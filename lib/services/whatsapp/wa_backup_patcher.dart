import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../device/contacts_service.dart';
import 'wa_backup_locator.dart';
import 'wa_bplist.dart';
import 'wa_ios_calls.dart';
import 'wa_ios_writer.dart';
import 'wa_parser.dart';
import '../../core/l10n/l10n.dart';

/// Puts Android WhatsApp chats into a local, unencrypted iPhone backup, ready
/// to be restored to the iPhone.
///
/// The backup must be fresh and come from the target iPhone with WhatsApp
/// installed and registered (same phone number as the Android phone): its
/// `ChatStorage.sqlite` is the template the chats are merged into. The
/// original database and `Manifest.db` are saved to [undoDir] first so the
/// backup can be put back as it was ([WaBackupPatcher.undo]).
abstract final class WaBackupPatcher {
  static WaIosImportResult transfer({
    required String backupDir,
    required WaArchive archive,
    required String undoDir,
    bool business = false,
    String? mediaRoot,
  }) {
    final src = BackupContacts.describe(backupDir, origin: '');
    if (src == null) {
      throw WaParseException(tr('This folder is not an iPhone backup.'));
    }
    if (src.encrypted) {
      throw WaParseException(
        tr(
          'The iPhone backup is encrypted. Turn off backup encryption (Devices → Backup), make a new backup and try again.',
        ),
      );
    }
    final matches = WaBackupLocator.find(backupDir)
        .where((m) => m.isBusiness == business)
        .toList();
    if (matches.isEmpty) {
      throw WaParseException(
        trf(
          '{0} was not found in the iPhone backup. Install it on the iPhone, register with the same number as the Android phone, send one message, then back up again.',
          [business ? 'WhatsApp Business' : 'WhatsApp'],
        ),
      );
    }
    final match = matches.first;
    final dbFile = File(match.dbFilePath);
    if (!dbFile.existsSync()) {
      throw WaParseException(
        tr('The WhatsApp database is missing from the backup.'),
      );
    }
    final manifestPath = p.join(backupDir, 'Manifest.db');

    // Save the originals once (a second transfer keeps the first originals).
    final undo = Directory(undoDir);
    if (!File(p.join(undoDir, 'Manifest.db')).existsSync()) {
      undo.createSync(recursive: true);
      File(manifestPath).copySync(p.join(undoDir, 'Manifest.db'));
      for (final f in _companions(backupDir, match)) {
        if (File(f.blob).existsSync()) {
          File(f.blob).copySync(p.join(undoDir, f.fileId));
        }
      }
    }

    final tmp = Directory.systemTemp.createTempSync('hk_wa_xfer_');
    try {
      // Rebuild the live database (main file + WAL) in a temp folder, so the
      // WAL is folded in before writing.
      final work = p.join(tmp.path, 'ChatStorage.sqlite');
      dbFile.copySync(work);
      final companions = _companions(backupDir, match);
      // Only the WAL carries data; SQLite rebuilds the -shm index itself.
      for (final c in companions.where((c) => c.suffix == '-wal')) {
        if (File(c.blob).existsSync()) {
          File(c.blob).copySync('$work${c.suffix}');
        }
      }
      final resolver = mediaRoot == null ? null : _MediaIndex(mediaRoot);
      final result = WaIosWriter.importFile(
        work,
        archive,
        media: resolver?.resolve,
      );

      // Write back: the database, and empty WAL/SHM files.
      final manifest = sqlite3.open(manifestPath);
      try {
        for (final c in companions) {
          final Uint8List bytes = c.suffix.isEmpty
              ? File(work).readAsBytesSync()
              : Uint8List(0);
          File(c.blob)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(bytes, flush: true);
          _setSize(manifest, c.fileId, bytes.length);
        }
        if (result.mediaFiles.isNotEmpty) {
          _addMedia(backupDir, manifest, match, result.mediaFiles, undoDir);
        }
        final calls = archive.calls.isEmpty
            ? 0
            : _addCalls(backupDir, manifest, match.domain, archive, tmp.path);
        return result.withCalls(calls);
      } finally {
        manifest.close();
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// Makes a small backup holding only WhatsApp's shared-container files
  /// from the full iPhone backup at [backupDir], under `<outRoot>/<udid>`, and
  /// returns its path. The full backup is left untouched.
  ///
  /// This is what the commercial transfer tools restore: a backup with just
  /// the WhatsApp domain. Restoring it changes only WhatsApp's data (items
  /// that aren't in a backup are kept unless the restore is told to remove
  /// them), takes seconds instead of a whole-phone restore, and can't
  /// disturb photos, apps or settings.
  static String buildRestoreSet({
    required String backupDir,
    required String outRoot,
    bool business = false,
  }) {
    final matches = WaBackupLocator.find(backupDir)
        .where((m) => m.isBusiness == business)
        .toList();
    if (matches.isEmpty) {
      throw WaParseException(
        trf(
          '{0} was not found in the iPhone backup. Install it on the iPhone, register with the same number as the Android phone, send one message, then try again.',
          [business ? 'WhatsApp Business' : 'WhatsApp'],
        ),
      );
    }
    final domain = matches.first.domain;
    final dest = Directory(p.join(outRoot, p.basename(backupDir)));
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    dest.createSync(recursive: true);
    for (final name in const ['Info.plist', 'Manifest.plist', 'Status.plist']) {
      final f = File(p.join(backupDir, name));
      if (f.existsSync()) f.copySync(p.join(dest.path, name));
    }
    final manifestPath = p.join(dest.path, 'Manifest.db');
    File(p.join(backupDir, 'Manifest.db')).copySync(manifestPath);
    final db = sqlite3.open(manifestPath);
    try {
      db.execute('DELETE FROM Files WHERE domain != ?', [domain]);
      db.execute('VACUUM');
      for (final row in db.select('SELECT fileID FROM Files WHERE flags = 1')) {
        final id = row['fileID'] as String;
        if (id.length < 2) continue;
        final src = File(p.join(backupDir, id.substring(0, 2), id));
        if (!src.existsSync()) continue;
        final to = File(p.join(dest.path, id.substring(0, 2), id))
          ..parent.createSync(recursive: true);
        src.copySync(to.path);
      }
    } finally {
      db.close();
    }
    return dest.path;
  }

  /// Puts back the backup's original WhatsApp database and `Manifest.db`.
  static bool undo({required String backupDir, required String undoDir}) {
    final saved = File(p.join(undoDir, 'Manifest.db'));
    if (!saved.existsSync()) return false;
    for (final f in Directory(undoDir).listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (name == 'Manifest.db' || name == _addedList) continue;
      f.copySync(p.join(backupDir, name.substring(0, 2), name));
    }
    saved.copySync(p.join(backupDir, 'Manifest.db'));
    // Media files the transfer added.
    final added = File(p.join(undoDir, _addedList));
    if (added.existsSync()) {
      for (final id in added.readAsLinesSync()) {
        if (id.length < 2) continue;
        final f = File(p.join(backupDir, id.substring(0, 2), id));
        if (f.existsSync()) f.deleteSync();
      }
    }
    Directory(undoDir).deleteSync(recursive: true);
    return true;
  }

  static const _addedList = 'added-files.txt';

  /// Adds the call history to WhatsApp's `CallHistory.sqlite` in the backup
  /// (same container, created by WhatsApp on first launch). Returns how many
  /// calls were added; 0 when the iPhone has no call-history store yet.
  static int _addCalls(
    String backupDir,
    Database manifest,
    String domain,
    WaArchive archive,
    String tmpDir,
  ) {
    String? idOf(String rel) =>
        manifest.select(
              'SELECT fileID FROM Files WHERE domain = ? AND relativePath = ?',
              [domain, rel],
            ).firstOrNull?['fileID']
            as String?;
    const rel = 'CallHistory.sqlite';
    final mainId = idOf(rel);
    if (mainId == null) return 0;
    String blob(String id) => p.join(backupDir, id.substring(0, 2), id);
    if (!File(blob(mainId)).existsSync()) return 0;

    final work = p.join(tmpDir, rel);
    File(blob(mainId)).copySync(work);
    final walId = idOf('$rel-wal');
    if (walId != null && File(blob(walId)).existsSync()) {
      File(blob(walId)).copySync('$work-wal');
    }
    final added = WaIosCallWriter.importFile(work, archive.calls);

    final bytes = File(work).readAsBytesSync();
    File(blob(mainId)).writeAsBytesSync(bytes, flush: true);
    _setSize(manifest, mainId, bytes.length);
    for (final suffix in const ['-wal', '-shm']) {
      final id = idOf('$rel$suffix');
      if (id == null || !File(blob(id)).existsSync()) continue;
      File(blob(id)).writeAsBytesSync(const [], flush: true);
      _setSize(manifest, id, 0);
    }
    return added;
  }

  /// Copies the media into the backup and lists each file (and any missing
  /// parent folder) in `Manifest.db`, using WhatsApp's own records as
  /// templates so mode, owner and protection class match.
  static void _addMedia(
    String backupDir,
    Database manifest,
    WaBackupMatch match,
    List<WaIosMediaFile> files,
    String undoDir,
  ) {
    final domain = match.domain;
    final fileTemplate =
        manifest.select('SELECT file FROM Files WHERE fileID = ?', [
              p.basename(match.dbFilePath),
            ]).firstOrNull?['file']
            as Uint8List?;
    if (fileTemplate == null) return;
    final dirTemplate =
        manifest.select(
              'SELECT file FROM Files WHERE domain = ? AND flags = 2 '
              'AND file IS NOT NULL LIMIT 1',
              [domain],
            ).firstOrNull?['file']
            as Uint8List?;
    final known = {
      for (final r in manifest.select(
        'SELECT relativePath FROM Files WHERE domain = ?',
        [domain],
      ))
        r['relativePath'] as String,
    };
    final added = File(p.join(undoDir, _addedList))
      ..parent.createSync(recursive: true);
    final addedIds = StringBuffer();

    manifest.execute('BEGIN');
    try {
      for (final f in files) {
        // Parent folders first (Message/Media/<jid>/x/y).
        if (dirTemplate != null) {
          final parts = f.relativePath.split('/');
          for (var i = 1; i < parts.length; i++) {
            final dir = parts.sublist(0, i).join('/');
            if (!known.add(dir)) continue;
            manifest.execute(
              'INSERT OR REPLACE INTO Files VALUES (?, ?, ?, 2, ?)',
              [
                BackupContacts.fileId(domain, dir),
                domain,
                dir,
                bplistFileRecord(dirTemplate, relativePath: dir, size: 0),
              ],
            );
          }
        }
        final id = BackupContacts.fileId(domain, f.relativePath);
        final blob = File(p.join(backupDir, id.substring(0, 2), id));
        if (!blob.existsSync()) addedIds.writeln(id);
        blob.parent.createSync(recursive: true);
        File(f.localPath).copySync(blob.path);
        known.add(f.relativePath);
        manifest.execute(
          'INSERT OR REPLACE INTO Files VALUES (?, ?, ?, 1, ?)',
          [
            id,
            domain,
            f.relativePath,
            bplistFileRecord(
              fileTemplate,
              relativePath: f.relativePath,
              size: f.size,
              modified: File(f.localPath).lastModifiedSync(),
            ),
          ],
        );
      }
      manifest.execute('COMMIT');
    } catch (_) {
      manifest.execute('ROLLBACK');
      rethrow;
    } finally {
      added.writeAsStringSync(addedIds.toString(), mode: FileMode.append);
    }
  }

  static void _setSize(Database manifest, String fileId, int size) {
    final row = manifest.select('SELECT file FROM Files WHERE fileID = ?', [
      fileId,
    ]).firstOrNull;
    final blob = row?['file'];
    if (blob is! Uint8List) return;
    manifest.execute('UPDATE Files SET file = ? WHERE fileID = ?', [
      bplistSetSize(blob, size),
      fileId,
    ]);
  }

  /// The database and its `-wal` / `-shm` files, as listed in the backup.
  static List<_BackupFile> _companions(String backupDir, WaBackupMatch match) {
    final mainId = p.basename(match.dbFilePath);
    final out = [
      _BackupFile(fileId: mainId, blob: match.dbFilePath, suffix: ''),
    ];
    final db = sqlite3.open(
      p.join(backupDir, 'Manifest.db'),
      mode: OpenMode.readOnly,
    );
    try {
      final main = db.select(
        'SELECT relativePath FROM Files WHERE fileID = ?',
        [mainId],
      ).firstOrNull;
      final rel = main?['relativePath'] as String?;
      if (rel == null) return out;
      for (final suffix in const ['-wal', '-shm']) {
        final r = db.select(
          'SELECT fileID FROM Files WHERE domain = ? AND relativePath = ?',
          [match.domain, '$rel$suffix'],
        ).firstOrNull;
        final id = r?['fileID'] as String?;
        if (id == null || id.length < 2) continue;
        out.add(
          _BackupFile(
            fileId: id,
            blob: p.join(backupDir, id.substring(0, 2), id),
            suffix: suffix,
          ),
        );
      }
    } finally {
      db.close();
    }
    return out;
  }
}

class _BackupFile {
  const _BackupFile({
    required this.fileId,
    required this.blob,
    required this.suffix,
  });

  final String fileId;
  final String blob;
  final String suffix;
}

/// Finds the Android media file for a message inside the copied `Media`
/// folder: by its recorded path first, then by file name.
class _MediaIndex {
  _MediaIndex(this.root);

  final String root;
  Map<String, String>? _byName;

  String? resolve(WaMessage m) {
    final path = m.mediaPath;
    if (path != null && path.isNotEmpty) {
      final norm = path.replaceAll('\\', '/');
      final i = norm.indexOf('Media/');
      if (i >= 0) {
        final candidate = p.joinAll([root, ...norm.substring(i).split('/')]);
        if (File(candidate).existsSync()) return candidate;
      }
    }
    final names = _byName ??= _index();
    final name = path?.replaceAll('\\', '/').split('/').last ?? m.mediaName;
    return name == null || name.isEmpty ? null : names[name];
  }

  Map<String, String> _index() {
    final out = <String, String>{};
    final dir = Directory(p.join(root, 'Media'));
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) out.putIfAbsent(p.basename(e.path), () => e.path);
    }
    return out;
  }
}
