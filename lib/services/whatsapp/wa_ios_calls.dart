import 'package:sqlite3/sqlite3.dart';

import 'wa_parser.dart';
import '../../core/l10n/l10n.dart';

/// Writes Android call history into the iPhone's WhatsApp
/// `CallHistory.sqlite` (a Core Data store in the same shared container as
/// `ChatStorage.sqlite`).
///
/// Layout, as read by the public iOS WhatsApp parsers:
///  * `ZWAAGGREGATECALLEVENT`: one row per call as shown in the Calls tab
///    (`ZINCOMING`, `ZMISSED`, `ZVIDEO`);
///  * `ZWACDCALLEVENT`: the call itself (`ZDATE`, `ZDURATION`, `ZOUTCOME`,
///    `ZCALLIDSTRING`, `ZGROUPJIDSTRING`), linked to its aggregate by
///    `Z1CALLEVENTS` (older versions: `ZAGGREGATECALLEVENT`);
///  * `ZWACDCALLEVENTPARTICIPANT`: who was on it (`ZJIDSTRING`, `ZOUTCOME`),
///    linked by `Z1PARTICIPANTS` (older: `ZCALLEVENT`).
///
/// As with chats, the iPhone's own (empty) store is the template, and only
/// columns that exist are written. `ZOUTCOME`: 0 completed, 1 missed / not
/// answered, 2 failed, 4 rejected.
abstract final class WaIosCallWriter {
  static const _appleEpoch = 978307200;

  /// Adds [calls] to the store at [path]; returns how many were added (calls
  /// already present, by call id, are skipped).
  static int importFile(String path, List<WaCall> calls) {
    if (calls.isEmpty) return 0;
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA journal_mode=DELETE');
      return import(db, calls);
    } finally {
      db.close();
    }
  }

  static int import(Database db, List<WaCall> calls) {
    final cols = <String, Set<String>>{};
    for (final r in db.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )) {
      final t = r['name'] as String;
      cols[t] = {
        for (final c in db.select('PRAGMA table_info("$t")'))
          c['name'] as String,
      };
    }
    const agg = 'ZWAAGGREGATECALLEVENT';
    const ev = 'ZWACDCALLEVENT';
    const part = 'ZWACDCALLEVENTPARTICIPANT';
    if (!cols.containsKey(ev) || !cols.containsKey('Z_PRIMARYKEY')) {
      throw WaParseException(
        tr(
          'The iPhone\'s call history has an unexpected layout; calls were not moved.',
        ),
      );
    }

    // Core Data entity per table: table "Z" + upper-case entity name.
    final ent = <String, int>{};
    final max = <String, int>{};
    final entName = <String, String>{};
    for (final r in db.select(
      'SELECT Z_ENT, Z_NAME, Z_MAX FROM Z_PRIMARYKEY',
    )) {
      final name = r['Z_NAME'] as String;
      final table = 'Z${name.toUpperCase()}';
      ent[table] = r['Z_ENT'] as int;
      max[table] = (r['Z_MAX'] as int?) ?? 0;
      entName[table] = name;
    }

    int insert(String table, Map<String, Object?> values) {
      final have = cols[table]!;
      final inTable =
          db.select('SELECT MAX(Z_PK) AS m FROM "$table"').first['m'] as int? ??
          0;
      final pk = ((max[table] ?? 0) > inTable ? max[table]! : inTable) + 1;
      max[table] = pk;
      final row = <String, Object?>{
        'Z_PK': pk,
        if (ent[table] != null) 'Z_ENT': ent[table],
        'Z_OPT': 1,
        for (final e in values.entries)
          if (have.contains(e.key)) e.key: e.value,
      };
      db.execute(
        'INSERT INTO "$table" (${row.keys.join(', ')}) '
        'VALUES (${List.filled(row.length, '?').join(', ')})',
        row.values.toList(),
      );
      return pk;
    }

    String? fk(String table, List<String> names) =>
        names.where((n) => cols[table]?.contains(n) ?? false).firstOrNull;
    final evToAgg = fk(ev, ['Z1CALLEVENTS', 'ZAGGREGATECALLEVENT']);
    final partToEv = fk(part, ['Z1PARTICIPANTS', 'ZCALLEVENT']);

    final known = <String>{
      if (cols[ev]!.contains('ZCALLIDSTRING'))
        for (final r in db.select(
          'SELECT ZCALLIDSTRING FROM $ev WHERE ZCALLIDSTRING IS NOT NULL',
        ))
          r['ZCALLIDSTRING'] as String,
    };

    var added = 0;
    db.execute('BEGIN');
    try {
      for (final c in calls) {
        if (c.callId != null && !known.add(c.callId!)) continue;
        final date = c.timestampMs / 1000.0 - _appleEpoch;
        final outcome = switch (c.outcome) {
          WaCallOutcome.completed => 0,
          WaCallOutcome.missed => 1,
          WaCallOutcome.failed => 2,
          WaCallOutcome.rejected => 4,
        };
        final missed = !c.fromMe && c.outcome != WaCallOutcome.completed;
        int? aggPk;
        if (cols.containsKey(agg)) {
          aggPk = insert(agg, {
            'ZINCOMING': c.fromMe ? 0 : 1,
            'ZMISSED': missed ? 1 : 0,
            'ZMISSEDREASON': 0,
            'ZVIDEO': c.video ? 1 : 0,
            'ZGROUPJIDSTRING': c.groupJid,
          });
        }
        final evPk = insert(ev, {
          'ZDATE': date,
          'ZDURATION': c.durationSec.toDouble(),
          'ZOUTCOME': outcome,
          'ZVIDEO': c.video ? 1 : 0,
          'ZCALLIDSTRING': c.callId,
          'ZGROUPJIDSTRING': c.groupJid,
          'ZGROUPCALLCREATORUSERJIDSTRING': c.groupJid == null
              ? null
              : (c.fromMe ? null : c.jid),
          'ZBYTESSENT': 0,
          'ZBYTESRECEIVED': 0,
          ?evToAgg: aggPk,
        });
        if (cols.containsKey(part)) {
          insert(part, {
            'ZJIDSTRING': c.jid,
            'ZOUTCOME': outcome,
            ?partToEv: evPk,
          });
        }
        added++;
      }
      for (final e in max.entries) {
        final name = entName[e.key];
        if (name == null) continue;
        db.execute('UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = ?', [
          e.value,
          name,
        ]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return added;
  }
}
