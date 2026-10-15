import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/device/contacts_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _udid = '00008101-000A1C3E0C38001E';

/// Builds `<root>/<udid>` like idevicebackup2: Info/Manifest plists plus the
/// address book stored under its SHA-1 file id.
Future<String> fakeBackup(Directory root, {bool encrypted = false}) async {
  final dir = Directory(p.join(root.path, _udid))..createSync(recursive: true);
  File(p.join(dir.path, 'Info.plist'))
      .writeAsStringSync('''<?xml version="1.0"?>
<plist version="1.0"><dict>
<key>Device Name</key><string>Test iPhone</string>
<key>Last Backup Date</key><date>2026-10-10T12:00:00Z</date>
</dict></plist>''');
  File(p.join(dir.path, 'Manifest.plist')).writeAsStringSync(
    '''<?xml version="1.0"?>
<plist version="1.0"><dict><key>IsEncrypted</key>${encrypted ? '<true/>' : '<false/>'}</dict></plist>''',
  );

  String place(String rel) {
    final id = BackupContacts.fileId('HomeDomain', rel);
    final d = Directory(p.join(dir.path, id.substring(0, 2)))
      ..createSync(recursive: true);
    return p.join(d.path, id);
  }

  final db = sqlite3.open(place('Library/AddressBook/AddressBook.sqlitedb'));
  db.execute('''
    CREATE TABLE ABPerson (ROWID INTEGER PRIMARY KEY, First TEXT, Last TEXT,
      Organization TEXT, JobTitle TEXT, Note TEXT, Birthday TEXT, Nickname TEXT);
    CREATE TABLE ABMultiValue (UID INTEGER PRIMARY KEY, record_id INTEGER,
      property INTEGER, identifier INTEGER, label INTEGER, value TEXT);
    CREATE TABLE ABMultiValueLabel (value TEXT, UNIQUE(value));
    CREATE TABLE ABMultiValueEntry (parent_id INTEGER, key INTEGER, value TEXT);
    CREATE TABLE ABMultiValueEntryKey (value TEXT, UNIQUE(value));
    INSERT INTO ABMultiValueLabel VALUES ('_\$!<Mobile>!\$_'), ('_\$!<Home>!\$_');
    INSERT INTO ABMultiValueEntryKey VALUES ('Street'), ('City'), ('Country');
    INSERT INTO ABPerson VALUES (1, 'Hisham', 'Khateeb', 'HK', 'Founder',
      'Line 1
Line 2', '0', NULL);
    INSERT INTO ABPerson VALUES (2, 'Sam', 'Lee', NULL, NULL, NULL, NULL, NULL);
    INSERT INTO ABPerson VALUES (3, NULL, NULL, 'Acme, Inc.', NULL, NULL, NULL, NULL);
    INSERT INTO ABMultiValue VALUES (10, 1, 3, 0, 1, '+962 79 123 4567');
    INSERT INTO ABMultiValue VALUES (11, 1, 4, 0, 2, 'h@example.com');
    INSERT INTO ABMultiValue VALUES (12, 1, 5, 0, 2, NULL);
    INSERT INTO ABMultiValue VALUES (13, 2, 3, 0, 1, '0791234567');
    INSERT INTO ABMultiValueEntry VALUES (12, 1, '1 Main St'), (12, 2, 'Amman'), (12, 3, 'Jordan');
  ''');
  db.close();

  final img = sqlite3.open(
    place('Library/AddressBook/AddressBookImages.sqlitedb'),
  );
  img.execute(
    'CREATE TABLE ABThumbnailImage (record_id INTEGER, format INTEGER, data BLOB)',
  );
  img.execute('INSERT INTO ABThumbnailImage VALUES (?, 0, ?)', [
    1,
    Uint8List.fromList([0xFF, 0xD8, 0xFF]),
  ]);
  img.close();
  return dir.path;
}

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('hk_bk_'));
  tearDown(() => root.delete(recursive: true));

  test(
    'reads people, labels, addresses, photos; leaves backup untouched',
    () async {
      final dir = await fakeBackup(root);
      final before = Directory(dir).listSync(recursive: true).length;
      final contacts = await BackupContacts.load(dir);
      expect(Directory(dir).listSync(recursive: true).length, before);

      expect(contacts.map((c) => c.displayName), [
        'Acme, Inc.',
        'Hisham Khateeb',
        'Sam Lee',
      ]);
      final h = contacts[1];
      expect(h.phones.single.label, 'Mobile');
      expect(h.emails.single.value, 'h@example.com');
      expect(h.addresses.single.oneLine, '1 Main St, Amman, Jordan');
      expect(h.birthday, DateTime.utc(2001));
      expect(h.photo, [0xFF, 0xD8, 0xFF]);
      expect(h.initials, 'HK');
    },
  );

  test('sources, encrypted backups and duplicates', () async {
    final dir = await fakeBackup(root, encrypted: true);
    final sources = BackupContacts.sourcesFor(_udid, appBackupRoot: root.path);
    expect(sources.first.directory, dir);
    expect(sources.first.encrypted, isTrue);
    expect(sources.first.deviceName, 'Test iPhone');
    expect(
      () => BackupContacts.loadSync(dir),
      throwsA(
        isA<ContactsException>().having(
          (e) => e.message,
          'msg',
          contains('encrypted'),
        ),
      ),
    );
  });

  test('duplicates, vCard and CSV export', () async {
    final contacts = BackupContacts.loadSync(await fakeBackup(root));
    final dups = findDuplicates(contacts);
    // +962 79 123 4567 and 0791234567 share the last 9 digits.
    expect(dups.single.map((c) => c.first).toSet(), {'Hisham', 'Sam'});

    final vcf = toVCard(contacts);
    expect('BEGIN:VCARD'.allMatches(vcf).length, 3);
    expect(vcf, contains('TEL;TYPE=MOBILE:+962 79 123 4567'));
    expect(vcf, contains(r'NOTE:Line 1\nLine 2'));
    expect(vcf, contains(r'FN:Acme\, Inc.'));
    expect(vcf, contains('PHOTO;ENCODING=b;TYPE=JPEG:/9j/'));
    expect(vcf, contains('\r\n'));

    final csv = toCsv(contacts);
    expect(csv.startsWith('﻿'), isTrue);
    expect(
      csv,
      contains('"Hisham","Khateeb","HK","Founder","Mobile: +962 79 123 4567"'),
    );
  });
}
