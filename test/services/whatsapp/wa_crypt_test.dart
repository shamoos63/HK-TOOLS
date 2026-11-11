import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_crypt.dart';
import 'package:pointycastle/export.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// Serializes [data] the way Java serializes a `byte[]`, so the key-file parser
/// is tested against the real wrapper shape.
Uint8List _javaByteArray(Uint8List data) {
  final b = BytesBuilder();
  b.add([0xAC, 0xED, 0x00, 0x05, 0x75, 0x72, 0x00, 0x02, 0x5B, 0x42]); // "[B"
  b.add(List.filled(8, 0xAA)); // serialVersionUID (ignored)
  b.add([
    0x02,
    0x00,
    0x00,
    0x78,
    0x70,
  ]); // flags, 0 fields, end-block, null super
  b.add([
    (data.length >> 24) & 0xff,
    (data.length >> 16) & 0xff,
    (data.length >> 8) & 0xff,
    data.length & 0xff,
  ]);
  b.add(data);
  return b.toBytes();
}

/// Builds a `.crypt15` from plain [db] exactly as WhatsApp does, so the full
/// decrypt path (header varint, IV-in-protobuf, GCM, md5 trailer) is exercised.
Uint8List _encryptCrypt15(Uint8List db, Uint8List aesKey, Uint8List iv) {
  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
  final cipherAndTag = gcm.process(db); // ciphertext ++ tag[16]

  // BackupPrefix { e2ee_key_data(3) = C15IV { encryption_iv(1) = iv } }
  final c15iv = <int>[0x0A, iv.length, ...iv]; // field 1, len-delimited
  final prefix = <int>[0x1A, c15iv.length, ...c15iv]; // field 3, len-delimited

  final body = BytesBuilder()
    ..add([prefix.length]) // varint (prefix < 128 bytes here)
    ..add(prefix)
    ..add(cipherAndTag);
  // md5 of everything before it (wa-crypt-tools / WhatsApp layout).
  final md5 = crypto.md5.convert(body.toBytes()).bytes;
  body.add(md5);
  return body.toBytes();
}

void main() {
  test('crypt15 key derivation matches the reference vector', () {
    // root = 00..1f → derived key computed with wa-crypt-tools' algorithm.
    final root = Uint8List.fromList(List.generate(32, (i) => i));
    final key = WaBackupKey.fromKeyFile(root);
    expect(key.version, WaCryptVersion.crypt15);
    expect(
      key.aesKey,
      _hex('4e54c0777a7214dfdf0af5b6e153acfa2fbdac603fea6fd1630b824e5c29eef5'),
    );
  });

  test(
    'a corrupt backup is rejected by the GCM tag, not silently accepted',
    () {
      final db = File('test/fixtures/wa_msgstore.db').readAsBytesSync();
      final key = WaBackupKey.fromKeyFile(
        Uint8List.fromList(List.generate(32, (i) => i)),
      );
      final encrypted = _encryptCrypt15(db, key.aesKey, Uint8List(16));
      // Flip one ciphertext byte (just after the header, before the trailer).
      encrypted[12] ^= 0xFF;
      expect(
        () => decryptWhatsAppDb(encrypted, key),
        throwsA(isA<WaCryptException>()),
      );
    },
  );

  test('key file: raw, hex, and Java-serialized forms all load', () {
    final root = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final fromRaw = WaBackupKey.fromKeyFile(root);
    final fromJava = WaBackupKey.fromKeyFile(_javaByteArray(root));
    final hex = root.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final fromHex = WaBackupKey.fromKeyFile(Uint8List.fromList(hex.codeUnits));
    expect(fromRaw.aesKey, fromJava.aesKey);
    expect(fromRaw.aesKey, fromHex.aesKey);

    // 131-byte crypt14 key: AES key is the last 32 bytes, used directly.
    final k14 = Uint8List(131);
    for (var i = 99; i < 131; i++) {
      k14[i] = i;
    }
    final c14 = WaBackupKey.fromKeyFile(_javaByteArray(k14));
    expect(c14.version, WaCryptVersion.crypt14);
    expect(c14.aesKey, Uint8List.sublistView(k14, 99, 131));
  });

  test('full round-trip decrypts a real msgstore.db', () {
    final db = File('test/fixtures/wa_msgstore.db').readAsBytesSync();
    final root = Uint8List.fromList(List.generate(32, (i) => (i * 7) & 0xff));
    final key = WaBackupKey.fromKeyFile(root);
    final iv = Uint8List.fromList(List.generate(16, (i) => (i * 3 + 1) & 0xff));

    final encrypted = _encryptCrypt15(db, key.aesKey, iv);
    final decrypted = decryptWhatsAppDb(encrypted, key);
    expect(decrypted, db);
    expect(String.fromCharCodes(decrypted.sublist(0, 15)), 'SQLite format 3');
  });

  test('wrong key fails with a clear message, not a crash', () {
    final db = File('test/fixtures/wa_msgstore.db').readAsBytesSync();
    final right = WaBackupKey.fromKeyFile(
      Uint8List.fromList(List.generate(32, (i) => i)),
    );
    final iv = Uint8List(16);
    final encrypted = _encryptCrypt15(db, right.aesKey, iv);
    final wrong = WaBackupKey.fromKeyFile(
      Uint8List.fromList(List.generate(32, (i) => i + 9)),
    );
    expect(
      () => decryptWhatsAppDb(encrypted, wrong),
      throwsA(isA<WaCryptException>()),
    );
  });

  test('encrypt → decrypt round-trips, compressed, keeping the header', () {
    final db = File('test/fixtures/wa_msgstore.db').readAsBytesSync();
    final key = WaBackupKey.fromKeyFile(
      Uint8List.fromList(List.generate(32, (i) => (i * 5) & 0xff)),
    );
    final template = _encryptCrypt15(db, key.aesKey, Uint8List(16));
    final out = encryptWhatsAppDb(db, key, template);
    // Same header length; only the IV differs.
    expect(out.sublist(0, 3), template.sublist(0, 3));
    expect(out.sublist(5, 21), isNot(template.sublist(5, 21)));
    // md5 trailer covers everything before it.
    expect(
      out.sublist(out.length - 16),
      crypto.md5.convert(out.sublist(0, out.length - 16)).bytes,
    );
    expect(decryptWhatsAppDb(out, key), db);
    // The payload is zlib: smaller than the plain database plus overhead.
    expect(out.length, lessThan(db.length + 64));
  });

  test('decrypts a zlib-compressed backup made by WhatsApp', () {
    final db = File('test/fixtures/wa_msgstore.db').readAsBytesSync();
    final key = WaBackupKey.fromKeyFile(
      Uint8List.fromList(List.generate(32, (i) => i)),
    );
    final packed = Uint8List.fromList(ZLibCodec(level: 1).encode(db));
    final enc = _encryptCrypt15(packed, key.aesKey, Uint8List(16));
    expect(decryptWhatsAppDb(enc, key), db);
  });
}
