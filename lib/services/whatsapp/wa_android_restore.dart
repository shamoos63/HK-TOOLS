import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'wa_android_writer.dart';
import 'wa_backup_locator.dart';
import 'wa_crypt.dart';
import 'wa_msgstore_schema.dart';
import 'wa_parser.dart';

/// What [WaAndroidRestore.prepare] leaves in its output folder, ready to be
/// pushed to the phone's WhatsApp folder.
class WaAndroidRestorePackage {
  const WaAndroidRestorePackage({
    required this.crypt15Path,
    required this.mediaDir,
    required this.result,
  });

  /// `msgstore.db.crypt15` for `<WhatsApp>/Databases/`.
  final String crypt15Path;

  /// Folder whose contents go into `<WhatsApp>/Media/`, or `null` when there
  /// is no media.
  final String? mediaDir;
  final WaAndroidImportResult result;
}

/// iPhone → Android, the way Dr.Fone does it (traced from its logs):
///
///  1. Build an Android `msgstore.db`: start from the phone's own database
///     when the "From Android" steps copied it (so its chats are kept),
///     otherwise from a WhatsApp 2.26 template; add the iPhone chats.
///  2. Encrypt it as a `.crypt15` with a header made from scratch (installed
///     WhatsApp version, last two digits of the phone number) and the
///     all-zeros 64-digit key.
///  3. The caller reinstalls WhatsApp clean, pushes the backup and media,
///     and the user restores with 64 zeros as the key.
abstract final class WaAndroidRestore {
  static WaAndroidRestorePackage prepare({
    required String iphoneBackupDir,
    required String outDir,
    required String appVersion,
    required String jidSuffix,
    String? baseCrypt15Path,
    String? baseKeyHex,
    bool business = false,
  }) {
    final archive = WaBackupLocator.read(iphoneBackupDir, business: business);

    final out = Directory(outDir);
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final dbPath = p.join(outDir, 'msgstore.db');
    if (baseCrypt15Path != null && baseKeyHex != null) {
      final baseKey = WaBackupKey.fromKeyFile(
        Uint8List.fromList(baseKeyHex.codeUnits),
      );
      File(dbPath).writeAsBytesSync(
        decryptWhatsAppDb(File(baseCrypt15Path).readAsBytesSync(), baseKey),
      );
    } else {
      createTemplateMsgstore(dbPath);
    }

    final media = _IphoneMedia(iphoneBackupDir, business: business);
    final result = WaAndroidWriter.importFile(
      dbPath,
      archive,
      media: media.resolve,
      business: business,
    );

    final zero = WaBackupKey.fromKeyFile(
      Uint8List.fromList(waZeroKeyHex.codeUnits),
    );
    final crypt = p.join(outDir, 'Databases', 'msgstore.db.crypt15');
    File(crypt)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
        encryptWhatsAppDbFresh(
          File(dbPath).readAsBytesSync(),
          zero,
          appVersion: appVersion,
          jidSuffix: jidSuffix,
        ),
        flush: true,
      );
    File(dbPath).deleteSync();

    String? mediaDir;
    if (result.mediaFiles.isNotEmpty) {
      mediaDir = p.join(outDir, 'Media');
      for (final f in result.mediaFiles) {
        // relativePath is "Media/…"; stage it under outDir with the same tree.
        final to = File(p.joinAll([outDir, ...f.relativePath.split('/')]))
          ..parent.createSync(recursive: true);
        File(f.localPath).copySync(to.path);
      }
    }
    return WaAndroidRestorePackage(
      crypt15Path: crypt,
      mediaDir: mediaDir,
      result: result,
    );
  }
}

/// Creates an empty WhatsApp `msgstore.db` at [path] from the built-in
/// schema.
void createTemplateMsgstore(String path) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA journal_mode=DELETE');
    db.execute('BEGIN');
    for (final sql in waMsgstoreSchema) {
      db.execute(sql);
    }
    // FTS4 tables: created normally when this SQLite has FTS4; otherwise
    // only registered in the schema (their shadow tables already exist), the
    // same bytes WhatsApp's own database has. WhatsApp opens them with its
    // own SQLite, which has FTS4.
    for (final (name, sql) in waMsgstoreVirtualTables) {
      try {
        db.execute('SAVEPOINT vt');
        db.execute(sql);
        db.execute('RELEASE vt');
      } on SqliteException {
        db.execute('ROLLBACK TO vt');
        db.execute('RELEASE vt');
        db.execute('PRAGMA writable_schema = ON');
        db.execute(
          "INSERT INTO sqlite_master (type, name, tbl_name, rootpage, sql) "
          "VALUES ('table', ?, ?, 0, ?)",
          [name, name, sql],
        );
        db.execute('PRAGMA writable_schema = OFF');
      }
    }
    db.execute('CREATE TABLE android_metadata (locale TEXT)');
    db.execute("INSERT INTO android_metadata VALUES ('en_US')");
    db.execute('COMMIT');
    db.execute('PRAGMA user_version = 1');
  } finally {
    db.close();
  }
}

/// Finds a message's media file inside the iPhone backup: iOS WhatsApp
/// stores `Message/` + `ZMEDIALOCALPATH` in its shared container.
class _IphoneMedia {
  _IphoneMedia(this.backupDir, {required bool business}) {
    final match = WaBackupLocator.find(backupDir)
        .where((m) => m.isBusiness == business)
        .firstOrNull;
    if (match == null) return;
    final db = sqlite3.open(
      p.join(backupDir, 'Manifest.db'),
      mode: OpenMode.readOnly,
    );
    try {
      for (final r in db.select(
        "SELECT fileID, relativePath FROM Files WHERE domain = ? "
        "AND flags = 1 AND relativePath LIKE 'Message/%'",
        [match.domain],
      )) {
        _byPath[r['relativePath'] as String] = r['fileID'] as String;
      }
    } on SqliteException {
      // No media index: messages keep labels.
    } finally {
      db.close();
    }
  }

  final String backupDir;
  final _byPath = <String, String>{};

  String? resolve(WaMessage m) {
    final path = m.mediaPath;
    if (path == null || path.isEmpty) return null;
    final rel = path.startsWith('Message/') ? path : 'Message/$path';
    final id = _byPath[rel] ?? _byPath[path];
    if (id == null || id.length < 2) return null;
    final f = File(p.join(backupDir, id.substring(0, 2), id));
    return f.existsSync() ? f.path : null;
  }
}
