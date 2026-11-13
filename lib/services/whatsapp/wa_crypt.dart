import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import '../../core/l10n/l10n.dart';

/// Decrypts a WhatsApp `.crypt15` (and legacy `.crypt14`) message database with
/// its `key` file, into a plain `msgstore.db`.
///
/// Format and key derivation follow the documented WhatsApp backup layout (the
/// reference implementation is ElDavoo/wa-crypt-tools):
///
///   file = varint(len(prefix)) ++ prefix ++ ciphertext ++ tag[16] ++ md5[16]
///
/// The prefix is a protobuf `BackupPrefix`; the 16-byte GCM IV lives in field 3
/// (`e2ee_key_data`, a `C15IV`) → field 1 (`encryption_iv`) for crypt15, or
/// field 2 (`wa_provided_key_data`, a `C14Cipher`) → field 5 for crypt14. The
/// header is variable length, so the IV is parsed out of the protobuf rather
/// than read from a fixed offset (the fixed-offset shortcut is why many simple
/// decryptors fail on real crypt15 files).
class WaCryptException implements Exception {
  WaCryptException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum WaCryptVersion { crypt14, crypt15 }

class WaBackupKey {
  WaBackupKey._(this.version, this.aesKey);

  final WaCryptVersion version;

  /// The 32-byte AES-256 key actually used to decrypt the database (already
  /// derived for crypt15).
  final Uint8List aesKey;

  /// Builds the decryption key from a `key` file's bytes, or from a 64-char
  /// hex / 32-byte raw key the user pasted.
  factory WaBackupKey.fromKeyFile(Uint8List bytes) {
    final inner = _javaByteArray(bytes) ?? _rawOrHex(bytes);
    if (inner == null) {
      throw WaCryptException(
        tr(
          'Unrecognised key file. Expected the WhatsApp "key" file, a 32-byte key, or a 64-character hex key.',
        ),
      );
    }
    if (inner.length == 32) {
      // crypt15 root key → derive the backup-encryption key.
      return WaBackupKey._(WaCryptVersion.crypt15, _deriveCrypt15(inner));
    }
    if (inner.length == 131) {
      // crypt14: cipher key is the last 32 bytes, used directly.
      return WaBackupKey._(
        WaCryptVersion.crypt14,
        Uint8List.sublistView(inner, 99, 131),
      );
    }
    throw WaCryptException(
      trf(
        'Unexpected key length ({0} bytes); expected 32 (crypt15) or 131 (crypt14).',
        [inner.length],
      ),
    );
  }

