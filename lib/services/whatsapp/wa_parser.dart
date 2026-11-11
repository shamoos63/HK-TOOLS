import 'package:sqlite3/sqlite3.dart';

import '../../core/l10n/l10n.dart';

/// Reads chats and messages out of a decrypted WhatsApp `msgstore.db`.
///
/// Handles the modern schema (`message` / `chat` / `jid`, WhatsApp 2021+) and
/// falls back to the legacy schema (`messages` / `chat_list`) used by older
/// backups. The original wa-transfer read only the legacy tables, which newer
/// WhatsApp no longer populates — the main reason its parser returned nothing.
class WaChat {
  const WaChat({
    required this.jid,
    required this.name,
    required this.isGroup,
    required this.messageCount,
    this.lastTimestampMs,
  });

  final String jid;
  final String name;
  final bool isGroup;
  final int messageCount;
  final int? lastTimestampMs;
}

enum WaMediaKind {
  none,
  image,
  video,
  audio,
  voice,
  document,
  sticker,
  gif,
  contact,
  location,
}

class WaMessage {
  const WaMessage({
    required this.chatJid,
    required this.fromMe,
    required this.timestampMs,
    required this.kind,
    this.sender,
    this.text,
    this.mediaName,
    this.mediaMime,
    this.mediaPath,
    this.mediaSize,
    this.keyId,
    this.mediaDurationSec,
  });

  final String chatJid;
  final bool fromMe;
  final int timestampMs;
  final WaMediaKind kind;

  /// Group sender (phone/JID), null for 1:1 or own messages.
  final String? sender;
  final String? text;
  final String? mediaName;
  final String? mediaMime;

  /// Relative path inside the WhatsApp media folder, when known.
  final String? mediaPath;
  final int? mediaSize;

  /// WhatsApp's own message id (`key_id`), unique per chat. Used as the iOS
  /// `ZSTANZAID` when transferring to an iPhone.
  final String? keyId;

  /// Length of a video / voice note / audio, in seconds, when known.
  final int? mediaDurationSec;

  bool get isMedia => kind != WaMediaKind.none;
}

enum WaCallOutcome { completed, missed, failed, rejected }

/// One call from WhatsApp's call log.
class WaCall {
  const WaCall({
    required this.jid,
    required this.fromMe,
    required this.timestampMs,
    required this.durationSec,
    required this.video,
    required this.outcome,
    this.callId,
    this.groupJid,
  });

  /// The other person.
  final String jid;
  final bool fromMe;
  final int timestampMs;
  final int durationSec;
  final bool video;
  final WaCallOutcome outcome;
  final String? callId;

  /// Set for group calls.
  final String? groupJid;
}

class WaArchive {
  const WaArchive({
    required this.chats,
    required this.messages,
    this.calls = const [],
  });

  final List<WaChat> chats;
  final List<WaMessage> messages;

  /// Call history (Android backups only).
  final List<WaCall> calls;

  int get chatCount => chats.length;
  int get messageCount => messages.length;
  int get mediaCount => messages.where((m) => m.isMedia).length;

  List<WaMessage> messagesFor(String jid) =>
      messages.where((m) => m.chatJid == jid).toList();
}

class WaParseException implements Exception {
  WaParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class WaParser {
  /// Opens the decrypted database at [dbPath] and reads it into a [WaArchive].
  static WaArchive parseFile(String dbPath) {
    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      return parse(db);
    } finally {
      db.close();
    }
  }

  static WaArchive parse(Database db) {
    final tables = _tables(db);
    if (tables.contains('message') && tables.contains('chat')) {
      return _parseModern(db, tables);
    }
    if (tables.contains('messages')) {
      return _parseLegacy(db, tables);
    }
    throw WaParseException(
      tr('This file is not a recognised WhatsApp message database.'),
    );
  }

  // ───────────────────────── modern schema ─────────────────────────

