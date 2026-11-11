import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:sqlite3/sqlite3.dart';

import '../../core/l10n/l10n.dart';
import 'wa_parser.dart';

/// A media file to put on the Android phone.
class WaAndroidMediaFile {
  const WaAndroidMediaFile({
    required this.localPath,
    required this.relativePath,
  });

  /// The file taken from the iPhone backup.
  final String localPath;

  /// Path under the WhatsApp folder on the phone, e.g.
  /// `Media/WhatsApp Images/1234567890.jpg` (what `message_media.file_path`
  /// stores).
  final String relativePath;
}

class WaAndroidImportResult {
  const WaAndroidImportResult({
    required this.chatsCreated,
    required this.chatsMerged,
    required this.messagesAdded,
    required this.messagesSkipped,
    required this.mediaFiles,
    required this.mediaMissing,
  });

  final int chatsCreated;
  final int chatsMerged;
  final int messagesAdded;
  final int messagesSkipped;
  final List<WaAndroidMediaFile> mediaFiles;
  final int mediaMissing;
}

/// Writes chats read from an iPhone (`ChatStorage.sqlite` → [WaArchive]) into
/// an Android `msgstore.db`: the phone's own database, decrypted from the
/// backup WhatsApp just made, so its schema matches the installed version and
/// its existing chats are kept.
///
/// Rows go into `jid`, `chat`, `message` and `message_media`, only into
/// columns that exist. Messages already present (same `key_id`) are skipped,
/// and every chat touched is put back in date order (`sort_id`), since the
/// iPhone history is usually older than what the Android phone already has.
abstract final class WaAndroidWriter {
  static WaAndroidImportResult importFile(
    String msgstorePath,
    WaArchive archive, {
    String? Function(WaMessage message)? media,
    bool business = false,
  }) {
    final db = sqlite3.open(msgstorePath);
    try {
      db.execute('PRAGMA journal_mode=DELETE');
      return import(db, archive, media: media, business: business);
    } finally {
      db.close();
    }
  }

