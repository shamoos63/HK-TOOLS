import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_backup_locator.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_calls.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

WaArchive _androidWithCalls() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE jid(_id INTEGER PRIMARY KEY, user TEXT, server TEXT,
      raw_string TEXT);
    CREATE TABLE chat(_id INTEGER PRIMARY KEY, jid_row_id INTEGER,
      subject TEXT);
    CREATE TABLE message(_id INTEGER PRIMARY KEY, chat_row_id INTEGER,
      from_me INTEGER, text_data TEXT, timestamp INTEGER);
    CREATE TABLE jid_map(lid_row_id INTEGER PRIMARY KEY, jid_row_id INTEGER,
      sort_id INTEGER);
    CREATE TABLE call_log(_id INTEGER PRIMARY KEY, jid_row_id INTEGER,
      from_me INTEGER, call_id TEXT, timestamp INTEGER, video_call INTEGER,
      duration INTEGER, call_result INTEGER, bytes_transferred INTEGER,
      group_jid_row_id INTEGER);
    INSERT INTO jid VALUES (1,'15550001111','s.whatsapp.net','15550001111@s.whatsapp.net');
    INSERT INTO jid VALUES (2,'777','lid','777@lid');
    INSERT INTO jid_map VALUES (2,1,0);
    INSERT INTO call_log VALUES (1,1,1,'CALL1',1700000000000,0,65,5,100,NULL);
    INSERT INTO call_log VALUES (2,2,0,'CALL2',1700000100000,1,0,2,0,NULL);
  ''');
  final a = WaParser.parse(db);
  db.close();
  return a;
}

/// iPhone CallHistory.sqlite as WhatsApp creates it.
void _createCallStore(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR,
      Z_SUPER INTEGER, Z_MAX INTEGER);
    INSERT INTO Z_PRIMARYKEY VALUES (1,'WAAggregateCallEvent',0,0),
      (2,'WACDCallEvent',0,0),(3,'WACDCallEventParticipant',0,0);
    CREATE TABLE ZWAAGGREGATECALLEVENT (Z_PK INTEGER PRIMARY KEY,
      Z_ENT INTEGER, Z_OPT INTEGER, ZINCOMING INTEGER, ZMISSED INTEGER,
      ZMISSEDREASON INTEGER, ZVIDEO INTEGER);
    CREATE TABLE ZWACDCALLEVENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZOUTCOME INTEGER, Z1CALLEVENTS INTEGER,
      ZDATE TIMESTAMP, ZDURATION FLOAT, ZBYTESRECEIVED INTEGER,
      ZBYTESSENT INTEGER, ZCALLIDSTRING VARCHAR, ZGROUPJIDSTRING VARCHAR,
      ZGROUPCALLCREATORUSERJIDSTRING VARCHAR);
    CREATE TABLE ZWACDCALLEVENTPARTICIPANT (Z_PK INTEGER PRIMARY KEY,
      Z_ENT INTEGER, Z_OPT INTEGER, ZOUTCOME INTEGER, Z1PARTICIPANTS INTEGER,
      ZJIDSTRING VARCHAR);
  ''');
  db.close();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hk_wa_calls_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads Android call history, with privacy ids mapped', () {
    final calls = _androidWithCalls().calls;
    expect(calls, hasLength(2));
    expect(calls[0].fromMe, isTrue);
    expect(calls[0].outcome, WaCallOutcome.completed);
    expect(calls[0].durationSec, 65);
    expect(calls[1].jid, '15550001111@s.whatsapp.net');
    expect(calls[1].video, isTrue);
    expect(calls[1].outcome, WaCallOutcome.missed);
  });

  test('writes calls into the iPhone call history, once', () {
    final path = p.join(tmp.path, 'CallHistory.sqlite');
    _createCallStore(path);
    final calls = _androidWithCalls().calls;
    expect(WaIosCallWriter.importFile(path, calls), 2);
    expect(WaIosCallWriter.importFile(path, calls), 0);

    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    // The query the public iOS parsers use.
    final rows = db.select(
      'SELECT e.ZCALLIDSTRING id, e.ZDATE, e.ZOUTCOME, e.ZDURATION, '
      'a.ZINCOMING, a.ZMISSED, a.ZVIDEO, p.ZJIDSTRING '
      'FROM ZWACDCALLEVENT e '
      'JOIN ZWAAGGREGATECALLEVENT a ON e.Z1CALLEVENTS = a.Z_PK '
      'JOIN ZWACDCALLEVENTPARTICIPANT p ON p.Z1PARTICIPANTS = e.Z_PK '
      'ORDER BY e.ZDATE',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['id'], 'CALL1');
    expect(rows[0]['ZOUTCOME'], 0);
    expect(rows[0]['ZINCOMING'], 0);
    expect(rows[0]['ZDURATION'], 65);
    expect(rows[0]['ZDATE'], 1700000000 - 978307200);
    expect(rows[1]['ZINCOMING'], 1);
    expect(rows[1]['ZMISSED'], 1);
    expect(rows[1]['ZVIDEO'], 1);
    expect(rows[1]['ZJIDSTRING'], '15550001111@s.whatsapp.net');
    final maxEv =
        db
                .select(
                  "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='WACDCallEvent'",
                )
                .first['Z_MAX']
            as int;
    expect(maxEv, 2);
    db.close();
  });

  test('WhatsApp Business is recognised in an iPhone backup', () {
    final dir = Directory(p.join(tmp.path, 'UDID'))..createSync();
    final m = sqlite3.open(p.join(dir.path, 'Manifest.db'));
    m.execute(
      'CREATE TABLE Files(fileID TEXT PRIMARY KEY, domain TEXT, '
      'relativePath TEXT, flags INTEGER, file BLOB)',
    );
    m.execute(
      "INSERT INTO Files VALUES('724bd3b98b18518b455a87c1f3ac3a0d189c4466',"
      "'AppDomainGroup-group.net.whatsapp.WhatsAppSMB.shared',"
      "'ChatStorage.sqlite',1,NULL)",
    );
    m.execute(
      "INSERT INTO Files VALUES('7c7fba66680ef796b916b067077cc246adacf01d',"
      "'AppDomainGroup-group.net.whatsapp.WhatsApp.shared',"
      "'ChatStorage.sqlite',1,NULL)",
    );
    m.close();
    final found = WaBackupLocator.find(dir.path);
    expect(found.where((f) => f.isBusiness).single.domain, contains('SMB'));
    expect(
      found.where((f) => !f.isBusiness).single.domain,
      isNot(contains('SMB')),
    );
  });
}
