import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_export.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:sqlite3/sqlite3.dart';

WaArchive _legacy() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE messages(_id INTEGER PRIMARY KEY, key_remote_jid TEXT,
      key_from_me INTEGER, timestamp INTEGER, data TEXT,
      media_mime_type TEXT, media_name TEXT, media_size INTEGER, remote_resource TEXT);
    CREATE TABLE chat_list(key_remote_jid TEXT, subject TEXT);
    INSERT INTO chat_list VALUES('120363@g.us','Legacy Group');
    INSERT INTO messages VALUES(1,'15551112222@s.whatsapp.net',0,1600000000000,'hi legacy',NULL,NULL,NULL,NULL);
    INSERT INTO messages VALUES(2,'120363@g.us',0,1600000100000,NULL,'image/jpeg','a.jpg',99,'15553334444@s.whatsapp.net');
  ''');
  final a = WaParser.parse(db);
  db.close();
  return a;
}

void main() {
  test('parses the modern message/chat/jid schema', () {
    final a = WaParser.parseFile('test/fixtures/wa_msgstore.db');
    expect(a.chatCount, 2);
    expect(a.messageCount, 4);
    expect(a.mediaCount, 1);

    final group = a.chats.firstWhere((c) => c.isGroup);
    expect(group.name, 'Family Group');
    expect(group.jid, '120363000@g.us');
    expect(group.messageCount, 2);

    final dm = a.chats.firstWhere((c) => !c.isGroup);
    expect(dm.jid, '15551234567@s.whatsapp.net');
    // No contact name in msgstore → shows the number.
    expect(dm.name, '+15551234567');

    final dmMsgs = a.messagesFor(dm.jid);
    expect(dmMsgs.map((m) => m.text), ['Hello from Android', 'Reply from me']);
    expect(dmMsgs[0].fromMe, isFalse);
    expect(dmMsgs[1].fromMe, isTrue);

    // Group media message: sender resolved, kind from message_type.
    final media = a.messages.firstWhere((m) => m.isMedia);
    expect(media.kind, WaMediaKind.image);
    expect(media.mediaMime, 'image/jpeg');
    expect(media.sender, '15551234567@s.whatsapp.net');

    // A different group member sent the text-only group message.
    final groupText = a.messagesFor(group.jid).firstWhere((m) => !m.isMedia);
    expect(groupText.sender, '15559990000@s.whatsapp.net');
  });

  test('falls back to the legacy messages/chat_list schema', () {
    final a = _legacy();
    expect(a.chatCount, 2);
    expect(a.messageCount, 2);
    expect(a.chats.any((c) => c.name == 'Legacy Group'), isTrue);
    expect(a.messages.first.text, isNotNull);
    expect(a.mediaCount, 1);
  });

  test('HTML export embeds every chat and message, safely escaped', () {
    final a = WaParser.parseFile('test/fixtures/wa_msgstore.db');
    final html = WaExport.toHtml(a, title: 'My <chats>');
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('My &lt;chats&gt;')); // title escaped
    expect(html, contains('Family Group'));
    expect(html, contains('Hello from Android'));
    expect(html, contains('Photo')); // media placeholder text
    // Chat data is present for client-side rendering.
    expect('{f:0,t:1700000000000'.allMatches(html).length, greaterThan(0));
  });

  test('CSV export has a header and one row per message', () {
    final a = WaParser.parseFile('test/fixtures/wa_msgstore.db');
    final csv = WaExport.toCsv(a);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('"Chat","JID","Date","Direction"'));
    expect('\r\n'.allMatches(csv).length, a.messageCount + 1);
    expect(csv, contains('"Reply from me"'));
    expect(csv, contains('"Received"'));
  });

  test('rejects a non-WhatsApp database', () {
    final db = sqlite3.openInMemory();
    db.execute('CREATE TABLE foo(x)');
    expect(() => WaParser.parse(db), throwsA(isA<WaParseException>()));
    db.close();
  });

  test('privacy ids (@lid) become phone numbers via jid_map', () {
    final db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE jid(_id INTEGER PRIMARY KEY, user TEXT, server TEXT,
        raw_string TEXT);
      CREATE TABLE chat(_id INTEGER PRIMARY KEY, jid_row_id INTEGER,
        subject TEXT);
      CREATE TABLE message(_id INTEGER PRIMARY KEY, chat_row_id INTEGER,
        from_me INTEGER, sender_jid_row_id INTEGER, text_data TEXT,
        timestamp INTEGER, message_type INTEGER, key_id TEXT);
      CREATE TABLE jid_map(lid_row_id INTEGER PRIMARY KEY,
        jid_row_id INTEGER, sort_id INTEGER);
      INSERT INTO jid VALUES (1,'15550001111','s.whatsapp.net','15550001111@s.whatsapp.net');
      INSERT INTO jid VALUES (2,'98765','lid','98765@lid');
      INSERT INTO jid VALUES (3,'120363','g.us','120363@g.us');
      INSERT INTO jid_map VALUES (2,1,0);
      INSERT INTO chat VALUES (10,1,NULL),(11,2,NULL),(12,3,'Team');
      INSERT INTO message VALUES (1,10,0,NULL,'by number',1000,0,'A');
      INSERT INTO message VALUES (2,11,0,NULL,'by lid',2000,0,'B');
      INSERT INTO message VALUES (3,12,0,2,'group lid sender',3000,0,'C');
    ''');
    final a = WaParser.parse(db);
    db.close();
    // The LID chat merged into the phone-number chat.
    expect(a.chats.where((c) => !c.isGroup), hasLength(1));
    expect(a.messagesFor('15550001111@s.whatsapp.net').map((m) => m.text), [
      'by number',
      'by lid',
    ]);
    final g = a.messagesFor('120363@g.us').single;
    expect(g.sender, '15550001111@s.whatsapp.net');
    expect(g.keyId, 'C');
  });
}
