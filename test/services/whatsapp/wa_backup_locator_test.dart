import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_backup_locator.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Builds a minimal unencrypted iOS backup containing a WhatsApp
/// ChatStorage.sqlite, the way idevicebackup2 lays one out.
String _buildBackup(Directory root, {bool encrypted = false}) {
  final dir = Directory(p.join(root.path, 'UDID1'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'Info.plist')).writeAsStringSync(
    '<?xml version="1.0"?><plist version="1.0"><dict>'
    '<key>Device Name</key><string>Test</string></dict></plist>',
  );
  File(p.join(dir.path, 'Manifest.plist')).writeAsStringSync(
    '<?xml version="1.0"?><plist version="1.0"><dict>'
    '<key>IsEncrypted</key>${encrypted ? '<true/>' : '<false/>'}'
    '</dict></plist>',
  );

  const fileId = 'a1b2c3d4e5f600112233445566778899aabbccdd';
  final sub = Directory(p.join(dir.path, fileId.substring(0, 2)))..createSync();
  File('test/fixtures/wa_chatstorage.sqlite')
      .copySync(p.join(sub.path, fileId));

  final manifest = sqlite3.open(p.join(dir.path, 'Manifest.db'));
  manifest.execute(
    'CREATE TABLE Files(fileID TEXT PRIMARY KEY, domain TEXT, '
    'relativePath TEXT, flags INTEGER, file BLOB)',
  );
  manifest.execute(
    "INSERT INTO Files VALUES(?, 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared', "
    "'ChatStorage.sqlite', 1, NULL)",
    [fileId],
  );
  manifest.close();
  return dir.path;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('hk_wab_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('finds and reads WhatsApp from an unencrypted backup', () {
    final dir = _buildBackup(root);
    expect(WaBackupLocator.hasWhatsApp(dir), isTrue);

    final matches = WaBackupLocator.find(dir);
    expect(matches, hasLength(1));
    expect(matches.first.isBusiness, isFalse);
    expect(File(matches.first.dbFilePath).existsSync(), isTrue);

    final archive = WaBackupLocator.read(dir);
    expect(archive.chatCount, 2);
    expect(archive.messageCount, 4);
    expect(archive.chats.any((c) => c.name == 'Alice'), isTrue);
  });

  test('refuses an encrypted backup with a clear message', () {
    final dir = _buildBackup(root, encrypted: true);
    expect(
      () => WaBackupLocator.read(dir),
      throwsA(
        isA<WaParseException>().having(
          (e) => e.message,
          'm',
          contains('encrypted'),
        ),
      ),
    );
  });

  test('a backup without WhatsApp yields nothing', () {
    final dir = Directory(p.join(root.path, 'empty'))..createSync();
    File(p.join(dir.path, 'Manifest.db')).writeAsStringSync('not a db');
    expect(WaBackupLocator.hasWhatsApp(dir.path), isFalse);
    expect(
      () => WaBackupLocator.read(dir.path),
      throwsA(isA<WaParseException>()),
    );
  });
}
