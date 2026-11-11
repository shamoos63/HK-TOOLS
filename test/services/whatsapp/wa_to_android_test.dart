import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_android_restore.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_android_writer.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_crypt.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_reader.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// The core tables of a current Android msgstore.db (schema as WhatsApp 2.26
/// creates it), with one chat already on the phone.
void _createAndroidStore(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE jid(_id INTEGER PRIMARY KEY AUTOINCREMENT,user TEXT NOT NULL,
      server TEXT NOT NULL,agent INTEGER,device INTEGER,type INTEGER,
      raw_string TEXT);
    CREATE TABLE chat(_id INTEGER PRIMARY KEY AUTOINCREMENT,
      jid_row_id INTEGER UNIQUE,hidden INTEGER,subject TEXT,
      created_timestamp INTEGER,display_message_row_id INTEGER,
      last_message_row_id INTEGER,last_read_message_row_id INTEGER,
      archived INTEGER,sort_timestamp INTEGER,
      unseen_important_message_count INTEGER NOT NULL DEFAULT 0,
      group_type INTEGER NOT NULL DEFAULT 0,last_message_sort_id INTEGER,
      display_message_sort_id INTEGER);
    CREATE TABLE message(_id INTEGER PRIMARY KEY AUTOINCREMENT,
      chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,
      key_id TEXT NOT NULL,sender_jid_row_id INTEGER,status INTEGER,
      broadcast INTEGER,recipient_count INTEGER,origination_flags INTEGER,
      origin INTEGER,timestamp INTEGER,received_timestamp INTEGER,
      receipt_server_timestamp INTEGER,message_type INTEGER,text_data TEXT,
      starred INTEGER,lookup_tables INTEGER,
      sort_id INTEGER NOT NULL DEFAULT 0);
    CREATE UNIQUE INDEX message_key ON message(chat_row_id, from_me, key_id);
    CREATE TABLE message_media(message_row_id INTEGER PRIMARY KEY,
      chat_row_id INTEGER,transferred INTEGER,file_path TEXT,
      file_size INTEGER,mime_type TEXT,media_name TEXT,
      media_duration INTEGER,media_caption TEXT,file_length INTEGER);
    INSERT INTO jid VALUES (1,'15551234567','s.whatsapp.net',0,0,0,
      '15551234567@s.whatsapp.net');
    INSERT INTO chat (_id,jid_row_id,hidden,sort_timestamp) VALUES (1,1,0,0);
    INSERT INTO message (_id,chat_row_id,from_me,key_id,timestamp,
      message_type,text_data,sort_id)
      VALUES (1,1,0,'ANDROID1',1800000000000,0,'newest, on Android',1);
  ''');
  db.close();
}

/// A minimal crypt15 header ({3: {1: iv}}) + body, as WhatsApp writes it.
Uint8List _template(Uint8List db, WaBackupKey key) {
  final stub = Uint8List.fromList([
    5,
    0x1A,
    18,
    0x0A,
    16,
    ...List.filled(16, 7),
  ]);
  // Build a valid file by encrypting through our own writer from a stub
  // header (with the IV field in place).
  final header = Uint8List.fromList([stub.length - 1 + 16, ...stub.sublist(1)]);
  return encryptWhatsAppDb(
    db,
    key,
    Uint8List.fromList([...header, ...List.filled(48, 0)]),
  );
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hk_wa_to_android_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final iphone = WaIosReader.readFile('test/fixtures/wa_chatstorage.sqlite');

  test('iPhone chats go into the Android database, in date order', () {
    final path = p.join(tmp.path, 'msgstore.db');
    _createAndroidStore(path);
    final r = WaAndroidWriter.importFile(path, iphone);
    expect(r.chatsMerged, 1); // Alice's chat already on the phone
    expect(r.chatsCreated, 1); // the group
    expect(r.messagesAdded, greaterThan(0));

    final back = WaParser.parseFile(path);
    final alice = back.messagesFor('15551234567@s.whatsapp.net');
    expect(alice.map((m) => m.text), [
      'Hello from Alice',
      'Reply from me',
      'newest, on Android',
    ]);
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    // sort_id follows the dates, newest last.
    final order = db.select(
      'SELECT text_data FROM message WHERE chat_row_id=1 ORDER BY sort_id',
    );
    expect(order.last['text_data'], 'newest, on Android');
    final chat = db.select('SELECT last_message_row_id FROM chat WHERE _id=1');
    expect(chat.first['last_message_row_id'], 1);
    db.close();

    // Again: nothing doubles.
    expect(WaAndroidWriter.importFile(path, iphone).messagesAdded, 0);
  });

  test('full package: decrypt, merge, re-encrypt, stage media', () {
    // iPhone backup with the WhatsApp database and one photo.
    final backup = Directory(p.join(tmp.path, 'UDID'))..createSync();
    File(p.join(backup.path, 'Info.plist')).writeAsStringSync(
      '<?xml version="1.0"?><plist version="1.0"><dict></dict></plist>',
    );
    File(p.join(backup.path, 'Manifest.plist')).writeAsStringSync(
      '<?xml version="1.0"?><plist version="1.0"><dict>'
      '<key>IsEncrypted</key><false/></dict></plist>',
    );
    const domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared';
    const dbId = '7c7fba66680ef796b916b067077cc246adacf01d';
    const photoId = 'ab00000000000000000000000000000000000001';
    File('test/fixtures/wa_chatstorage.sqlite').copySync(
      (File(p.join(backup.path, '7c', dbId))..parent.createSync()).path,
    );
    final photo = File(p.join(backup.path, 'ab', photoId))
      ..parent.createSync()
      ..writeAsBytesSync(List.filled(321, 9));
    final m = sqlite3.open(p.join(backup.path, 'Manifest.db'));
    m.execute(
      'CREATE TABLE Files(fileID TEXT PRIMARY KEY, domain TEXT, '
      'relativePath TEXT, flags INTEGER, file BLOB)',
    );
    m.execute('INSERT INTO Files VALUES(?,?,?,1,NULL)', [
      dbId,
      domain,
      'ChatStorage.sqlite',
    ]);
    m.execute('INSERT INTO Files VALUES(?,?,?,1,NULL)', [
      photoId,
      domain,
      'Message/Media/photo.jpg',
    ]);
    m.close();

    // The Android phone's own encrypted backup.
    const keyHex =
        '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
    final key = WaBackupKey.fromKeyFile(Uint8List.fromList(keyHex.codeUnits));
    final androidDb = p.join(tmp.path, 'android.db');
    _createAndroidStore(androidDb);
    final crypt = File(p.join(tmp.path, 'msgstore.db.crypt15'))
      ..writeAsBytesSync(_template(File(androidDb).readAsBytesSync(), key));

    final pkg = WaAndroidRestore.prepare(
      iphoneBackupDir: backup.path,
      androidCrypt15Path: crypt.path,
      keyHex: keyHex,
      outDir: p.join(tmp.path, 'out'),
    );
    expect(pkg.result.mediaFiles, hasLength(1));
    expect(pkg.result.mediaMissing, 0);
    final rel = pkg.result.mediaFiles.single.relativePath;
    expect(rel, startsWith('Media/WhatsApp Images/'));
    final staged = File(p.joinAll([tmp.path, 'out', ...rel.split('/')]));
    expect(staged.readAsBytesSync(), photo.readAsBytesSync());

    // The new backup opens with the same key and holds both phones' chats.
    final plain = decryptWhatsAppDb(
      File(pkg.crypt15Path).readAsBytesSync(),
      key,
    );
    final check = File(p.join(tmp.path, 'check.db'))..writeAsBytesSync(plain);
    final merged = WaParser.parseFile(check.path);
    final texts = merged.messages.map((m) => m.text).toList();
    expect(texts, contains('Hello from Alice'));
    expect(texts, contains('newest, on Android'));
    final img = merged.messages.singleWhere((m) => m.kind == WaMediaKind.image);
    expect(img.mediaPath, rel);
  });
}