  /// crypt15: `HMAC(HMAC(0^32, root), "backup encryption" ++ 0x01)`.
  static Uint8List _deriveCrypt15(Uint8List root) {
    final privateKey = _hmac(Uint8List(32), root);
    return _hmac(
      privateKey,
      Uint8List.fromList([...'backup encryption'.codeUnits, 0x01]),
    );
  }
}

/// Decrypts [encrypted] (a whole `.crypt15`/`.crypt14` file) with [key],
/// returning the plain SQLite bytes. Throws [WaCryptException] when the key is
/// wrong or the file is corrupt.
Uint8List decryptWhatsAppDb(Uint8List encrypted, WaBackupKey key) {
  if (encrypted.length < 4) {
    throw WaCryptException(tr('File is too small to be a WhatsApp backup.'));
  }
  final (prefixLen, headerStart) = _readVarint(encrypted, 0);
  final prefixEnd = headerStart + prefixLen;
  if (prefixLen <= 0 || prefixEnd > encrypted.length) {
    throw WaCryptException(tr('Backup header is invalid or truncated.'));
  }
  final prefix = Uint8List.sublistView(encrypted, headerStart, prefixEnd);
  final iv = _ivFromPrefix(prefix);
  if (iv == null) {
    throw WaCryptException(
      tr('No IV in the backup header; unsupported format.'),
    );
  }

  final body = Uint8List.sublistView(encrypted, prefixEnd);
  if (body.length < 32) {
    throw WaCryptException(tr('Backup body is too small.'));
  }
  // body = ciphertext ++ tag[16] ++ md5[16], the md5 covering everything
  // before it. Multi-file backups have no md5: then the last 16 bytes are the
  // tag (wa-crypt-tools tells them apart the same way).
  final md5Ok =
      _md5(Uint8List.sublistView(encrypted, 0, encrypted.length - 16))
          .toString() ==
      _hexOf(Uint8List.sublistView(encrypted, encrypted.length - 16));
  final cipherAndTag = md5Ok
      ? Uint8List.sublistView(body, 0, body.length - 16)
      : body;
  Uint8List plain;
  try {
    plain = _aesGcmDecrypt(key.aesKey, iv, cipherAndTag);
  } on WaCryptException {
    if (md5Ok) rethrow;
    // A checksum written some other way: try with it stripped.
    plain = _aesGcmDecrypt(
      key.aesKey,
      iv,
      Uint8List.sublistView(body, 0, body.length - 16),
    );
  }
  // WhatsApp zlib-compresses the database before encrypting it.
  if (plain.isNotEmpty && plain[0] == 0x78) {
    try {
      plain = Uint8List.fromList(zlib.decode(plain));
    } on FormatException {
      // Not compressed after all; checked below.
    }
  }

  if (plain.length < 16 ||
      String.fromCharCodes(plain.sublist(0, 15)) != 'SQLite format 3') {
    throw WaCryptException(
      tr(
        'Decryption produced invalid data. The key does not match this backup.',
      ),
    );
  }
  return plain;
}

/// Encrypts a plain `msgstore.db` ([plainDb]) into a `.crypt15` that
/// WhatsApp on Android restores with the same 64-digit key.
///
/// [template] is a `.crypt15` made by WhatsApp on the target phone: its
/// header (app version, backup version, phone-number suffix) is kept as is,
/// with a fresh IV. Layout as in wa-crypt-tools: varint(header size) ++ header
/// ++ AES-GCM(zlib(db)) ++ tag[16] ++ md5(everything before)[16].
Uint8List encryptWhatsAppDb(
  Uint8List plainDb,
  WaBackupKey key,
  Uint8List template, {
  Uint8List? iv,
}) {
  if (key.version != WaCryptVersion.crypt15) {
    throw WaCryptException(tr('Only crypt15 backups can be written.'));
  }
  final (prefixLen, headerStart) = _readVarint(template, 0);
  final prefixEnd = headerStart + prefixLen;
  if (prefixLen <= 0 || prefixEnd > template.length) {
    throw WaCryptException(tr('Backup header is invalid or truncated.'));
  }
  final header = Uint8List.fromList(template.sublist(0, prefixEnd));
  final oldIv = _ivFromPrefix(
    Uint8List.sublistView(header, headerStart, prefixEnd),
  );
  if (oldIv == null) {
    throw WaCryptException(
      tr('No IV in the backup header; unsupported format.'),
    );
  }
  final newIv = iv ?? _randomBytes(16);
  final at = _indexOf(header, oldIv, headerStart);
  if (at < 0 || newIv.length != 16) {
    throw WaCryptException(tr('Backup header is invalid or truncated.'));
  }
  header.setRange(at, at + 16, newIv);

  final compressed = Uint8List.fromList(ZLibCodec(level: 6).encode(plainDb));
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key.aesKey), 128, newIv, Uint8List(0)),
    );
  final cipherAndTag = gcm.process(compressed);
  final out = BytesBuilder(copy: false)
    ..add(header)
    ..add(cipherAndTag);
  final body = out.toBytes();
  return Uint8List.fromList([...body, ..._md5(body).bytes]);
}

