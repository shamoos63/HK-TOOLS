import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:sqlite3/sqlite3.dart';

import 'wa_parser.dart';
import '../../core/l10n/l10n.dart';

/// Result of [WaIosWriter.import].
class WaIosImportResult {
  const WaIosImportResult({
    required this.chatsCreated,
    required this.chatsMerged,
    required this.messagesAdded,
    required this.messagesSkipped,
    this.mediaFiles = const [],
    this.mediaMissing = 0,
    this.callsAdded = 0,
  });

  final int chatsCreated;
  final int chatsMerged;
  final int messagesAdded;

  /// Already present (same message id), or empty system events.
  final int messagesSkipped;

  /// Media files to place in the iPhone backup (one per media message).
  final List<WaIosMediaFile> mediaFiles;

  /// Media messages whose file wasn't on the Android phone (never downloaded,
  /// or deleted); these arrive as a labelled text message.
  final int mediaMissing;

  /// Calls added to the iPhone's call history.
  final int callsAdded;

  WaIosImportResult withCalls(int calls) => WaIosImportResult(
    chatsCreated: chatsCreated,
    chatsMerged: chatsMerged,
    messagesAdded: messagesAdded,
    messagesSkipped: messagesSkipped,
    mediaFiles: mediaFiles,
    mediaMissing: mediaMissing,
    callsAdded: calls,
  );
}

/// A media file to copy into the iPhone backup.
class WaIosMediaFile {
  const WaIosMediaFile({
    required this.localPath,
    required this.relativePath,
    required this.size,
  });

  /// The file pulled from the Android phone.
  final String localPath;

  /// Path inside WhatsApp's shared container on the iPhone
  /// (`Message/Media/<jid>/x/y/<id>.<ext>`).
  final String relativePath;
  final int size;
}

/// Local file for a media message, or `null` when it isn't available.
typedef WaMediaResolver = String? Function(WaMessage message);

/// Writes chats read from an Android `msgstore.db` ([WaArchive]) into an iOS
/// WhatsApp `ChatStorage.sqlite` (Core Data store).
///
/// The target should be the iPhone's own `ChatStorage.sqlite`, taken from a
/// fresh backup with WhatsApp already registered, so the schema matches the
/// installed WhatsApp exactly. Rows are inserted the way Core Data would
/// (`Z_PK`, `Z_ENT`, `Z_OPT`, `Z_PRIMARYKEY.Z_MAX`), and only into columns
/// the store actually has, so it tolerates schema changes between versions.
///
/// Field values follow the proven open-source importer (watoi): sent messages
/// get status 5 (delivered) and `toJID`, received ones `fromJID`; the Android
/// `key_id` becomes `stanzaID`. Photos, videos, GIFs, voice notes, audio and
/// documents become real media messages (a `ZWAMEDIAITEM` pointing at
/// `Message/Media/…`, the folder iOS WhatsApp reads `ZMEDIALOCALPATH` from)
/// when [WaMediaResolver] finds the file; otherwise, and for stickers,
/// contacts and locations, a labelled text placeholder.
abstract final class WaIosWriter {
  static const _appleEpoch = 978307200;

  static WaIosImportResult importFile(
    String chatStoragePath,
    WaArchive a, {
    WaMediaResolver? media,
  }) {
    final db = sqlite3.open(chatStoragePath);
    try {
      // A single self-contained file: no WAL left behind next to it.
      db.execute('PRAGMA journal_mode=DELETE');
      return import(db, a, media: media);
    } finally {
      db.close();
    }
  }

