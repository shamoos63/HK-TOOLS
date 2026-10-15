import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Random-access byte source (a local file, or HTTP ranges in tooling).
abstract interface class ByteSource {
  Future<int> length();
  Future<Uint8List> read(int offset, int length);
}

class FileByteSource implements ByteSource {
  FileByteSource(this._raf);

  final RandomAccessFile _raf;

  @override
  Future<int> length() => _raf.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    await _raf.setPosition(offset);
    return _raf.read(length);
  }
}

/// What an IPSW says about itself in `BuildManifest.plist`.
class IpswManifest {
  const IpswManifest({
    required this.productVersion,
    required this.buildVersion,
    required this.supportedProductTypes,
  });

  final String productVersion;
  final String buildVersion;

  /// Device identifiers this IPSW restores (`iPhone13,2`, `Mac14,2`, ...).
  final List<String> supportedProductTypes;

  Map<String, dynamic> toJson() => {
    'v': productVersion,
    'b': buildVersion,
    't': supportedProductTypes,
  };

  static IpswManifest fromJson(Map<String, dynamic> j) => IpswManifest(
    productVersion: j['v'] as String,
    buildVersion: j['b'] as String,
    supportedProductTypes: (j['t'] as List).cast<String>(),
  );
}

class ManifestReadException implements Exception {
  ManifestReadException(this.message);

  final String message;

  @override
  String toString() => 'ManifestReadException: $message';
}

/// Reads `BuildManifest.plist` out of an IPSW (a ZIP, ZIP64 when > 4 GiB)
/// without touching the multi-GB payload: only the end-of-archive records,
/// the central directory and the one compressed entry are read.
class IpswManifestReader {
  static const _eocdSig = 0x06054b50;
  static const _zip64LocatorSig = 0x07064b50;
  static const _zip64EocdSig = 0x06064b50;
  static const _centralSig = 0x02014b50;
  static const _localSig = 0x04034b50;

  static Future<IpswManifest> readFile(String path) async {
    final raf = await File(path).open();
    try {
      return await read(FileByteSource(raf));
    } finally {
      await raf.close();
    }
  }

  static Future<IpswManifest> read(ByteSource src) async {
    final bytes = await extractEntry(src, 'BuildManifest.plist');
    return parsePlist(bytes);
  }

  /// Extracts one entry by exact name from a ZIP / ZIP64 archive.
  static Future<Uint8List> extractEntry(ByteSource src, String name) async {
    final wanted = utf8.encode(name);
    return (await extractMatching(
      src,
      (bytes) => _equals(bytes, wanted),
      description: name,
    )).$2;
  }

  /// Extracts the first entry whose name matches [pattern] (e.g. an app's
  /// `Payload/<Name>.app/Info.plist` inside an IPA). Returns (name, bytes).
  static Future<(String, Uint8List)> extractFirst(
    ByteSource src,
    RegExp pattern,
  ) => extractMatching(
    src,
    (bytes) => pattern.hasMatch(utf8.decode(bytes, allowMalformed: true)),
    description: pattern.pattern,
  );