  static WaArchive _parseModern(Database db, Set<String> tables) {
    final hasMedia = tables.contains('message_media');
    final msgCols = _columns(db, 'message');
    final chatCols = _columns(db, 'chat');

    // jid._id → raw JID string.
    final jids = <int, String>{};
    for (final row in db.select(
      'SELECT _id, user, server, raw_string FROM jid',
    )) {
      final raw =
          (row['raw_string'] as String?) ??
          '${row['user'] ?? ''}@${row['server'] ?? ''}';
      jids[row['_id'] as int] = raw;
    }
    // Newer WhatsApp addresses many people by a privacy id (`…@lid`) instead
    // of their phone number. `jid_map` links the two; prefer the phone JID so
    // chats and group senders line up with the iPhone's contacts.
    if (tables.contains('jid_map')) {
      for (final row in db.select(
        'SELECT lid_row_id, jid_row_id FROM jid_map',
      )) {
        final lid = row['lid_row_id'] as int?;
        final pn = jids[row['jid_row_id'] as int?];
        if (lid != null && pn != null && jids.containsKey(lid)) {
          jids[lid] = pn;
        }
      }
    }

    final subjectCol = chatCols.contains('subject') ? 'subject' : null;
    final chatRows = db.select(
      'SELECT _id, jid_row_id${subjectCol == null ? '' : ', subject'} FROM chat',
    );
    final chatJidById = <int, String>{};
    final chatSubject = <int, String?>{};
    for (final row in chatRows) {
      final jid = jids[row['jid_row_id'] as int?] ?? '';
      if (jid.isEmpty) continue;
      chatJidById[row['_id'] as int] = jid;
      chatSubject[row['_id'] as int] = subjectCol == null
          ? null
          : row['subject'] as String?;
    }

    final senderCol = msgCols.contains('sender_jid_row_id')
        ? 'sender_jid_row_id'
        : null;
    final typeCol = msgCols.contains('message_type')
        ? 'message_type'
        : (msgCols.contains('type') ? 'type' : null);
    final textCol = msgCols.contains('text_data') ? 'text_data' : null;
    final keyCol = msgCols.contains('key_id') ? 'key_id' : null;

    final media = hasMedia ? _mediaByMessage(db) : const <int, _Media>{};

    final messages = <WaMessage>[];
    final counts = <String, int>{};
    final lastTs = <String, int>{};

    final sql = StringBuffer('SELECT _id, chat_row_id, from_me, timestamp')
      ..write(textCol == null ? '' : ', $textCol')
      ..write(typeCol == null ? '' : ', $typeCol')
      ..write(senderCol == null ? '' : ', $senderCol')
      ..write(keyCol == null ? '' : ', $keyCol')
      ..write(
        ' FROM message WHERE chat_row_id IS NOT NULL ORDER BY timestamp ASC',
      );

    for (final row in db.select(sql.toString())) {
      final chatId = row['chat_row_id'] as int?;
      final jid = chatId == null ? null : chatJidById[chatId];
      if (jid == null) continue;
      final ts = (row['timestamp'] as int?) ?? 0;
      final type = typeCol == null ? 0 : (row[typeCol] as int?) ?? 0;
      final m = media[row['_id'] as int];
      messages.add(
        WaMessage(
          chatJid: jid,
          fromMe: ((row['from_me'] as int?) ?? 0) != 0,
          timestampMs: ts,
          kind: _kindFromType(type, m?.mime),
          sender: senderCol == null ? null : jids[row[senderCol] as int?],
          text: textCol == null ? null : row[textCol] as String?,
          mediaName: m?.name,
          mediaMime: m?.mime,
          mediaPath: m?.path,
          mediaSize: m?.size,
          keyId: keyCol == null ? null : row[keyCol] as String?,
          mediaDurationSec: m?.duration,
        ),
      );
      counts[jid] = (counts[jid] ?? 0) + 1;
      if (ts > (lastTs[jid] ?? 0)) lastTs[jid] = ts;
    }

    final chats = <WaChat>[];
    final seenChats = <String>{};
    for (final entry in chatJidById.entries) {
      final jid = entry.value;
      if (!seenChats.add(jid)) continue; // a LID chat merged into its number
      final isGroup = jid.endsWith('@g.us');
      chats.add(
        WaChat(
          jid: jid,
          name: chatSubject[entry.key]?.trim().isNotEmpty == true
              ? chatSubject[entry.key]!
              : _displayFromJid(jid),
          isGroup: isGroup,
          messageCount: counts[jid] ?? 0,
          lastTimestampMs: lastTs[jid],
        ),
      );
    }
    _sortChats(chats);
    return WaArchive(
      chats: chats,
      messages: messages,
      calls: tables.contains('call_log') ? _calls(db, jids) : const [],
    );
  }