  static WaIosImportResult import(
    Database db,
    WaArchive archive, {
    WaMediaResolver? media,
  }) {
    final s = _Store(db);
    db.execute('BEGIN');
    try {
      final r = _import(s, archive, media);
      s.saveMax();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static WaIosImportResult _import(
    _Store s,
    WaArchive archive,
    WaMediaResolver? resolve,
  ) {
    var created = 0, merged = 0, added = 0, skipped = 0, missing = 0;
    final files = <WaIosMediaFile>[];
    final canMedia = s.has('ZWAMEDIAITEM');

    final byChat = <String, List<WaMessage>>{};
    for (final m in archive.messages) {
      byChat.putIfAbsent(m.chatJid, () => []).add(m);
    }

    for (final chat in archive.chats) {
      final jid = chat.jid;
      if (jid.isEmpty || jid.endsWith('@broadcast') || jid == 'status') {
        continue;
      }
      final msgs = (byChat[jid] ?? const <WaMessage>[])
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      final isGroup = chat.isGroup || jid.endsWith('@g.us');

      // ── chat session ──
      var sessionPk = s.existingSession(jid);
      if (sessionPk == null) {
        sessionPk = s.insert('ZWACHATSESSION', 'WAChatSession', {
          'ZCONTACTJID': jid,
          'ZPARTNERNAME': isGroup ? chat.name : jid.split('@').first,
          'ZSESSIONTYPE': isGroup ? 1 : 0,
          'ZARCHIVED': 0,
          'ZHIDDEN': 0,
          'ZREMOVED': 0,
          'ZUNREADCOUNT': 0,
          'ZFLAGS': 0,
          'ZMESSAGECOUNTER': 0,
        });
        created++;
        if (isGroup && s.has('ZWAGROUPINFO')) {
          final first = msgs.isEmpty ? null : msgs.first.timestampMs;
          final infoPk = s.insert('ZWAGROUPINFO', 'WAGroupInfo', {
            'ZCHATSESSION': sessionPk,
            'ZCREATIONDATE': first == null ? null : _apple(first),
          });
          s.update('ZWACHATSESSION', sessionPk, {'ZGROUPINFO': infoPk});
        }
      } else {
        merged++;
      }

      // ── messages ──
      final seen = s.stanzaIds(sessionPk);
      var sort = s.maxSort(sessionPk) + 1;
      int? lastPk;
      WaMessage? last;
      final members = <String, int?>{};
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        final text = _text(m);
        if (text == null) {
          skipped++;
          continue;
        }
        final stanza = (m.keyId != null && m.keyId!.isNotEmpty)
            ? m.keyId!
            : _syntheticId(jid, m, i);
        if (!seen.add(stanza)) {
          skipped++;
          continue;
        }
        int? memberPk;
        if (isGroup && !m.fromMe && m.sender != null && m.sender!.isNotEmpty) {
          memberPk = members[m.sender!] ??= s.groupMember(sessionPk, m.sender!);
        }
        final date = _apple(m.timestampMs);
        final iosType = _iosMediaType(m.kind);
        String? local;
        if (iosType != null && canMedia) {
          local = resolve?.call(m);
          if (local == null) missing++;
        }
        final caption = m.text?.trim();
        final pk = s.insert('ZWAMESSAGE', 'WAMessage', {
          'ZCHATSESSION': sessionPk,
          'ZISFROMME': m.fromMe ? 1 : 0,
          'ZMESSAGEDATE': date,
          'ZSENTDATE': date,
          'ZTEXT': local == null ? text : null,
          'ZMESSAGETYPE': local == null ? 0 : iosType,
          if (local != null) 'ZMEDIASECTIONID': _sectionId(m.timestampMs),
          'ZMESSAGESTATUS': m.fromMe ? 5 : 0,
          'ZFROMJID': m.fromMe ? null : jid,
          'ZTOJID': m.fromMe ? jid : null,
          'ZSTANZAID': stanza,
          'ZGROUPMEMBER': memberPk,
          'ZSORT': sort++,
          'ZDATAITEMVERSION': 2,
          'ZFLAGS': 0,
          'ZGROUPEVENTTYPE': 0,
          'ZSPOTLIGHTSTATUS': 0,
        });
        if (local != null) {
          final f = File(local);
          final ext = _ext(local, m);
          final id = crypto.sha1
              .convert(utf8.encode('$jid|$stanza'))
              .toString()
              .toUpperCase();
          final rel =
              'Media/$jid/${id[0]}/${id[1]}/'
              '${id.substring(2, 10)}-${id.substring(10, 14)}-'
              '${id.substring(14, 18)}-${id.substring(18, 22)}-'
              '${id.substring(22, 34)}$ext';
          final size = f.lengthSync();
          final itemPk = s.insert('ZWAMEDIAITEM', 'WAMediaItem', {
            'ZMESSAGE': pk,
            'ZMEDIALOCALPATH': rel,
            'ZFILESIZE': size,
            'ZMOVIEDURATION': m.mediaDurationSec,
            'ZTITLE': m.kind == WaMediaKind.document
                ? (m.mediaName ?? local.split(Platform.pathSeparator).last)
                : ((caption == null || caption.isEmpty) ? null : caption),
          });
          s.update('ZWAMESSAGE', pk, {'ZMEDIAITEM': itemPk});
          files.add(
            WaIosMediaFile(
              localPath: local,
              relativePath: 'Message/$rel',
              size: size,
            ),
          );
        }
        added++;
        lastPk = pk;
        last = m;
      }

      // ── session summary ──
      if (last != null) {
        // Android history can be older than messages already on the iPhone
        // (e.g. the test message): put the whole chat back in date order.
        final count = s.renumberSort(sessionPk);
        final lastDate = _apple(last.timestampMs);
        final current = s.lastMessageDate(sessionPk);
        s.update('ZWACHATSESSION', sessionPk, {
          'ZMESSAGECOUNTER': count ?? sort,
          if (current == null || current <= lastDate) ...{
            'ZLASTMESSAGE': lastPk,
            'ZLASTMESSAGEDATE': lastDate,
            'ZLASTMESSAGETEXT': _text(last),
          },
        });
      }
    }
    return WaIosImportResult(
      chatsCreated: created,
      chatsMerged: merged,
      messagesAdded: added,
      messagesSkipped: skipped,
      mediaFiles: files,
      mediaMissing: missing,
    );
  }

  /// iOS `ZMESSAGETYPE` for media that is moved as a real file.
  static int? _iosMediaType(WaMediaKind k) => switch (k) {
    WaMediaKind.image => 1,
    WaMediaKind.video || WaMediaKind.gif => 2,
    WaMediaKind.voice || WaMediaKind.audio => 3,
    WaMediaKind.document => 8,
    _ => null,
  };

  /// Media-gallery bucket (year-month).
  static String _sectionId(int unixMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  static String _ext(String local, WaMessage m) {
    final name = local.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 6) {
      return name.substring(dot).toLowerCase();
    }
    return switch (m.kind) {
      WaMediaKind.image => '.jpg',
      WaMediaKind.video || WaMediaKind.gif => '.mp4',
      WaMediaKind.voice => '.opus',
      WaMediaKind.audio => '.m4a',
      _ => '',
    };
  }

  static double _apple(int unixMs) => unixMs / 1000.0 - _appleEpoch;

  /// Text shown on the iPhone; media becomes a labelled placeholder (with the
  /// caption, if any). `null` for empty system events.
  static String? _text(WaMessage m) {
    final body = m.text?.trim();
    final label = switch (m.kind) {
      WaMediaKind.none => null,
      WaMediaKind.image => '📷 Photo',
      WaMediaKind.video => '🎥 Video',
      WaMediaKind.audio => '🎵 Audio',
      WaMediaKind.voice => '🎤 Voice message',
      WaMediaKind.document => '📄 ${m.mediaName ?? 'Document'}',
      WaMediaKind.sticker => 'Sticker',
      WaMediaKind.gif => 'GIF',
      WaMediaKind.contact => '👤 Contact',
      WaMediaKind.location => '📍 Location',
    };
    if (label == null) return (body == null || body.isEmpty) ? null : body;
    return (body == null || body.isEmpty) ? '[$label]' : '[$label] $body';
  }

  static String _syntheticId(String jid, WaMessage m, int i) {
    final h = crypto.sha1.convert(
      utf8.encode('$jid|${m.timestampMs}|${m.fromMe}|$i|${m.text}'),
    );
    return 'HK${h.toString().substring(0, 18).toUpperCase()}';
  }
}

/// Core Data bookkeeping over the raw SQLite store.
class _Store {
  _Store(this.db) {
    for (final r in db.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )) {
      final t = r['name'] as String;
      _cols[t] = {
        for (final c in db.select('PRAGMA table_info("$t")'))
          c['name'] as String,
      };
    }
    if (!has('ZWAMESSAGE') || !has('ZWACHATSESSION') || !has('Z_PRIMARYKEY')) {
      throw WaParseException(
        tr('The iPhone database is not a WhatsApp ChatStorage.sqlite.'),
      );
    }
    for (final r in db.select(
      'SELECT Z_ENT, Z_NAME, Z_MAX FROM Z_PRIMARYKEY',
    )) {
      _ent[r['Z_NAME'] as String] = r['Z_ENT'] as int;
      _max[r['Z_NAME'] as String] = (r['Z_MAX'] as int?) ?? 0;
    }
  }