  static WaAndroidImportResult import(
    Database db,
    WaArchive archive, {
    String? Function(WaMessage message)? media,
    bool business = false,
  }) {
    final s = _Store(db);
    db.execute('BEGIN');
    try {
      final r = _import(
        s,
        archive,
        media,
        business ? 'WhatsApp Business' : 'WhatsApp',
      );
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static WaAndroidImportResult _import(
    _Store s,
    WaArchive archive,
    String? Function(WaMessage)? resolve,
    String app,
  ) {
    var created = 0, merged = 0, added = 0, skipped = 0, missing = 0;
    final files = <WaAndroidMediaFile>[];
    final canMedia = s.has('message_media');

    final byChat = <String, List<WaMessage>>{};
    for (final m in archive.messages) {
      byChat.putIfAbsent(m.chatJid, () => []).add(m);
    }

    for (final chat in archive.chats) {
      final jid = chat.jid;
      if (jid.isEmpty || jid.endsWith('@broadcast') || !jid.contains('@')) {
        continue;
      }
      final msgs = (byChat[jid] ?? const <WaMessage>[])
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      final isGroup = chat.isGroup || jid.endsWith('@g.us');
      final jidRow = s.jid(jid);

      var chatRow = s.chatFor(jidRow);
      if (chatRow == null) {
        chatRow = s.insert('chat', {
          'jid_row_id': jidRow,
          'hidden': 0,
          'subject': isGroup ? chat.name : null,
          'created_timestamp': msgs.isEmpty ? null : msgs.first.timestampMs,
          'archived': 0,
          'sort_timestamp': msgs.isEmpty ? 0 : msgs.last.timestampMs,
          'unseen_message_count': 0,
          'unseen_missed_calls_count': 0,
          'unseen_row_count': 0,
          'unseen_important_message_count': 0,
          'group_type': 0,
          'plaintext_disabled': 1,
        });
        created++;
      } else {
        merged++;
      }

      final seen = s.keyIds(chatRow);
      var any = false;
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        final keyId = (m.keyId != null && m.keyId!.isNotEmpty)
            ? m.keyId!
            : _syntheticId(jid, m, i);
        if (!seen.add('${m.fromMe ? 1 : 0}|$keyId')) {
          skipped++;
          continue;
        }
        final kind = _androidMedia(m.kind, app, m.fromMe);
        String? local;
        if (kind != null && canMedia) {
          local = resolve?.call(m);
          if (local == null) missing++;
        }
        final caption = _caption(m);
        final text = local != null ? caption : _text(m);
        if (text == null && local == null) {
          skipped++;
          continue;
        }
        final sender = isGroup && !m.fromMe && (m.sender?.isNotEmpty ?? false)
            ? s.jid(m.sender!)
            : null;
        final rowId = s.insert('message', {
          'chat_row_id': chatRow,
          'from_me': m.fromMe ? 1 : 0,
          'key_id': keyId,
          'sender_jid_row_id': sender,
          'status': m.fromMe ? 13 : 0,
          'broadcast': 0,
          'recipient_count': 0,
          'origination_flags': 0,
          'origin': 0,
          'timestamp': m.timestampMs,
          'received_timestamp': m.timestampMs,
          'receipt_server_timestamp': m.fromMe ? m.timestampMs : -1,
          'message_type': local == null ? 0 : kind!.type,
          'text_data': text,
          'starred': 0,
          'lookup_tables': 0,
          'message_add_on_flags': 0,
          'sort_id': 0,
        });
        s.update('message', rowId, {'sort_id': rowId});
        if (local != null) {
          final f = File(local);
          final rel = '${kind!.folder}/${_fileName(jid, keyId, local, m)}';
          s.insertRaw('message_media', {
            'message_row_id': rowId,
            'chat_row_id': chatRow,
            'autotransfer_retry_enabled': 0,
            'transferred': 1,
            'transcoded': 0,
            'file_path': rel,
            'file_size': f.lengthSync(),
            'file_length': f.lengthSync(),
            'mime_type': _mime(local, m.kind),
            'media_name': m.kind == WaMediaKind.document ? m.mediaName : null,
            'media_duration': m.mediaDurationSec ?? 0,
            'media_caption': caption,
            'suspicious_content': 0,
            'is_animated_sticker': 0,
            'has_streaming_sidecar': 0,
            'gif_attribution': 0,
          });
          files.add(WaAndroidMediaFile(localPath: local, relativePath: rel));
        }
        added++;
        any = true;
      }
      if (any) s.reorderChat(chatRow);
    }
    return WaAndroidImportResult(
      chatsCreated: created,
      chatsMerged: merged,
      messagesAdded: added,
      messagesSkipped: skipped,
      mediaFiles: files,
      mediaMissing: missing,
    );
  }

  /// iPhone captions live in the media item's title; for documents that
  /// title is the file name instead.
  static String? _caption(WaMessage m) {
    final t = m.text?.trim();
    if (t != null && t.isNotEmpty) return t;
    if (m.kind == WaMediaKind.image || m.kind == WaMediaKind.video) {
      final name = m.mediaName?.trim();
      final file = m.mediaPath?.split('/').last;
      if (name != null && name.isNotEmpty && name != file) return name;
    }
    return null;
  }

  static String? _text(WaMessage m) {
    final body = _caption(m);
    final label = switch (m.kind) {
      WaMediaKind.none => null,
      WaMediaKind.image => '📷 ${tr('Photo')}',
      WaMediaKind.video => '🎥 ${tr('Video')}',
      WaMediaKind.audio => '🎵 ${tr('Audio')}',
      WaMediaKind.voice => '🎤 ${tr('Voice message')}',
      WaMediaKind.document => '📄 ${m.mediaName ?? tr('Document')}',
      WaMediaKind.sticker => tr('Sticker'),
      WaMediaKind.gif => 'GIF',
      WaMediaKind.contact => '👤 ${tr('Contact')}',
      WaMediaKind.location => '📍 ${tr('Location')}',
    };
    if (label == null) return body;
    return body == null ? '[$label]' : '[$label] $body';
  }

  /// Android `message_type` and media folder for a kind that is moved as a
  /// real file (`Sent/` for own photos, videos and documents, as WhatsApp
  /// does).
  static _Kind? _androidMedia(WaMediaKind k, String app, bool fromMe) {
    final sent = fromMe ? '/Sent' : '';
    return switch (k) {
      WaMediaKind.image => _Kind(1, 'Media/$app Images$sent'),
      WaMediaKind.voice => _Kind(2, 'Media/$app Voice Notes'),
      WaMediaKind.audio => _Kind(2, 'Media/$app Audio$sent'),
      WaMediaKind.video => _Kind(3, 'Media/$app Video$sent'),
      WaMediaKind.document => _Kind(9, 'Media/$app Documents$sent'),
      WaMediaKind.gif => _Kind(13, 'Media/$app Animated Gifs$sent'),
      WaMediaKind.sticker => _Kind(20, 'Media/$app Stickers'),
      _ => null,
    };
  }

  static String _fileName(String jid, String keyId, String local, WaMessage m) {
    final h = crypto.sha1.convert(utf8.encode('$jid|$keyId')).bytes;
    final digits = ((h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) & 0x7fffffff)
        .toString();
    final base = local.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    final ext = dot > 0
        ? base.substring(dot).toLowerCase()
        : _defaultExt(m.kind);
    if (m.kind == WaMediaKind.document && (m.mediaName?.isNotEmpty ?? false)) {
      final safe = m.mediaName!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      return safe.contains('.') ? '$digits $safe' : '$digits $safe$ext';
    }
    return '$digits$ext';
  }

  static String _defaultExt(WaMediaKind k) => switch (k) {
    WaMediaKind.image => '.jpg',
    WaMediaKind.video || WaMediaKind.gif => '.mp4',
    WaMediaKind.voice => '.opus',
    WaMediaKind.audio => '.m4a',
    WaMediaKind.sticker => '.webp',
    _ => '',
  };

  static String _mime(String path, WaMediaKind k) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'opus' => 'audio/ogg; codecs=opus',
      'ogg' => 'audio/ogg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'mp3' => 'audio/mpeg',
      'pdf' => 'application/pdf',
      _ => switch (k) {
        WaMediaKind.image => 'image/jpeg',
        WaMediaKind.video || WaMediaKind.gif => 'video/mp4',
        WaMediaKind.voice || WaMediaKind.audio => 'audio/ogg; codecs=opus',
        _ => 'application/octet-stream',
      },
    };
  }

  static String _syntheticId(String jid, WaMessage m, int i) {
    final h = crypto.sha1.convert(
      utf8.encode('$jid|${m.timestampMs}|${m.fromMe}|$i|${m.text}'),
    );
    return '3EB0${h.toString().substring(0, 16).toUpperCase()}';
  }
}

