import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Parses an XML property list (as printed by the libimobiledevice tools with
/// `-x` / `--xml`) into plain Dart values:
/// `dict` → `Map<String, Object?>`, `array` → `List<Object?>`, `integer` → `int`,
/// `real` → `double`, `true`/`false` → `bool`, `date` → `DateTime`,
/// `data` → `Uint8List`, `string` → `String`.
///
/// Tools sometimes print warnings before the document, so parsing starts at
/// the first `<?xml` or `<plist`.
Object? parsePlistXml(String text) {
  var start = text.indexOf('<?xml');
  if (start < 0) start = text.indexOf('<plist');
  if (start < 0) throw const FormatException('No property list in output');
  final end = text.lastIndexOf('</plist>');
  final doc = XmlDocument.parse(
    end < 0 ? text.substring(start) : text.substring(start, end + 8),
  );
  final root = doc.rootElement;
  final first = root.name.local == 'plist'
      ? root.childElements.firstOrNull
      : root;
  return first == null ? null : _value(first);
}

/// [parsePlistXml] for output whose top level must be a dictionary.
Map<String, Object?> parsePlistDict(String text) {
  final v = parsePlistXml(text);
  if (v is Map<String, Object?>) return v;
  throw const FormatException('Property list is not a dictionary');
}

Object? _value(XmlElement e) {
  switch (e.name.local) {
    case 'dict':
      final out = <String, Object?>{};
      String? key;
      for (final c in e.childElements) {
        if (c.name.local == 'key') {
          key = c.innerText;
        } else if (key != null) {
          out[key] = _value(c);
          key = null;
        }
      }
      return out;
    case 'array':
      return [for (final c in e.childElements) _value(c)];
    case 'string':
      return e.innerText;
    case 'integer':
      final t = e.innerText.trim();
      return int.tryParse(t) ?? BigInt.tryParse(t)?.toInt() ?? 0;
    case 'real':
      return double.tryParse(e.innerText.trim()) ?? 0.0;
    case 'true':
      return true;
    case 'false':
      return false;
    case 'date':
      return DateTime.tryParse(e.innerText.trim());
    case 'data':
      final b64 = e.innerText.replaceAll(RegExp(r'\s'), '');
      try {
        return Uint8List.fromList(base64.decode(b64));
      } on FormatException {
        return Uint8List(0);
      }
    default:
      return e.innerText;
  }
}

/// Typed lookups for the loosely typed maps [parsePlistXml] returns.
extension PlistMap on Map<String, Object?> {
  String? str(String key) {
    final v = this[key];
    return v == null ? null : '$v';
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? real(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool? boolean(String key) {
    final v = this[key];
    if (v is bool) return v;
    if (v is int) return v != 0;
    return null;
  }

  Map<String, Object?>? dict(String key) {
    final v = this[key];
    return v is Map<String, Object?> ? v : null;
  }
}

/// Parses a property list in either format: binary (`bplist00`, how most
/// app `Info.plist` files ship inside IPAs) or XML.
Object? parsePlistBytes(Uint8List bytes) {
  if (bytes.length >= 8 &&
      String.fromCharCodes(bytes.sublist(0, 6)) == 'bplist') {
    return _BinaryPlist(bytes).parse();
  }
  return parsePlistXml(utf8.decode(bytes, allowMalformed: true));
}

/// Minimal `bplist00` decoder (Apple CoreFoundation format): trailer, offset
/// table, and the object types used in app metadata.
class _BinaryPlist {
  _BinaryPlist(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  late final int _offsetSize;
  late final int _refSize;
  late final int _offsetTable;
  late final int _count;
  final _depth = <int>{};

  Object? parse() {
    if (bytes.length < 40) throw const FormatException('Truncated bplist');
    final t = bytes.length - 32;
    _offsetSize = bytes[t + 6];
    _refSize = bytes[t + 7];
    _count = _uint(t + 8, 8);
    final top = _uint(t + 16, 8);
    _offsetTable = _uint(t + 24, 8);
    if (_offsetSize < 1 || _refSize < 1 || _offsetTable >= bytes.length) {
      throw const FormatException('Corrupt bplist trailer');
    }
    return _object(top);
  }

  int _uint(int at, int size) {
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = (v << 8) | bytes[at + i];
    }
    return v;
  }

  int _offsetOf(int ref) {
    if (ref >= _count) throw const FormatException('bplist ref out of range');
    return _uint(_offsetTable + ref * _offsetSize, _offsetSize);
  }

  /// Length encoded in a marker's low nibble, or in a following int object.
  (int, int) _length(int at) {
    final low = bytes[at] & 0x0F;
    if (low != 0x0F) return (low, at + 1);
    final intMarker = bytes[at + 1];
    final size = 1 << (intMarker & 0x0F);
    return (_uint(at + 2, size), at + 2 + size);
  }

  Object? _object(int ref) {
    // Guards against reference cycles in malformed files.
    if (!_depth.add(ref)) throw const FormatException('bplist cycle');
    try {
      return _decode(_offsetOf(ref));
    } finally {
      _depth.remove(ref);
    }
  }

  Object? _decode(int at) {
    final marker = bytes[at];
    final type = marker >> 4;
    switch (type) {
      case 0x0:
        return switch (marker) {
          0x08 => false,
          0x09 => true,
          _ => null,
        };
      case 0x1:
        final size = 1 << (marker & 0x0F);
        if (size == 8) return data.getInt64(at + 1);
        return _uint(at + 1, size);
      case 0x2:
        return (marker & 0x0F) == 2
            ? data.getFloat32(at + 1)
            : data.getFloat64(at + 1);
      case 0x3:
        final seconds = data.getFloat64(at + 1);
        return DateTime.utc(2001)
            .add(Duration(microseconds: (seconds * 1e6).round()));
      case 0x4:
        final (len, start) = _length(at);
        return Uint8List.fromList(bytes.sublist(start, start + len));
      case 0x5:
        final (len, start) = _length(at);
        return latin1.decode(bytes.sublist(start, start + len));
      case 0x6:
        final (len, start) = _length(at);
        final units = [
          for (var i = 0; i < len; i++) data.getUint16(start + i * 2),
        ];
        return String.fromCharCodes(units);
      case 0x8:
        return _uint(at + 1, (marker & 0x0F) + 1);
      case 0xA:
        final (len, start) = _length(at);
        return [
          for (var i = 0; i < len; i++)
            _object(_uint(start + i * _refSize, _refSize)),
        ];
      case 0xD:
        final (len, start) = _length(at);
        final out = <String, Object?>{};
        for (var i = 0; i < len; i++) {
          final key = _object(_uint(start + i * _refSize, _refSize));
          final value = _object(_uint(start + (len + i) * _refSize, _refSize));
          out['$key'] = value;
        }
        return out;
      default:
        throw FormatException(
          'Unsupported bplist object 0x${marker.toRadixString(16)}',
        );
    }
  }
}
