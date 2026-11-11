import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../device/contacts_service.dart';
import 'wa_ios_reader.dart';
import 'wa_parser.dart';
import '../../core/l10n/l10n.dart';

/// A WhatsApp `ChatStorage.sqlite` found inside an iOS backup.
class WaBackupMatch {
  const WaBackupMatch({
    required this.dbFilePath,
    required this.domain,
    required this.isBusiness,
  });

  /// On-disk path of the backed-up database file (`<backup>/ab/abcdef…`).
  final String dbFilePath;
  final String domain;
  final bool isBusiness;
}

/// Finds WhatsApp chat databases in a local iOS backup and reads them, reusing
/// the device-backup machinery (and encryption check) from the Contacts
/// feature.
abstract final class WaBackupLocator {
  /// WhatsApp `ChatStorage.sqlite` files in the backup at [backupDir]
  /// (`<root>/<udid>`), WhatsApp before WhatsApp Business.
  static List<WaBackupMatch> find(String backupDir) {
    final manifest = File(p.join(backupDir, 'Manifest.db'));
    if (!manifest.existsSync()) return const [];
    final db = sqlite3.open(manifest.path, mode: OpenMode.readOnly);
    try {
      final matches = <WaBackupMatch>[];
      for (final row in db.select(
        "SELECT fileID, domain, relativePath FROM Files "
        "WHERE relativePath LIKE '%ChatStorage.sqlite' "
        "AND LOWER(domain) LIKE '%whatsapp%'",
      )) {
        final fileId = row['fileID'] as String?;
        final domain = (row['domain'] as String?) ?? '';
        if (fileId == null || fileId.length < 2) continue;
        matches.add(
          WaBackupMatch(
            dbFilePath: p.join(backupDir, fileId.substring(0, 2), fileId),
            domain: domain,
            // WhatsApp Business's container is
            // `group.net.whatsapp.WhatsAppSMB.shared`.
            isBusiness:
                domain.toLowerCase().contains('whatsappsmb') ||
                domain.toLowerCase().contains('4b') ||
                domain.toLowerCase().contains('business'),
          ),
        );
      }
      // Main WhatsApp first.
      matches.sort((a, b) => (a.isBusiness ? 1 : 0) - (b.isBusiness ? 1 : 0));
      return matches;
    } on SqliteException {
      return const [];
    } finally {
      db.close();
    }
  }

  /// Reads the first WhatsApp database in [backupDir]. Copies it to a temp file
  /// first so the backup is never touched and SQLite's `-wal`/`-shm` land
  /// outside it. Throws [WaParseException] when the backup is encrypted or has
  /// no WhatsApp data.
  static WaArchive read(String backupDir, {bool business = false}) {
    final src = BackupContacts.describe(backupDir, origin: '');
    if (src?.encrypted ?? false) {
      throw WaParseException(
        tr(
          'This backup is encrypted, so WhatsApp can\'t be read from it. Turn off backup encryption (Devices → Backup), make a new backup, then retry.',
        ),
      );
    }
    final matches = find(backupDir);
    if (matches.isEmpty) {
      throw WaParseException(
        tr(
          'No WhatsApp chat database in this backup. Make sure WhatsApp is installed and was included in the backup.',
        ),
      );
    }
    final match = matches.firstWhere(
      (m) => m.isBusiness == business,
      orElse: () => matches.first,
    );
    if (!File(match.dbFilePath).existsSync()) {
      throw WaParseException(
        tr('The WhatsApp database is missing from the backup.'),
      );
    }
    final tmp = Directory.systemTemp.createTempSync('hk_wa_');
    try {
      final copy = p.join(tmp.path, 'ChatStorage.sqlite');
      File(match.dbFilePath).copySync(copy);
      return WaIosReader.readFile(copy);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// `true` if [backupDir] contains any WhatsApp database.
  static bool hasWhatsApp(String backupDir) => find(backupDir).isNotEmpty;
}