  /// Android `call_log`; [jids] already maps privacy ids to numbers.
  static List<WaCall> _calls(Database db, Map<int, String> jids) {
    final cols = _columns(db, 'call_log');
    if (!cols.contains('jid_row_id') || !cols.contains('timestamp')) {
      return const [];
    }
    String col(String c, String fallback) => cols.contains(c) ? c : fallback;
    final rows = db.select(
      'SELECT jid_row_id, ${col('from_me', '0')} AS from_me, timestamp, '
      '${col('video_call', '0')} AS video_call, '
      '${col('duration', '0')} AS duration, '
      '${col('call_result', 'NULL')} AS call_result, '
      '${col('call_id', 'NULL')} AS call_id, '
      '${col('group_jid_row_id', 'NULL')} AS group_jid_row_id '
      'FROM call_log ORDER BY timestamp',
    );
    return [
      for (final r in rows)
        if (jids[r['jid_row_id'] as int?] case final jid?)
          WaCall(
            jid: jid,
            fromMe: ((r['from_me'] as int?) ?? 0) != 0,
            timestampMs: (r['timestamp'] as int?) ?? 0,
            durationSec: (r['duration'] as int?) ?? 0,
            video: ((r['video_call'] as int?) ?? 0) != 0,
            outcome: _callOutcome(
              r['call_result'] as int?,
              (r['duration'] as int?) ?? 0,
            ),
            callId: r['call_id'] as String?,
            groupJid: jids[r['group_jid_row_id'] as int?],
          ),
    ];
  }

  /// Android `call_result`: 5 = completed, 2/0/4/7 = not answered or
  /// cancelled, 3 = unavailable. A call with talk time always completed.
  static WaCallOutcome _callOutcome(int? result, int duration) {
    if (duration > 0 || result == 5) return WaCallOutcome.completed;
    return switch (result) {
      3 => WaCallOutcome.failed,
      1 || 6 => WaCallOutcome.rejected,
      _ => WaCallOutcome.missed,
    };
  }

  static Map<int, _Media> _mediaByMessage(Database db) {
    final cols = _columns(db, 'message_media');
    final keyCol = cols.contains('message_row_id')
        ? 'message_row_id'
        : (cols.contains('message_id') ? 'message_id' : null);
    if (keyCol == null) return const {};
    String? pick(List<String> names) => names.where(cols.contains).firstOrNull;
    final pathCol = pick(['file_path', 'media_path']);
    final mimeCol = pick(['mime_type', 'media_mime_type']);
    final sizeCol = pick(['file_size', 'media_size']);
    final nameCol = pick(['media_name', 'file_name', 'original_file_name']);
    final durCol = pick(['media_duration']);

    final out = <int, _Media>{};
    final select = [
      keyCol,
      ?pathCol,
      ?mimeCol,
      ?sizeCol,
      ?nameCol,
      ?durCol,
    ].join(', ');
    for (final row in db.select('SELECT $select FROM message_media')) {
      final id = row[keyCol] as int?;
      if (id == null) continue;
      final path = pathCol == null ? null : row[pathCol] as String?;
      out[id] = _Media(
        path: path,
        mime: mimeCol == null ? null : row[mimeCol] as String?,
        size: sizeCol == null ? null : (row[sizeCol] as int?),
        name:
            (nameCol == null ? null : row[nameCol] as String?) ??
            path?.split('/').last,
        duration: durCol == null ? null : (row[durCol] as num?)?.toInt(),
      );
    }
    return out;
  }

  // ───────────────────────── legacy schema ─────────────────────────

