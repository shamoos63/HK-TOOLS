import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_backup_locator.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_backup_patcher.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_bplist.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_reader.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_writer.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// A fresh iPhone ChatStorage.sqlite as WhatsApp leaves it after registering:
/// Core Data tables with Z_PRIMARYKEY, one existing chat.
void _createIosStore(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR,
      Z_SUPER INTEGER, Z_MAX INTEGER);
    INSERT INTO Z_PRIMARYKEY VALUES (1,'WAChatSession',0,1),
      (2,'WAMessage',0,1),(3,'WAGroupMember',0,0),(4,'WAGroupInfo',0,0),
      (5,'WAMediaItem',0,0);
    CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZARCHIVED INTEGER, ZHIDDEN INTEGER, ZREMOVED INTEGER,
      ZSESSIONTYPE INTEGER, ZMESSAGECOUNTER INTEGER, ZUNREADCOUNT INTEGER,
      ZFLAGS INTEGER, ZGROUPINFO INTEGER, ZLASTMESSAGE INTEGER,
      ZLASTMESSAGEDATE TIMESTAMP, ZCONTACTJID VARCHAR, ZPARTNERNAME VARCHAR,
      ZLASTMESSAGETEXT VARCHAR);
    CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZCHATSESSION INTEGER, ZGROUPMEMBER INTEGER,
      ZMEDIAITEM INTEGER, ZISFROMME INTEGER, ZMESSAGESTATUS INTEGER,
      ZMESSAGETYPE INTEGER, ZSORT INTEGER, ZFLAGS INTEGER,
      ZDATAITEMVERSION INTEGER, ZGROUPEVENTTYPE INTEGER,
      ZSPOTLIGHTSTATUS INTEGER, ZMESSAGEDATE TIMESTAMP, ZSENTDATE TIMESTAMP,
      ZFROMJID VARCHAR, ZTOJID VARCHAR, ZSTANZAID VARCHAR, ZTEXT VARCHAR,
      ZMEDIASECTIONID VARCHAR);
    CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZISACTIVE INTEGER, ZISADMIN INTEGER,
      ZCHATSESSION INTEGER, ZCONTACTNAME VARCHAR, ZMEMBERJID VARCHAR);
    CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZMESSAGE INTEGER, ZFILESIZE INTEGER,
      ZMOVIEDURATION INTEGER, ZMEDIALOCALPATH VARCHAR, ZTITLE VARCHAR);
    CREATE TABLE ZWAGROUPINFO (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
      Z_OPT INTEGER, ZCHATSESSION INTEGER, ZCREATIONDATE TIMESTAMP);
    INSERT INTO ZWACHATSESSION (Z_PK,Z_ENT,Z_OPT,ZSESSIONTYPE,ZCONTACTJID,
      ZPARTNERNAME,ZMESSAGECOUNTER) VALUES (1,1,1,0,'0@s.whatsapp.net','WhatsApp',1);
    INSERT INTO ZWAMESSAGE (Z_PK,Z_ENT,Z_OPT,ZCHATSESSION,ZISFROMME,ZTEXT,
      ZMESSAGEDATE,ZSTANZAID,ZSORT) VALUES (1,2,1,1,0,'Welcome',700000000,'W1',0);
  ''');
  db.close();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hk_wa_xfer_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final android = WaParser.parseFile('test/fixtures/wa_msgstore.db');

  group('WaIosWriter', () {
    test('Android chats become readable iPhone chats', () {
      final path = p.join(tmp.path, 'ChatStorage.sqlite');
      _createIosStore(path);
      final r = WaIosWriter.importFile(path, android);
      expect(r.chatsCreated, android.chats.length);
      expect(r.messagesAdded, greaterThan(0));

      final ios = WaIosReader.readFile(path);
      // Existing chat kept, Android chats added.
      expect(ios.chatCount, android.chats.length + 1);
      for (final chat in android.chats) {
        final texts = ios.messagesFor(chat.jid).map((m) => m.text).toList();
        for (final m in android.messagesFor(chat.jid)) {
          if (m.text != null && m.text!.isNotEmpty && !m.isMedia) {
            expect(texts, contains(m.text));
          }
        }
      }

      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      // Z_MAX tracks the new keys so WhatsApp's Core Data won't reuse them.
      final maxMsg =
          db
                  .select(
                    "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='WAMessage'",
                  )
                  .first['Z_MAX']
              as int;
      final realMax =
          db.select('SELECT MAX(Z_PK) m FROM ZWAMESSAGE').first['m'] as int;
      expect(maxMsg, realMax);
      // Sent messages are marked delivered; nothing is left pending.
      expect(
        db
            .select(
              'SELECT COUNT(*) c FROM ZWAMESSAGE WHERE ZISFROMME=1 '
              'AND ZMESSAGESTATUS != 5',
            )
            .first['c'],
        0,
      );
      // Every chat points at its last message.
      expect(
        db
            .select(
              'SELECT COUNT(*) c FROM ZWACHATSESSION WHERE ZLASTMESSAGE IS NULL '
              "AND ZCONTACTJID != '0@s.whatsapp.net'",
            )
            .first['c'],
        0,
      );
      db.close();
    });

    test('Android history goes before newer iPhone messages', () {
      final path = p.join(tmp.path, 'ChatStorage.sqlite');
      _createIosStore(path);
      final jid = android.chats.first.jid;
      // A message already on the iPhone in that chat, dated after everything
      // in the Android backup.
      final db = sqlite3.open(path);
      db.execute(
        "INSERT INTO ZWACHATSESSION (Z_PK,Z_ENT,Z_OPT,ZSESSIONTYPE,ZCONTACTJID) "
        "VALUES (9,1,1,0,?)",
        [jid],
      );
      db.execute(
        "INSERT INTO ZWAMESSAGE (Z_PK,Z_ENT,Z_OPT,ZCHATSESSION,ZISFROMME,ZTEXT,"
        "ZMESSAGEDATE,ZSTANZAID,ZSORT) VALUES (9,2,1,9,1,'newest',2000000000,'N1',0)",
      );
      db.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=9");
      db.close();
      WaIosWriter.importFile(path, android);
      final check = sqlite3.open(path, mode: OpenMode.readOnly);
      final rows = check.select(
        'SELECT ZTEXT FROM ZWAMESSAGE WHERE ZCHATSESSION=9 ORDER BY ZSORT',
      );
      check.close();
      expect(rows.last['ZTEXT'], 'newest');
      expect(rows.length, greaterThan(1));
    });

    test('running it twice adds nothing new', () {
      final path = p.join(tmp.path, 'ChatStorage.sqlite');
      _createIosStore(path);
      final first = WaIosWriter.importFile(path, android);
      final second = WaIosWriter.importFile(path, android);
      expect(second.messagesAdded, 0);
      expect(second.chatsCreated, 0);
      expect(second.chatsMerged, first.chatsCreated);
    });
  });

  group('bplistSetSize', () {
    test('changes only Size, and the result is a valid plist', () {
      final src = File('test/fixtures/wa_mbfile.bplist').readAsBytesSync();
      expect(bplistGetSize(src), 200);
      final out = bplistSetSize(src, 5000000000);
      expect(bplistGetSize(out), 5000000000);
      expect(bplistGetSize(bplistSetSize(out, 7)), 7);
      if (Platform.isMacOS) {
        final f = File(p.join(tmp.path, 'out.bplist'))..writeAsBytesSync(out);
        final r = Process.runSync('plutil', ['-p', f.path]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('"Size" => 5000000000'));
        expect(r.stdout, contains('"RelativePath"'));
        expect(r.stdout, contains('ChatStorage.sqlite'));
      }
    });

    test('bplistFileRecord makes a valid record for another file', () {
      final src = File('test/fixtures/wa_mbfile.bplist').readAsBytesSync();
      const path = 'Message/Media/123@s.whatsapp.net/a/b/x.jpg';
      final out = bplistFileRecord(src, relativePath: path, size: 99);
      expect(bplistGetSize(out), 99);
      expect(bplistGetRelativePath(out), path);
      if (Platform.isMacOS) {
        final f = File(p.join(tmp.path, 'rec.bplist'))..writeAsBytesSync(out);
        final r = Process.runSync('plutil', ['-p', f.path]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains(path));
        expect(r.stdout, contains('"Size" => 99'));
      }
    });
  });

  group('WaBackupPatcher', () {
    String buildBackup() {
      final dir = Directory(p.join(tmp.path, 'Backups', 'UDID1'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'Info.plist')).writeAsStringSync(
        '<?xml version="1.0"?><plist version="1.0"><dict>'
        '<key>Device Name</key><string>Test</string></dict></plist>',
      );
      File(p.join(dir.path, 'Manifest.plist')).writeAsStringSync(
        '<?xml version="1.0"?><plist version="1.0"><dict>'
        '<key>IsEncrypted</key><false/></dict></plist>',
      );
      const id = '7c7fba66680ef796b916b067077cc246adacf01d';
      const walId = 'aa00000000000000000000000000000000000001';
      final blob = p.join(dir.path, id.substring(0, 2), id);
      Directory(p.dirname(blob)).createSync();
      _createIosStore(blob);
      final wal = p.join(dir.path, 'aa', walId);
      Directory(p.dirname(wal)).createSync();
      File(wal).writeAsBytesSync(List.filled(32, 1));
      final mb = File('test/fixtures/wa_mbfile.bplist').readAsBytesSync();
      final m = sqlite3.open(p.join(dir.path, 'Manifest.db'));
      m.execute(
        'CREATE TABLE Files(fileID TEXT PRIMARY KEY, domain TEXT, '
        'relativePath TEXT, flags INTEGER, file BLOB)',
      );
      const domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared';
      m.execute('INSERT INTO Files VALUES(?,?,?,1,?)', [
        id,
        domain,
        'ChatStorage.sqlite',
        mb,
      ]);
      m.execute('INSERT INTO Files VALUES(?,?,?,1,?)', [
        walId,
        domain,
        'ChatStorage.sqlite-wal',
        mb,
      ]);
      m.execute('INSERT INTO Files VALUES(?,?,?,2,?)', [
        'bb00000000000000000000000000000000000002',
        domain,
        'Message',
        mb,
      ]);
      m.close();
      return dir.path;
    }

    Uint8List fileRecord(String dir, String id) {
      final m = sqlite3.open(p.join(dir, 'Manifest.db'));
      try {
        return m.select('SELECT file FROM Files WHERE fileID=?', [
              id,
            ]).first['file']
            as Uint8List;
      } finally {
        m.close();
      }
    }

    test('injects chats, fixes sizes, and can be undone', () {
      final dir = buildBackup();
      final undoDir = p.join(tmp.path, 'undo');
      const id = '7c7fba66680ef796b916b067077cc246adacf01d';
      final blob = File(p.join(dir, '7c', id));
      final originalBytes = blob.readAsBytesSync();

      final r = WaBackupPatcher.transfer(
        backupDir: dir,
        archive: android,
        undoDir: undoDir,
      );
      expect(r.messagesAdded, greaterThan(0));
      expect(bplistGetSize(fileRecord(dir, id)), blob.lengthSync());
      expect(
        bplistGetSize(
          fileRecord(dir, 'aa00000000000000000000000000000000000001'),
        ),
        0,
      );
      final read = WaBackupLocator.read(dir);
      expect(read.chatCount, android.chats.length + 1);

      expect(WaBackupPatcher.undo(backupDir: dir, undoDir: undoDir), isTrue);
      expect(blob.readAsBytesSync(), originalBytes);
      expect(bplistGetSize(fileRecord(dir, id)), 200);
    });

    test('moves photos into the backup as real media messages', () {
      final dir = buildBackup();
      final undoDir = p.join(tmp.path, 'undo');
      final mediaRoot = p.join(tmp.path, 'android');
      final photo = File(p.join(mediaRoot, 'Media', 'photo.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.generate(1234, (i) => i % 256));

      final r = WaBackupPatcher.transfer(
        backupDir: dir,
        archive: android,
        undoDir: undoDir,
        mediaRoot: mediaRoot,
      );
      expect(r.mediaFiles, hasLength(1));
      expect(r.mediaMissing, 0);
      final rel = r.mediaFiles.single.relativePath;
      expect(rel, startsWith('Message/Media/'));
      expect(rel, endsWith('.jpg'));

      // The iPhone database has an image message pointing at the file.
      final ios = WaBackupLocator.read(dir);
      final img = ios.messages.where((m) => m.kind == WaMediaKind.image);
      expect(img, hasLength(1));
      expect('Message/${img.single.mediaPath}', rel);
      expect(img.single.mediaSize, 1234);

      // The file is in the backup and listed in Manifest.db.
      const domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared';
      final m = sqlite3.open(p.join(dir, 'Manifest.db'));
      final row = m.select(
        'SELECT fileID, file, flags FROM Files WHERE relativePath = ?',
        [rel],
      ).single;
      final id = row['fileID'] as String;
      expect(
        File(p.join(dir, id.substring(0, 2), id)).readAsBytesSync(),
        photo.readAsBytesSync(),
      );
      expect(bplistGetSize(row['file'] as Uint8List), 1234);
      expect(bplistGetRelativePath(row['file'] as Uint8List), rel);
      // Parent folders were added too.
      final parent = rel.substring(0, rel.lastIndexOf('/'));
      expect(
        m.select(
          'SELECT flags FROM Files WHERE domain = ? AND relativePath = ?',
          [domain, parent],
        ).single['flags'],
        2,
      );
      m.close();

      // Undo removes the added file again.
      WaBackupPatcher.undo(backupDir: dir, undoDir: undoDir);
      expect(File(p.join(dir, id.substring(0, 2), id)).existsSync(), isFalse);
    });

    test(
      'restore set holds only WhatsApp and leaves the full backup alone',
      () {
        final dir = buildBackup();
        // Something from another app in the full backup.
        final m = sqlite3.open(p.join(dir, 'Manifest.db'));
        m.execute(
          "INSERT INTO Files VALUES('cc00000000000000000000000000000000000003',"
          "'HomeDomain','Library/SMS/sms.db',1,NULL)",
        );
        m.close();
        File(p.join(dir, 'cc', 'cc00000000000000000000000000000000000003'))
          ..createSync(recursive: true)
          ..writeAsStringSync('sms');
        final manifestBefore = File(p.join(dir, 'Manifest.db'))
            .readAsBytesSync();
        const id = '7c7fba66680ef796b916b067077cc246adacf01d';
        final dbBefore = File(p.join(dir, '7c', id)).readAsBytesSync();

        final set = WaBackupPatcher.buildRestoreSet(
          backupDir: dir,
          outRoot: p.join(tmp.path, 'restore'),
        );
        expect(p.basename(set), 'UDID1');
        for (final f in ['Info.plist', 'Manifest.plist', 'Manifest.db']) {
          expect(File(p.join(set, f)).existsSync(), isTrue, reason: f);
        }
        final sm = sqlite3.open(p.join(set, 'Manifest.db'));
        final domains = {
          for (final r in sm.select('SELECT DISTINCT domain FROM Files'))
            r['domain'] as String,
        };
        sm.close();
        expect(domains, {'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'});
        expect(File(p.join(set, 'cc')).existsSync(), isFalse);

        final r = WaBackupPatcher.transfer(
          backupDir: set,
          archive: android,
          undoDir: p.join(tmp.path, 'undo'),
        );
        expect(r.messagesAdded, greaterThan(0));
        expect(WaBackupLocator.read(set).chatCount, android.chats.length + 1);
        // The full backup is exactly as it was.
        expect(
          File(p.join(dir, 'Manifest.db')).readAsBytesSync(),
          manifestBefore,
        );
        expect(File(p.join(dir, '7c', id)).readAsBytesSync(), dbBefore);
      },
    );

    test('call history goes into the backup too', () {
      final dir = buildBackup();
      const callId = '1b432994e9000000000000000000000000000000';
      final blob = File(p.join(dir, '1b', callId))..createSync(recursive: true);
      final cdb = sqlite3.open(blob.path);
      cdb.execute('''
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR,
          Z_SUPER INTEGER, Z_MAX INTEGER);
        INSERT INTO Z_PRIMARYKEY VALUES (1,'WACDCallEvent',0,0),
          (2,'WACDCallEventParticipant',0,0);
        CREATE TABLE ZWACDCALLEVENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
          Z_OPT INTEGER, ZOUTCOME INTEGER, ZDATE TIMESTAMP, ZDURATION FLOAT,
          ZCALLIDSTRING VARCHAR);
        CREATE TABLE ZWACDCALLEVENTPARTICIPANT (Z_PK INTEGER PRIMARY KEY,
          Z_ENT INTEGER, Z_OPT INTEGER, ZOUTCOME INTEGER,
          Z1PARTICIPANTS INTEGER, ZJIDSTRING VARCHAR);
      ''');
      cdb.close();
      final m = sqlite3.open(p.join(dir, 'Manifest.db'));
      m.execute('INSERT INTO Files VALUES(?,?,?,1,?)', [
        callId,
        'AppDomainGroup-group.net.whatsapp.WhatsApp.shared',
        'CallHistory.sqlite',
        File('test/fixtures/wa_mbfile.bplist').readAsBytesSync(),
      ]);
      m.close();
      final withCalls = WaArchive(
        chats: android.chats,
        messages: android.messages,
        calls: const [
          WaCall(
            jid: '15551234567@s.whatsapp.net',
            fromMe: true,
            timestampMs: 1700000000000,
            durationSec: 30,
            video: false,
            outcome: WaCallOutcome.completed,
            callId: 'X1',
          ),
        ],
      );
      final r = WaBackupPatcher.transfer(
        backupDir: dir,
        archive: withCalls,
        undoDir: p.join(tmp.path, 'undo'),
      );
      expect(r.callsAdded, 1);
      final m2 = sqlite3.open(p.join(dir, 'Manifest.db'));
      final rec =
          m2.select('SELECT file FROM Files WHERE fileID=?', [
                callId,
              ]).first['file']
              as Uint8List;
      m2.close();
      expect(bplistGetSize(rec), blob.lengthSync());
      final check = sqlite3.open(blob.path, mode: OpenMode.readOnly);
      expect(
        check
            .select('SELECT ZCALLIDSTRING FROM ZWACDCALLEVENT')
            .single['ZCALLIDSTRING'],
        'X1',
      );
      check.close();
    });

    test('a photo missing on the phone stays a labelled message', () {
      final dir = buildBackup();
      final r = WaBackupPatcher.transfer(
        backupDir: dir,
        archive: android,
        undoDir: p.join(tmp.path, 'undo'),
        mediaRoot: p.join(tmp.path, 'nothing-here'),
      );
      expect(r.mediaFiles, isEmpty);
      expect(r.mediaMissing, 1);
      final ios = WaBackupLocator.read(dir);
      expect(ios.messages.map((m) => m.text), contains('[📷 Photo]'));
    });
  });
}