  final Database db;
  final _cols = <String, Set<String>>{};
  final _ent = <String, int>{};
  final _max = <String, int>{};

  bool has(String table) => _cols.containsKey(table);

  int _nextPk(String table, String entity) {
    // Z_MAX is shared across an entity hierarchy's table; never go below the
    // highest existing key either.
    final inTable =
        db.select('SELECT MAX(Z_PK) AS m FROM "$table"').first['m'] as int? ??
        0;
    final next = (_max[entity] ?? 0) > inTable
        ? _max[entity]! + 1
        : inTable + 1;
    _max[entity] = next;
    return next;
  }

  int insert(String table, String entity, Map<String, Object?> values) {
    final ent = _ent[entity];
    if (ent == null) {
      throw WaParseException(
        trf(
          'This WhatsApp version stores {0} differently; the transfer can\'t write to it.',
          [entity],
        ),
      );
    }
    final pk = _nextPk(table, entity);
    final cols = _cols[table]!;
    final row = <String, Object?>{
      'Z_PK': pk,
      'Z_ENT': ent,
      'Z_OPT': 1,
      for (final e in values.entries)
        if (cols.contains(e.key)) e.key: e.value,
    };
    db.execute(
      'INSERT INTO "$table" (${row.keys.join(', ')}) '
      'VALUES (${List.filled(row.length, '?').join(', ')})',
      row.values.toList(),
    );
    return pk;
  }

