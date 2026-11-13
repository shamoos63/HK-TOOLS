import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Finds the files behind WhatsApp media messages, so photos, videos and
/// stickers can be shown inside the chat preview.
///
/// - **iPhone backups** store every file under its SHA-1 file id. The
///   backup's `Manifest.db` maps WhatsApp's `Message/Media/…` paths (the
///   `ZMEDIALOCALPATH` of each message, prefixed with `Message/`) to those
///   ids. Videos have a `.thumb` JPEG next to them.
/// - **Android** media copied off the phone is a plain folder; message paths
///   are relative to it.
class WaMediaIndex {
  WaMediaIndex._(this._files, this._root);

  /// Relative media path (`Media/<jid>/a/b/<uuid>.jpg`) → file on disk.
  final Map<String, String> _files;

  /// Folder that relative paths resolve against (Android).
  final String? _root;

  bool get isEmpty => _files.isEmpty && _root == null;

  /// Index of the media in the iPhone backup at [backupDir]; empty when the
  /// backup has none (or is encrypted).
  static WaMediaIndex fromBackup(String backupDir) {
    final manifest = File(p.join(backupDir, 'Manifest.db'));
    final files = <String, String>{};
    if (!manifest.existsSync()) return WaMediaIndex._(files, null);
    try {
      final db = sqlite3.open(manifest.path, mode: OpenMode.readOnly);
      try {
        for (final row in db.select(
          "SELECT fileID, relativePath FROM Files "
          "WHERE flags = 1 AND LOWER(domain) LIKE '%whatsapp%' "
          "AND relativePath LIKE 'Message/Media/%'",
        )) {
          final id = row['fileID'] as String;
          final rel = (row['relativePath'] as String).substring(8);
          files[rel] = p.join(backupDir, id.substring(0, 2), id);
        }
      } finally {
        db.close();
      }
    } on SqliteException {
      // Encrypted manifest: no media.
    }
    return WaMediaIndex._(files, null);
  }

  /// Media copied from an Android phone into [root].
  static WaMediaIndex fromFolder(String root) => WaMediaIndex._(const {}, root);

  static String _norm(String path) {
    var s = path.replaceAll('\\', '/');
    if (s.startsWith('Message/')) s = s.substring(8);
    if (s.startsWith('/')) s = s.substring(1);
    return s;
  }

  /// The full file for a message's media path, when it is in the backup.
  String? file(String? mediaPath) {
    if (mediaPath == null || mediaPath.isEmpty) return null;
    final key = _norm(mediaPath);
    final hit = _files[key];
    if (hit != null) return hit;
    final root = _root;
    if (root != null) {
      for (final candidate in [
        p.join(root, key),
        p.join(root, 'Media', key),
        p.join(root, p.basename(key)),
      ]) {
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  /// A small preview image: the photo itself, or the `.thumb` of a video.
  String? thumbnail(String? mediaPath) {
    if (mediaPath == null) return null;
    final key = _norm(mediaPath);
    final ext = p.extension(key).toLowerCase();
    if (const [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.gif',
    ].contains(ext)) {
      return file(mediaPath);
    }
    return _files['${p.withoutExtension(key)}.thumb'] ?? file(mediaPath);
  }

  /// Copies the media file to [dir] with its real extension (backup files
  /// have none), so the system can open it.
  String? export(String? mediaPath, String dir) {
    final src = file(mediaPath);
    if (src == null) return null;
    final name = p.basename(_norm(mediaPath!));
    final out = File(p.join(dir, name));
    if (!out.existsSync()) {
      out.parent.createSync(recursive: true);
      File(src).copySync(out.path);
    }
    return out.path;
  }
}
