import 'package:sqlite3/sqlite3.dart';

import 'wa_parser.dart';
import '../../core/l10n/l10n.dart';

/// Reads an iOS WhatsApp `ChatStorage.sqlite` (the Core Data store) into the
/// same [WaArchive] model the Android reader produces, so the browse/export UI
/// is shared.
///
/// iOS uses a completely different schema from Android: `ZWACHATSESSION`,
/// `ZWAMESSAGE`, `ZWAGROUPMEMBER`, `ZWAMEDIAITEM`, with Apple Core Data
/// timestamps (seconds since 2001-01-01).
abstract final class WaIosReader {
  // Core Data epoch (2001-01-01) in Unix seconds.
  static const _appleEpoch = 978307200;

  static int _toUnixMs(num? appleSeconds) =>
      appleSeconds == null ? 0 : ((appleSeconds + _appleEpoch) * 1000).round();

  static WaArchive readFile(String chatStorageDbPath) {
    final db = sqlite3.open(chatStorageDbPath, mode: OpenMode.readOnly);
    try {
      return read(db);
    } finally {
      db.close();
    }
  }

  static WaArchive read(Database db) {
    final tables = {
      for (final r in db.select(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        r['name'] as String,
    };
    if (!tables.contains('ZWAMESSAGE') || !tables.contains('ZWACHATSESSION')) {
      throw WaParseException(
        tr('This file is not an iOS WhatsApp ChatStorage.sqlite.'),
      );
    }

    final chatCols = _columns(db, 'ZWACHATSESSION');
    final msgCols = _columns(db, 'ZWAMESSAGE');

    // Chat sessions: Z_PK → (jid, name, isGroup).
    final sessionJid = <int, String>{};
    final sessions = <int, WaChat>{};
    final nameCol = chatCols.contains('ZPARTNERNAME') ? 'ZPARTNERNAME' : null;
    final typeCol = chatCols.contains('ZSESSIONTYPE') ? 'ZSESSIONTYPE' : null;
    for (final row in db.select(
      'SELECT Z_PK, ZCONTACTJID'
      '${nameCol == null ? '' : ', ZPARTNERNAME'}'
      '${typeCol == null ? '' : ', ZSESSIONTYPE'} FROM ZWACHATSESSION',
    )) {
      final jid = row['ZCONTACTJID'] as String?;
      if (jid == null || jid.isEmpty) continue;
      final pk = row['Z_PK'] as int;
      sessionJid[pk] = jid;
      final isGroup =
          jid.endsWith('@g.us') ||
          (typeCol != null && (row['ZSESSIONTYPE'] as int? ?? 0) == 1);
      final name = nameCol == null ? null : row['ZPARTNERNAME'] as String?;
      sessions[pk] = WaChat(
        jid: jid,
        name: (name != null && name.trim().isNotEmpty) ? name : _display(jid),
        isGroup: isGroup,
        messageCount: 0,
      );
    }

    // Group member Z_PK → sender JID.
    final memberJid = <int, String>{};
    if (tables.contains('ZWAGROUPMEMBER')) {
      final gmCols = _columns(db, 'ZWAGROUPMEMBER');
      final jidCol = gmCols.contains('ZMEMBERJID') ? 'ZMEMBERJID' : null;
      if (jidCol != null) {
        for (final row in db.select(
          'SELECT Z_PK, ZMEMBERJID FROM ZWAGROUPMEMBER',
        )) {
          final j = row['ZMEMBERJID'] as String?;
          if (j != null) memberJid[row['Z_PK'] as int] = j;
        }
      }
    }

    // Media item Z_PK → details.
    final media = <int, _IosMedia>{};
    if (tables.contains('ZWAMEDIAITEM')) {
      final miCols = _columns(db, 'ZWAMEDIAITEM');
      String? pick(List<String> c) => c.where(miCols.contains).firstOrNull;
      final pathCol = pick(['ZMEDIALOCALPATH', 'ZMEDIAURL']);
      final sizeCol = pick(['ZFILESIZE']);
      final titleCol = pick(['ZTITLE', 'ZVCARDNAME']);
      final cols = ['Z_PK', ?pathCol, ?sizeCol, ?titleCol];
      for (final row in db.select(
        'SELECT ${cols.join(', ')} FROM ZWAMEDIAITEM',
      )) {
        final path = pathCol == null ? null : row[pathCol] as String?;
        media[row['Z_PK'] as int] = _IosMedia(
          path: path,
          size: sizeCol == null ? null : (row[sizeCol] as num?)?.toInt(),
          name:
              (titleCol == null ? null : row[titleCol] as String?) ??
              path?.split('/').last,
        );
      }
    }

    final hasGroupMember = msgCols.contains('ZGROUPMEMBER');
    final hasMediaItem = msgCols.contains('ZMEDIAITEM');
    final textCol = msgCols.contains('ZTEXT') ? 'ZTEXT' : null;
    final typeMsgCol = msgCols.contains('ZMESSAGETYPE') ? 'ZMESSAGETYPE' : null;

    final select = [
      'ZCHATSESSION',
      'ZISFROMME',
      'ZMESSAGEDATE',
      ?textCol,
      ?typeMsgCol,
      if (hasGroupMember) 'ZGROUPMEMBER',
      if (hasMediaItem) 'ZMEDIAITEM',
    ].join(', ');

    final messages = <WaMessage>[];
    final counts = <String, int>{};
    final lastTs = <String, int>{};
    for (final row in db.select(
      'SELECT $select FROM ZWAMESSAGE WHERE ZCHATSESSION IS NOT NULL '
      'ORDER BY ZMESSAGEDATE ASC',
    )) {
      final jid = sessionJid[row['ZCHATSESSION'] as int?];
      if (jid == null) continue;
      final ts = _toUnixMs(row['ZMESSAGEDATE'] as num?);
      final m = hasMediaItem ? media[row['ZMEDIAITEM'] as int?] : null;
      final type = typeMsgCol == null ? 0 : (row[typeMsgCol] as int? ?? 0);
      messages.add(
        WaMessage(
          chatJid: jid,
          fromMe: ((row['ZISFROMME'] as int?) ?? 0) != 0,
          timestampMs: ts,
          kind: _kind(type, m),
          sender: hasGroupMember
              ? memberJid[row['ZGROUPMEMBER'] as int?]
              : null,
          text: textCol == null ? null : row[textCol] as String?,
          mediaName: m?.name,
          mediaPath: m?.path,
          mediaSize: m?.size,
        ),
      );
      counts[jid] = (counts[jid] ?? 0) + 1;
      if (ts > (lastTs[jid] ?? 0)) lastTs[jid] = ts;
    }

    final chats =
        [
          for (final s in sessions.values)
            WaChat(
              jid: s.jid,
              name: s.name,
              isGroup: s.isGroup,
              messageCount: counts[s.jid] ?? 0,
              lastTimestampMs: lastTs[s.jid],
            ),
        ]..sort(
          (a, b) => (b.lastTimestampMs ?? 0).compareTo(a.lastTimestampMs ?? 0),
        );

    return WaArchive(chats: chats, messages: messages);
  }

  static Set<String> _columns(Database db, String table) => {
    for (final r in db.select('PRAGMA table_info($table)')) r['name'] as String,
  };

  static String _display(String jid) {
    final user = jid.split('@').first;
    return jid.endsWith('@g.us') ? 'Group $user' : '+$user';
  }

  // iOS ZMESSAGETYPE values differ from Android's.
  static WaMediaKind _kind(int type, _IosMedia? media) {
    switch (type) {
      case 0:
        return WaMediaKind.none;
      case 1:
        return WaMediaKind.image;
      case 2:
        return WaMediaKind.video;
      case 3:
        return WaMediaKind.voice;
      case 4:
        return WaMediaKind.contact;
      case 5:
        return WaMediaKind.location;
      case 8:
      case 12:
        return WaMediaKind.document;
      case 11:
      case 14:
        return WaMediaKind.sticker;
      case 13:
        return WaMediaKind.gif;
    }
    return media == null ? WaMediaKind.none : WaMediaKind.document;
  }
}

class _IosMedia {
  const _IosMedia({this.path, this.size, this.name});

  final String? path;
  final int? size;
  final String? name;
}
