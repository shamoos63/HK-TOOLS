import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_export.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_reader.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('reads iOS ChatStorage.sqlite into the shared archive model', () {
    final a = WaIosReader.readFile('test/fixtures/wa_chatstorage.sqlite');
    expect(a.chatCount, 2);
    expect(a.messageCount, 4);
    expect(a.mediaCount, 1);

    final dm = a.chats.firstWhere((c) => !c.isGroup);
    expect(dm.name, 'Alice'); // ZPARTNERNAME, not just the number
    expect(dm.jid, '15551234567@s.whatsapp.net');

    final dmMsgs = a.messagesFor(dm.jid);
    expect(dmMsgs.map((m) => m.text), ['Hello from Alice', 'Reply from me']);
    expect(dmMsgs[0].fromMe, isFalse);
    expect(dmMsgs[1].fromMe, isTrue);
    // Apple epoch → Unix: 1700000000 s.
    expect(dmMsgs[0].timestampMs, 1700000000 * 1000);

    final group = a.chats.firstWhere((c) => c.isGroup);
    expect(group.name, 'Family Group');
    final media = a.messagesFor(group.jid).firstWhere((m) => m.isMedia);
    expect(media.kind, WaMediaKind.image);
    expect(media.mediaName, 'photo.jpg');
    expect(media.mediaSize, 45678);
    // Group sender resolved via ZGROUPMEMBER → ZMEMBERJID.
    expect(media.sender, '15559990000@s.whatsapp.net');
  });

  test('iOS chats export through the same HTML/CSV path', () {
    final a = WaIosReader.readFile('test/fixtures/wa_chatstorage.sqlite');
    expect(WaExport.toHtml(a), contains('Family Group'));
    final csv = WaExport.toCsv(a);
    expect(csv, contains('"Hello from Alice"'));
    expect('\r\n'.allMatches(csv).length, a.messageCount + 1);
  });

  test('rejects a non-ChatStorage database', () {
    final db = sqlite3.openInMemory();
    db.execute('CREATE TABLE ZABC(x)');
    expect(() => WaIosReader.read(db), throwsA(isA<WaParseException>()));
    db.close();
  });
}