  static WaArchive _parseLegacy(Database db, Set<String> tables) {
    final msgCols = _columns(db, 'messages');
    final textCol = msgCols.contains('data') ? 'data' : null;
    final mimeCol = msgCols.contains('media_mime_type')
        ? 'media_mime_type'
        : null;
    final nameCol = msgCols.contains('media_name') ? 'media_name' : null;
    final sizeCol = msgCols.contains('media_size') ? 'media_size' : null;
    final senderCol = msgCols.contains('remote_resource')
        ? 'remote_resource'
        : null;
    final keyCol = msgCols.contains('key_id') ? 'key_id' : null;

    final subjects = <String, String>{};
    if (tables.contains('chat_list')) {
      for (final row in db.select(
        'SELECT key_remote_jid, subject FROM chat_list',
      )) {
        final jid = row['key_remote_jid'] as String?;
        final subject = row['subject'] as String?;
        if (jid != null && subject != null && subject.isNotEmpty) {
          subjects[jid] = subject;
        }
      }
    }

    final messages = <WaMessage>[];
    final counts = <String, int>{};
    final lastTs = <String, int>{};
    final select = [
      'key_remote_jid',
      'key_from_me',
      'timestamp',
      ?textCol,
      ?mimeCol,
      ?nameCol,
      ?sizeCol,
      ?senderCol,
      ?keyCol,
    ].join(', ');
    for (final row in db.select(
      'SELECT $select FROM messages WHERE key_remote_jid IS NOT NULL '
      'ORDER BY timestamp ASC',
    )) {
      final jid = row['key_remote_jid'] as String?;
      if (jid == null || jid == '-1' || jid.endsWith('@broadcast')) continue;
      final ts = (row['timestamp'] as int?) ?? 0;
      final mime = mimeCol == null ? null : row[mimeCol] as String?;
      messages.add(
        WaMessage(
          chatJid: jid,
          fromMe: ((row['key_from_me'] as int?) ?? 0) != 0,
          timestampMs: ts,
          kind: _kindFromType(mime == null ? 0 : 1, mime),
          sender: senderCol == null ? null : row[senderCol] as String?,
          text: textCol == null ? null : row[textCol] as String?,
          mediaMime: mime,
          mediaName: nameCol == null ? null : row[nameCol] as String?,
          mediaSize: sizeCol == null ? null : row[sizeCol] as int?,
          keyId: keyCol == null ? null : row[keyCol] as String?,
        ),
      );
      counts[jid] = (counts[jid] ?? 0) + 1;
      if (ts > (lastTs[jid] ?? 0)) lastTs[jid] = ts;
    }

    final chats = [
      for (final jid in counts.keys)
        WaChat(
          jid: jid,
          name: subjects[jid] ?? _displayFromJid(jid),
          isGroup: jid.endsWith('@g.us'),
          messageCount: counts[jid]!,
          lastTimestampMs: lastTs[jid],
        ),
    ];
    _sortChats(chats);
    return WaArchive(chats: chats, messages: messages);
  }

  // ───────────────────────── helpers ─────────────────────────

  static Set<String> _tables(Database db) => {
    for (final r in db.select(
      "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
    ))
      r['name'] as String,
  };

  static Set<String> _columns(Database db, String table) => {
    for (final r in db.select('PRAGMA table_info($table)')) r['name'] as String,
  };

  static void _sortChats(List<WaChat> chats) => chats.sort(
    (a, b) => (b.lastTimestampMs ?? 0).compareTo(a.lastTimestampMs ?? 0),
  );

  static String _displayFromJid(String jid) {
    final user = jid.split('@').first;
    if (jid.endsWith('@g.us')) return 'Group $user';
    return '+$user';
  }

  static WaMediaKind _kindFromType(int type, String? mime) {
    // WhatsApp message_type values.
    switch (type) {
      case 1:
        return WaMediaKind.image;
      case 2:
        return (mime?.contains('audio') ?? false)
            ? WaMediaKind.voice
            : WaMediaKind.audio;
      case 3:
        return WaMediaKind.video;
      case 4:
        return WaMediaKind.contact;
      case 5:
      case 16:
        return WaMediaKind.location;
      case 9:
        return WaMediaKind.document;
      case 13:
        return WaMediaKind.gif;
      case 20:
      case 15:
        return WaMediaKind.sticker;
    }
    if (mime == null) return WaMediaKind.none;
    if (mime.startsWith('image/')) return WaMediaKind.image;
    if (mime.startsWith('video/')) return WaMediaKind.video;
    if (mime.startsWith('audio/')) return WaMediaKind.audio;
    return WaMediaKind.document;
  }
}

class _Media {
  const _Media({this.path, this.mime, this.size, this.name, this.duration});

  final String? path;
  final String? mime;
  final int? size;
  final String? name;
  final int? duration;
}
