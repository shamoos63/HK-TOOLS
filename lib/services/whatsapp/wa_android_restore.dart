import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'wa_android_writer.dart';
import 'wa_backup_locator.dart';
import 'wa_crypt.dart';
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

/// iPhone → Android: chats from an iPhone backup (iTunes / Finder / 3uTools /
/// HK Tools) merged into the Android phone's own encrypted WhatsApp backup.
///
/// Like the commercial tools, the result is a normal WhatsApp local backup:
/// WhatsApp on the phone restores it during setup with the 64-digit key.
abstract final class WaAndroidRestore {
  static WaAndroidRestorePackage prepare({
    required String iphoneBackupDir,
    required String androidCrypt15Path,
    required String keyHex,
    required String outDir,
    bool business = false,
  }) {
    final archive = WaBackupLocator.read(iphoneBackupDir, business: business);
    final key = WaBackupKey.fromKeyFile(Uint8List.fromList(keyHex.codeUnits));
    final template = File(androidCrypt15Path).readAsBytesSync();
    final plain = decryptWhatsAppDb(template, key);

    final out = Directory(outDir);
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final dbPath = p.join(outDir, 'msgstore.db');
    File(dbPath).writeAsBytesSync(plain);

    final media = _IphoneMedia(iphoneBackupDir, business: business);
    final result = WaAndroidWriter.importFile(
      dbPath,
      archive,
      media: media.resolve,
      business: business,
    );

    final crypt = p.join(outDir, 'Databases', 'msgstore.db.crypt15');
    File(crypt)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
        encryptWhatsAppDb(File(dbPath).readAsBytesSync(), key, template),
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