/// The 64-digit key of all zeros. The commercial transfer tools encrypt the
/// backup they build with it, and tell the user to type 64 zeros when
/// WhatsApp asks for the key during restore.
const waZeroKeyHex =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// A crypt15 header (`BackupPrefix`) built from scratch, as wa-crypt-tools
/// does without a reference backup:
///  1 key_type_deprecated = 1, 3 e2ee_key_data = { 1 iv },
///  4 backup_metadata = { 1 app_version, 3 jid_suffix (last two digits of
///  the phone number), 4 backup_version = 1, feature flags 5–37 and 39 },
///  6 key_type_new = 3 (64-digit key).
Uint8List buildCrypt15Header({
  required String appVersion,
  required String jidSuffix,
  required Uint8List iv,
}) {
  List<int> varint(int v) {
    final out = <int>[];
    while (v >= 0x80) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  List<int> tag(int field, int wire) => varint((field << 3) | wire);
  List<int> bytesField(int field, List<int> data) => [
    ...tag(field, 2),
    ...varint(data.length),
    ...data,
  ];
  List<int> intField(int field, int v) => [...tag(field, 0), ...varint(v)];

  final meta = <int>[
    ...bytesField(1, utf8.encode(appVersion)),
    ...bytesField(3, utf8.encode(jidSuffix)),
    ...intField(4, 1),
    for (var f = 5; f <= 37; f++) ...intField(f, 1),
    ...intField(39, 1),
  ];
  final prefix = <int>[
    ...intField(1, 1),
    ...bytesField(3, bytesField(1, iv)),
    ...bytesField(4, meta),
    ...intField(6, 3),
  ];
  return Uint8List.fromList([...varint(prefix.length), ...prefix]);
}

/// Encrypts [plainDb] into a new `.crypt15` with a header from
/// [buildCrypt15Header] (no template backup needed).
Uint8List encryptWhatsAppDbFresh(
  Uint8List plainDb,
  WaBackupKey key, {
  required String appVersion,
  required String jidSuffix,
  Uint8List? iv,
}) {
  final useIv = iv ?? _randomBytes(16);
  final header = buildCrypt15Header(
    appVersion: appVersion,
    jidSuffix: jidSuffix,
    iv: useIv,
  );
  // An encrypted file needs a body; reuse the template path with this
  // header (it keeps the header and the IV we just put in it).
  return encryptWhatsAppDb(
    plainDb,
    key,
    Uint8List.fromList([...header, ...List.filled(32, 0)]),
    iv: useIv,
  );
}

crypto.Digest _md5(List<int> data) => crypto.md5.convert(data);

String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

int _indexOf(Uint8List hay, Uint8List needle, int from) {
  outer:
  for (var i = from; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

// ───────────────────────── internals ─────────────────────────

Uint8List _hmac(Uint8List keyBytes, Uint8List msg) =>
    Uint8List.fromList(crypto.Hmac(crypto.sha256, keyBytes).convert(msg).bytes);

/// AES-256-GCM decrypt. [cipherAndTag] is ciphertext with the 16-byte tag
/// appended; PointyCastle verifies the tag in `doFinal`.
Uint8List _aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List cipherAndTag) {
  final gcm = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  try {
    return gcm.process(cipherAndTag);
  } on InvalidCipherTextException {
    throw WaCryptException(
      tr(
        'Decryption failed (authentication tag mismatch). Wrong key, or the backup is corrupt.',
      ),
    );
  }
}

/// (value, nextOffset) for a protobuf base-128 varint at [start].
(int, int) _readVarint(Uint8List data, int start) {
  var result = 0;
  var shift = 0;
  var i = start;
  while (i < data.length) {
    final b = data[i];
    result |= (b & 0x7f) << shift;
    i++;
    if (b & 0x80 == 0) return (result, i);
    shift += 7;
    if (shift > 63) break;
  }
  throw WaCryptException('Malformed length in backup header.');
}

/// Extracts the 16-byte IV from a `BackupPrefix`: field 3 (C15IV) → field 1,
/// or field 2 (C14Cipher) → field 5.
Uint8List? _ivFromPrefix(Uint8List prefix) {
  for (final (field, value) in _protoFields(prefix)) {
    if (field == 3) {
      // C15IV.encryption_iv = field 1.
      for (final (f, v) in _protoFields(value)) {
        if (f == 1 && v.length == 16) return v;
      }
    } else if (field == 2) {
      // C14Cipher.encryption_iv = field 5.
      for (final (f, v) in _protoFields(value)) {
        if (f == 5 && v.length == 16) return v;
      }
    }
  }
  return null;
}

/// Yields (fieldNumber, bytes) for every length-delimited (wire type 2) field;
/// other wire types are skipped. Enough to walk the backup header.
Iterable<(int, Uint8List)> _protoFields(Uint8List data) sync* {
  var pos = 0;
  while (pos < data.length) {
    final (tag, afterTag) = _readVarint(data, pos);
    final field = tag >> 3;
    final wire = tag & 0x7;
    pos = afterTag;
    switch (wire) {
      case 0: // varint
        pos = _readVarint(data, pos).$2;
      case 1: // 64-bit
        pos += 8;
      case 2: // length-delimited
        final (len, afterLen) = _readVarint(data, pos);
        if (afterLen + len > data.length) return;
        yield (field, Uint8List.sublistView(data, afterLen, afterLen + len));
        pos = afterLen + len;
      case 5: // 32-bit
        pos += 4;
      default:
        return;
    }
  }
}

/// The payload of a Java-serialized `byte[]` (`AC ED 00 05 75 72 00 02 [B …`),
/// or `null` if [bytes] is not such a stream.
Uint8List? _javaByteArray(Uint8List bytes) {
  // STREAM_MAGIC 0xACED, version 0x0005.
  if (bytes.length < 10 ||
      bytes[0] != 0xAC ||
      bytes[1] != 0xED ||
      bytes[2] != 0x00 ||
      bytes[3] != 0x05) {
    return null;
  }
  // Locate the class name "[B", then the 4-byte array length precedes the data.
  // The structure is fixed: TC_ARRAY(0x75) TC_CLASSDESC(0x72) nameLen=0x0002
  // "[B" uid[8] flags[1] fieldCount=0x0000 TC_ENDBLOCKDATA(0x78) TC_NULL(0x70)
  // length[4] data[length].
  var i = 4;
  if (i + 1 >= bytes.length || bytes[i] != 0x75 || bytes[i + 1] != 0x72) {
    return null;
  }
  i += 2;
  if (i + 1 >= bytes.length || bytes[i] != 0x00 || bytes[i + 1] != 0x02) {
    return null;
  }
  i += 2;
  if (i + 1 >= bytes.length || bytes[i] != 0x5B || bytes[i + 1] != 0x42) {
    return null; // "[B"
  }
  i += 2 + 8 + 1; // "[B" + serialVersionUID(8) + flags(1)
  i += 2; // fieldCount (expected 0)
  if (i + 1 >= bytes.length || bytes[i] != 0x78 || bytes[i + 1] != 0x70) {
    return null; // TC_ENDBLOCKDATA, TC_NULL
  }
  i += 2;
  if (i + 4 > bytes.length) return null;
  final len =
      (bytes[i] << 24) |
      (bytes[i + 1] << 16) |
      (bytes[i + 2] << 8) |
      bytes[i + 3];
  i += 4;
  if (len <= 0 || i + len > bytes.length) return null;
  return Uint8List.sublistView(bytes, i, i + len);
}

/// A raw 32-byte key, or a 64-char hex key, as the user may paste instead of a
/// key file.
Uint8List? _rawOrHex(Uint8List bytes) {
  if (bytes.length == 32) return bytes;
  final text = String.fromCharCodes(bytes.where((b) => b > 32)).toLowerCase();
  if (text.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(text)) {
    return Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ]);
  }
  return null;
}