class _Kind {
  const _Kind(this.type, this.folder);

  final int type;
  final String folder;
}

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
    if (!has('message') || !has('chat') || !has('jid')) {
      throw WaParseException(
        tr(
          'The Android backup is not a current WhatsApp database; update '
          'WhatsApp on the phone and make a new backup.',
        ),
      );
    }
  }

  final Database db;
  final _cols = <String, Set<String>>{};
  final _jids = <String, int>{};

  bool has(String table) => _cols.containsKey(table);

  Map<String, Object?> _filter(String table, Map<String, Object?> values) => {
    for (final e in values.entries)
      if (_cols[table]!.contains(e.key)) e.key: e.value,
  };

  int insert(String table, Map<String, Object?> values) {
    insertRaw(table, values);
    return db.lastInsertRowId;
  }

  void insertRaw(String table, Map<String, Object?> values) {
    final row = _filter(table, values);
    db.execute(
      'INSERT INTO "$table" (${row.keys.join(', ')}) '
      'VALUES (${List.filled(row.length, '?').join(', ')})',
      row.values.toList(),
    );
  }

  void update(String table, int id, Map<String, Object?> values) {
    final row = _filter(table, values);
    if (row.isEmpty) return;
    db.execute(
      'UPDATE "$table" SET ${row.keys.map((k) => '$k = ?').join(', ')} '
      'WHERE _id = ?',
      [...row.values, id],
    );
  }

  /// `jid._id` for [raw] (`user@server`), adding it when missing.
  int jid(String raw) => _jids.putIfAbsent(raw, () {
    final existing = db.select(
      'SELECT _id FROM jid WHERE raw_string = ? LIMIT 1',
      [raw],
    ).firstOrNull;
    if (existing != null) return existing['_id'] as int;
    final at = raw.indexOf('@');
    final user = at < 0 ? raw : raw.substring(0, at);
    final server = at < 0 ? 's.whatsapp.net' : raw.substring(at + 1);
    final byParts = db.select(
      'SELECT _id FROM jid WHERE user = ? AND server = ? '
      'AND COALESCE(device, 0) = 0 LIMIT 1',
      [user, server],
    ).firstOrNull;
    if (byParts != null) return byParts['_id'] as int;
    return insert('jid', {
      'user': user,
      'server': server,
      'agent': 0,
      'device': 0,
      'type': switch (server) {
        'g.us' => 1,
        'lid' => 18,
        _ => 0,
      },
      'raw_string': raw,
    });
  });

  int? chatFor(int jidRow) =>
      db.select('SELECT _id FROM chat WHERE jid_row_id = ? LIMIT 1', [
            jidRow,
          ]).firstOrNull?['_id']
          as int?;

  Set<String> keyIds(int chat) => {
    if (_cols['message']!.contains('key_id'))
      for (final r in db.select(
        'SELECT from_me, key_id FROM message WHERE chat_row_id = ?',
        [chat],
      ))
        '${r['from_me']}|${r['key_id']}',
  };

  /// Gives the chat's messages their existing `sort_id` values in date
  /// order, then points the chat at its newest message.
  void reorderChat(int chat) {
    if (!_cols['message']!.contains('sort_id')) return;
    final rows = db.select(
      'SELECT _id, sort_id, timestamp FROM message WHERE chat_row_id = ?',
      [chat],
    );
    final sortIds = [for (final r in rows) r['sort_id'] as int]..sort();
    final byDate = [...rows]
      ..sort((a, b) {
        final c = ((a['timestamp'] as int?) ?? 0).compareTo(
          (b['timestamp'] as int?) ?? 0,
        );
        return c != 0 ? c : (a['_id'] as int).compareTo(b['_id'] as int);
      });
    // Two passes so a temporarily duplicated sort_id never trips an index.
    for (var i = 0; i < byDate.length; i++) {
      db.execute('UPDATE message SET sort_id = ? WHERE _id = ?', [
        -1 - i,
        byDate[i]['_id'],
      ]);
    }
    for (var i = 0; i < byDate.length; i++) {
      db.execute('UPDATE message SET sort_id = ? WHERE _id = ?', [
        sortIds[i],
        byDate[i]['_id'],
      ]);
    }
    if (byDate.isEmpty) return;
    final last = byDate.last;
    final lastId = last['_id'] as int;
    final lastSort = sortIds.last;
    update('chat', chat, {
      'last_message_row_id': lastId,
      'display_message_row_id': lastId,
      'last_read_message_row_id': lastId,
      'last_read_receipt_sent_message_row_id': lastId,
      'last_message_sort_id': lastSort,
      'display_message_sort_id': lastSort,
      'last_read_message_sort_id': lastSort,
      'last_read_receipt_sent_message_sort_id': lastSort,
      'sort_timestamp': last['timestamp'],
      'hidden': 0,
    });
  }
}
