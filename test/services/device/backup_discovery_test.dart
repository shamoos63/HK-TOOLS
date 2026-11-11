import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/device/contacts_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('finds iTunes, named and nested (3uTools-style) backups', () {
    final root = Directory.systemTemp.createTempSync('hk_backups_');
    addTearDown(() => root.deleteSync(recursive: true));
    void make(String rel, String udid) {
      final d = Directory(p.join(root.path, rel))..createSync(recursive: true);
      File(p.join(d.path, 'Info.plist')).writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'
        '<key>Device Name</key><string>Test iPhone</string>'
        '<key>Unique Identifier</key><string>$udid</string></dict></plist>',
      );
      File(p.join(d.path, 'Manifest.db')).writeAsStringSync('');
    }

    make('00008101-AAA', '00008101-AAA'); // iTunes layout
    make('Test iPhone 2026-11-11 16.30/00008101-BBB', '00008101-BBB');
    make('2026/11/00008101-CCC', '00008101-CCC'); // nested
    Directory(p.join(root.path, 'empty')).createSync();

    final found = BackupContacts.findBackups(root.path, origin: 'x');
    expect(found.map((s) => s.udid).toSet(), {
      '00008101-AAA',
      '00008101-BBB',
      '00008101-CCC',
    });
    expect(found.first.deviceName, 'Test iPhone');
  });
}