  void update(String table, int pk, Map<String, Object?> values) {
    final cols = _cols[table]!;
    final set = {
      for (final e in values.entries)
        if (cols.contains(e.key)) e.key: e.value,
    };
    if (set.isEmpty) return;
    db.execute(
      'UPDATE "$table" SET ${set.keys.map((k) => '$k = ?').join(', ')} '
      'WHERE Z_PK = ?',
      [...set.values, pk],
    );
  }

  int? existingSession(String jid) =>
      db.select(
            'SELECT Z_PK FROM ZWACHATSESSION WHERE ZCONTACTJID = ? '
            'ORDER BY Z_PK LIMIT 1',
            [jid],
          ).firstOrNull?['Z_PK']
          as int?;

  Set<String> stanzaIds(int session) {
    if (!_cols['ZWAMESSAGE']!.contains('ZSTANZAID')) return {};
    return {
      for (final r in db.select(
        'SELECT ZSTANZAID FROM ZWAMESSAGE WHERE ZCHATSESSION = ? '
        'AND ZSTANZAID IS NOT NULL',
        [session],
      ))
        r['ZSTANZAID'] as String,
    };
  }

  int maxSort(int session) {
    if (!_cols['ZWAMESSAGE']!.contains('ZSORT')) return -1;
    return (db.select(
              'SELECT MAX(ZSORT) AS m FROM ZWAMESSAGE WHERE ZCHATSESSION = ?',
              [session],
            ).first['m']
            as int?) ??
        -1;
  }

  /// Renumbers `ZSORT` of a chat by message date; returns the message count
  /// (or `null` when the store has no `ZSORT`).
  int? renumberSort(int session) {
    if (!_cols['ZWAMESSAGE']!.contains('ZSORT')) return null;
    db.execute(
      'WITH r AS (SELECT Z_PK, ROW_NUMBER() OVER '
      '(ORDER BY ZMESSAGEDATE, Z_PK) - 1 AS rn FROM ZWAMESSAGE '
      'WHERE ZCHATSESSION = ?) '
      'UPDATE ZWAMESSAGE SET ZSORT = '
      '(SELECT rn FROM r WHERE r.Z_PK = ZWAMESSAGE.Z_PK) '
      'WHERE ZCHATSESSION = ?',
      [session, session],
    );
    return db.select(
          'SELECT COUNT(*) AS c FROM ZWAMESSAGE WHERE ZCHATSESSION = ?',
          [session],
        ).first['c']
        as int;
  }

  double? lastMessageDate(int session) {
    if (!_cols['ZWACHATSESSION']!.contains('ZLASTMESSAGEDATE')) return null;
    return (db.select(
              'SELECT ZLASTMESSAGEDATE AS d FROM ZWACHATSESSION WHERE Z_PK = ?',
              [session],
            ).first['d']
            as num?)
        ?.toDouble();
  }

  int? groupMember(int session, String memberJid) {
    if (!has('ZWAGROUPMEMBER')) return null;
    final existing = db.select(
      'SELECT Z_PK FROM ZWAGROUPMEMBER WHERE ZCHATSESSION = ? '
      'AND ZMEMBERJID = ? LIMIT 1',
      [session, memberJid],
    ).firstOrNull;
    if (existing != null) return existing['Z_PK'] as int;
    return insert('ZWAGROUPMEMBER', 'WAGroupMember', {
      'ZCHATSESSION': session,
      'ZMEMBERJID': memberJid,
      'ZCONTACTNAME': memberJid.split('@').first,
      'ZISACTIVE': 0,
      'ZISADMIN': 0,
    });
  }

  void saveMax() {
    for (final e in _max.entries) {
      db.execute('UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = ?', [
        e.value,
        e.key,
      ]);
    }
  }
}
