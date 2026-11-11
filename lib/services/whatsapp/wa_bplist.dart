import 'dart:convert';
import 'dart:typed_data';

/// Rewrites the `Size` integer inside a binary property list, keeping every
/// other object byte for byte.
///
/// An iOS backup's `Manifest.db` stores each file's metadata as an
/// NSKeyedArchiver `bplist00` (an `MBFile` dict with `Size`, `LastModified`,
/// …). After replacing a file in the backup its recorded size must match, or
/// the restore fails. Object references in a bplist are indices, not byte
/// offsets, so one object can be re-encoded and the offset table rebuilt
/// without touching anything else.
Uint8List bplistSetSize(Uint8List bytes, int newSize) {
  final doc = _Bplist(bytes);
  final ref = doc.findDictValueRef('Size');
  if (ref == null) {
    throw const FormatException('No "Size" entry in the file record.');
  }
  final marker = bytes[doc.offsets[ref]];
  if (marker >> 4 != 0x1) {
    throw const FormatException('"Size" is not an integer.');
  }
  final encoded = ByteData(9)
    ..setUint8(0, 0x13)
    ..setInt64(1, newSize);
  return doc.rebuild({ref: encoded.buffer.asUint8List()});
}

/// A new `Manifest.db` file record made from [template] (an existing record
/// of the same kind: a file for files, a folder for folders) with a different
/// path, size and timestamps. Everything else (mode, owner, protection class)
/// is kept from the template.
Uint8List bplistFileRecord(
  Uint8List template, {
  required String relativePath,
  required int size,
  DateTime? modified,
}) {
  final doc = _Bplist(template);
  final keys = doc.recordKeys();
  final sizeRef = keys['Size'];
  final pathRef = keys['RelativePath'];
  if (sizeRef == null || pathRef == null) {
    throw const FormatException('Unexpected file record layout.');
  }
  Uint8List int64(int v) {
    final b = ByteData(9)
      ..setUint8(0, 0x13)
      ..setInt64(1, v);
    return b.buffer.asUint8List();
  }

  final replacements = <int, Uint8List>{
    sizeRef: int64(size),
    doc.resolveUid(pathRef): _encodeString(relativePath),
  };
  final secs = (modified ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  for (final k in const ['LastModified', 'LastStatusChange', 'Birth']) {
    final r = keys[k];
    if (r != null && template[doc.offsets[r]] >> 4 == 0x1) {
      replacements[r] = int64(secs);
    }
  }
  return doc.rebuild(replacements);
}

/// The string stored under `RelativePath` (for tests).
String? bplistGetRelativePath(Uint8List bytes) {
  final doc = _Bplist(bytes);
  final r = doc.recordKeys()['RelativePath'];
  return r == null ? null : doc.stringAt(doc.offsets[doc.resolveUid(r)]);
}

Uint8List _encodeString(String s) {
  final ascii = s.codeUnits.every((c) => c < 0x80);
  final units = s.codeUnits;
  final out = BytesBuilder();
  final type = ascii ? 0x50 : 0x60;
  final n = units.length;
  if (n < 15) {
    out.addByte(type | n);
  } else {
    out.addByte(type | 0x0F);
    if (n < 0x100) {
      out
        ..addByte(0x10)
        ..addByte(n);
    } else if (n < 0x10000) {
      out
        ..addByte(0x11)
        ..addByte(n >> 8)
        ..addByte(n & 0xFF);
    } else {
      out
        ..addByte(0x12)
        ..add([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF]);
    }
  }
  if (ascii) {
    out.add(units);
  } else {
    for (final u in units) {
      out
        ..addByte(u >> 8)
        ..addByte(u & 0xFF);
    }
  }
  return out.toBytes();
}

/// Reads `Size` back (for tests and verification).
int? bplistGetSize(Uint8List bytes) {
  final doc = _Bplist(bytes);
  final ref = doc.findDictValueRef('Size');
  if (ref == null) return null;
  return doc.intAt(doc.offsets[ref]);
}

class _Bplist {
  _Bplist(this.bytes) {
    if (bytes.length < 40 ||
        ascii.decode(bytes.sublist(0, 6), allowInvalid: true) != 'bplist') {
      throw const FormatException('Not a binary plist.');
    }
    final t = bytes.length - 32;
    offsetSize = bytes[t + 6];
    refSize = bytes[t + 7];
    count = _uint(t + 8, 8);
    top = _uint(t + 16, 8);
    offsetTable = _uint(t + 24, 8);
    offsets = [
      for (var i = 0; i < count; i++)
        _uint(offsetTable + i * offsetSize, offsetSize),
    ];
  }

  final Uint8List bytes;
  late final int offsetSize;
  late final int refSize;
  late final int count;
  late final int top;
  late final int offsetTable;
  late final List<int> offsets;

  int _uint(int at, int size) {
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = (v << 8) | bytes[at + i];
    }
    return v;
  }

  /// (length, first byte after the length) for a marker at [at].
  (int, int) _length(int at) {
    final low = bytes[at] & 0x0F;
    if (low != 0x0F) return (low, at + 1);
    final size = 1 << (bytes[at + 1] & 0x0F);
    return (_uint(at + 2, size), at + 2 + size);
  }

  int intAt(int at) {
    final size = 1 << (bytes[at] & 0x0F);
    if (size == 8) {
      return ByteData.sublistView(bytes, at + 1, at + 9).getInt64(0);
    }
    return _uint(at + 1, size);
  }

  String? stringAt(int at) {
    final type = bytes[at] >> 4;
    final (len, start) = _length(at);
    if (type == 0x5) return latin1.decode(bytes.sublist(start, start + len));
    if (type == 0x6) {
      final units = [for (var i = 0; i < len; i++) _uint(start + i * 2, 2)];
      return String.fromCharCodes(units);
    }
    return null;
  }

  /// Ref of the value stored under [key] in the first dict that has it.
  int? findDictValueRef(String key) {
    for (final at in offsets) {
      if (bytes[at] >> 4 != 0xD) continue;
      final (n, start) = _length(at);
      for (var i = 0; i < n; i++) {
        final keyRef = _uint(start + i * refSize, refSize);
        if (keyRef >= count) continue;
        if (stringAt(offsets[keyRef]) == key) {
          return _uint(start + (n + i) * refSize, refSize);
        }
      }
    }
    return null;
  }

  /// key → value ref of the first dict that has a `Size` key (the MBFile).
  Map<String, int> recordKeys() {
    for (final at in offsets) {
      if (bytes[at] >> 4 != 0xD) continue;
      final (n, start) = _length(at);
      final map = <String, int>{};
      for (var i = 0; i < n; i++) {
        final keyRef = _uint(start + i * refSize, refSize);
        if (keyRef >= count) continue;
        final k = stringAt(offsets[keyRef]);
        if (k != null) map[k] = _uint(start + (n + i) * refSize, refSize);
      }
      if (map.containsKey('Size')) return map;
    }
    return const {};
  }

  /// Follows an NSKeyedArchiver UID (`$objects[uid]`) to its object ref; any
  /// other object is returned as is.
  int resolveUid(int ref) {
    final at = offsets[ref];
    if (bytes[at] >> 4 != 0x8) return ref;
    final uid = _uint(at + 1, (bytes[at] & 0x0F) + 1);
    final topAt = offsets[top];
    final (n, start) = _length(topAt);
    for (var i = 0; i < n; i++) {
      final keyRef = _uint(start + i * refSize, refSize);
      if (stringAt(offsets[keyRef]) == r'$objects') {
        final arrRef = _uint(start + (n + i) * refSize, refSize);
        final (len, aStart) = _length(offsets[arrRef]);
        if (uid >= len) break;
        return _uint(aStart + uid * refSize, refSize);
      }
    }
    throw const FormatException('Broken NSKeyedArchiver reference.');
  }

  /// Raw bytes of every object (from its offset to the next object's).
  List<Uint8List> _objects() {
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => offsets[a].compareTo(offsets[b]));
    final out = List<Uint8List>.filled(count, Uint8List(0));
    for (var k = 0; k < order.length; k++) {
      final start = offsets[order[k]];
      // Next object starting after this one (two refs may share an offset).
      var j = k + 1;
      while (j < order.length && offsets[order[j]] == start) {
        j++;
      }
      final end = j < order.length ? offsets[order[j]] : offsetTable;
      out[order[k]] = Uint8List.sublistView(bytes, start, end);
    }
    return out;
  }

  Uint8List rebuild(Map<int, Uint8List> replacements) {
    final objects = _objects();
    replacements.forEach((ref, b) => objects[ref] = b);
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(bytes, 0, 8)); // "bplist00"
    final newOffsets = <int>[];
    var pos = 8;
    for (final o in objects) {
      newOffsets.add(pos);
      out.add(o);
      pos += o.length;
    }
    final tableAt = pos;
    var oSize = 1;
    while (oSize < 8 && tableAt >= (1 << (8 * oSize))) {
      oSize++;
    }
    for (final off in newOffsets) {
      for (var i = oSize - 1; i >= 0; i--) {
        out.addByte((off >> (8 * i)) & 0xFF);
      }
    }
    final trailer = ByteData(32)
      ..setUint8(6, oSize)
      ..setUint8(7, refSize)
      ..setUint64(8, count)
      ..setUint64(16, top)
      ..setUint64(24, tableAt);
    out.add(trailer.buffer.asUint8List());
    return out.toBytes();
  }
}