  static Future<(String, Uint8List)> extractMatching(
    ByteSource src,
    bool Function(Uint8List nameBytes) matches, {
    required String description,
  }) async {
    final name = description;
    final size = await src.length();
    if (size < 22) throw ManifestReadException('Not a ZIP archive');

    // End of central directory: within the last 64 KiB + 22 bytes.
    final tailLen = size < 65557 ? size : 65557;
    final tailStart = size - tailLen;
    final tail = ByteData.sublistView(await src.read(tailStart, tailLen));
    var eocd = -1;
    for (var i = tailLen - 22; i >= 0; i--) {
      if (tail.getUint32(i, Endian.little) == _eocdSig) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw ManifestReadException('ZIP end record not found (truncated file?)');
    }

    var entries = tail.getUint16(eocd + 10, Endian.little);
    var cdSize = tail.getUint32(eocd + 12, Endian.little);
    var cdOffset = tail.getUint32(eocd + 16, Endian.little);

    if (entries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      final loc = eocd - 20;
      if (loc < 0 || tail.getUint32(loc, Endian.little) != _zip64LocatorSig) {
        throw ManifestReadException('ZIP64 locator missing');
      }
      final z64Offset = _u64(tail, loc + 8);
      final z64 = ByteData.sublistView(await src.read(z64Offset, 56));
      if (z64.getUint32(0, Endian.little) != _zip64EocdSig) {
        throw ManifestReadException('ZIP64 end record missing');
      }
      entries = _u64(z64, 32);
      cdSize = _u64(z64, 40);
      cdOffset = _u64(z64, 48);
    }
    if (cdSize > 64 * 1024 * 1024 || cdOffset + cdSize > size) {
      throw ManifestReadException('Central directory out of range');
    }

    final cd = ByteData.sublistView(await src.read(cdOffset, cdSize));
    var p = 0;
    for (var e = 0; e < entries && p + 46 <= cd.lengthInBytes; e++) {
      if (cd.getUint32(p, Endian.little) != _centralSig) {
        throw ManifestReadException('Corrupt central directory');
      }
      final method = cd.getUint16(p + 10, Endian.little);
      var compSize = cd.getUint32(p + 20, Endian.little);
      var uncompSize = cd.getUint32(p + 24, Endian.little);
      final nameLen = cd.getUint16(p + 28, Endian.little);
      final extraLen = cd.getUint16(p + 30, Endian.little);
      final commentLen = cd.getUint16(p + 32, Endian.little);
      var localOffset = cd.getUint32(p + 42, Endian.little);
      final nameBytes = Uint8List.sublistView(cd, p + 46, p + 46 + nameLen);

      if (matches(nameBytes)) {
        final entryName = utf8.decode(nameBytes, allowMalformed: true);
        // ZIP64 extra field carries the real 64-bit values.
        var x = p + 46 + nameLen;
        final xEnd = x + extraLen;
        while (x + 4 <= xEnd) {
          final id = cd.getUint16(x, Endian.little);
          final len = cd.getUint16(x + 2, Endian.little);
          if (id == 0x0001) {
            var q = x + 4;
            if (uncompSize == 0xFFFFFFFF) {
              uncompSize = _u64(cd, q);
              q += 8;
            }
            if (compSize == 0xFFFFFFFF) {
              compSize = _u64(cd, q);
              q += 8;
            }
            if (localOffset == 0xFFFFFFFF) localOffset = _u64(cd, q);
          }
          x += 4 + len;
        }
        if (compSize > 256 * 1024 * 1024) {
          throw ManifestReadException('$name is implausibly large');
        }

        final local = ByteData.sublistView(await src.read(localOffset, 30));
        if (local.getUint32(0, Endian.little) != _localSig) {
          throw ManifestReadException('Bad local header for $name');
        }
        final dataStart =
            localOffset +
            30 +
            local.getUint16(26, Endian.little) +
            local.getUint16(28, Endian.little);
        final data = await src.read(dataStart, compSize);
        return (
          entryName,
          switch (method) {
            0 => data,
            8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(data)),
            _ => throw ManifestReadException(
              'Unsupported compression method $method',
            ),
          },
        );
      }
      p += 46 + nameLen + extraLen + commentLen;
    }
    throw ManifestReadException('$name not found in archive');
  }

  /// Pulls the three top-level keys we need out of an XML plist.
  static IpswManifest parsePlist(Uint8List bytes) {
    if (bytes.length >= 6 &&
        ascii.decode(bytes.sublist(0, 6), allowInvalid: true) == 'bplist') {
      throw ManifestReadException('Binary plist manifests are not supported');
    }
    final xml = utf8.decode(bytes, allowMalformed: true);
    String? str(String key) =>
        RegExp('<key>$key</key>\\s*<string>([^<]*)</string>')
            .firstMatch(xml)
            ?.group(1)
            ?.trim();
    final version = str('ProductVersion');
    final build = str('ProductBuildVersion');
    if (version == null || build == null) {
      throw ManifestReadException(
        'ProductVersion / ProductBuildVersion missing',
      );
    }
    final types = <String>[];
    final arr = RegExp(
      r'<key>SupportedProductTypes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(xml);
    if (arr != null) {
      for (final m in RegExp(
        r'<string>([^<]*)</string>',
      ).allMatches(arr.group(1)!)) {
        types.add(m.group(1)!.trim());
      }
    }
    return IpswManifest(
      productVersion: version,
      buildVersion: build,
      supportedProductTypes: types,
    );
  }

  static int _u64(ByteData d, int offset) =>
      d.getUint32(offset, Endian.little) +
      d.getUint32(offset + 4, Endian.little) * 0x100000000;

  static bool _equals(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
