import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes a minimal IPSW-like ZIP: a padding blob plus `BuildManifest.plist`
/// (deflated). [zip64] forces ZIP64 end records like real >4 GiB IPSWs.
Future<File> writeFakeIpsw(
  String path, {
  required String version,
  required String build,
  required List<String> productTypes,
  int paddingBytes = 4096,
  bool zip64 = false,
  int seed = 1,
}) async {
  final plist =
      '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>BuildIdentities</key><array><dict><key>Info</key><dict>
    <key>BuildNumber</key><string>$build</string></dict></dict></array>
  <key>ManifestVersion</key><integer>0</integer>
  <key>ProductBuildVersion</key><string>$build</string>
  <key>ProductVersion</key><string>$version</string>
  <key>SupportedProductTypes</key><array>
${productTypes.map((t) => '    <string>$t</string>').join('\n')}
  </array>
</dict></plist>''';
  final padding = Uint8List(paddingBytes);
  for (var i = 0; i < paddingBytes; i++) {
    padding[i] = (i * 31 + seed) & 0xff;
  }
  final entries = [
    _Entry('Firmware/payload.bin', padding, compress: false),
    _Entry(
      'BuildManifest.plist',
      Uint8List.fromList(utf8.encode(plist)),
      compress: true,
    ),
  ];

  final out = BytesBuilder();
  final central = BytesBuilder();
  for (final e in entries) {
    final data = e.compress
        ? Uint8List.fromList(ZLibEncoder(raw: true).convert(e.data))
        : e.data;
    final name = utf8.encode(e.name);
    final offset = out.length;
    out.add(_le32(0x04034b50));
    out.add(_le16(20));
    out.add(_le16(0));
    out.add(_le16(e.compress ? 8 : 0));
    out.add(_le32(0)); // time/date
    out.add(_le32(0)); // crc (not checked by the reader)
    out.add(_le32(data.length));
    out.add(_le32(e.data.length));
    out.add(_le16(name.length));
    out.add(_le16(0));
    out.add(name);
    out.add(data);

    // In ZIP64 mode, push sizes/offset into the extra field.
    final extra = zip64
        ? (BytesBuilder()
                ..add(_le16(0x0001))
                ..add(_le16(24))
                ..add(_le64(e.data.length))
                ..add(_le64(data.length))
                ..add(_le64(offset)))
              .takeBytes()
        : Uint8List(0);
    central.add(_le32(0x02014b50));
    central.add(_le16(45));
    central.add(_le16(45));
    central.add(_le16(0));
    central.add(_le16(e.compress ? 8 : 0));
    central.add(_le32(0));
    central.add(_le32(0));
    central.add(_le32(zip64 ? 0xFFFFFFFF : data.length));
    central.add(_le32(zip64 ? 0xFFFFFFFF : e.data.length));
    central.add(_le16(name.length));
    central.add(_le16(extra.length));
    central.add(_le16(0));
    central.add(_le16(0));
    central.add(_le16(0));
    central.add(_le32(0));
    central.add(_le32(zip64 ? 0xFFFFFFFF : offset));
    central.add(name);
    central.add(extra);
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  if (zip64) {
    final z64Offset = out.length;
    out.add(_le32(0x06064b50));
    out.add(_le64(44));
    out.add(_le16(45));
    out.add(_le16(45));
    out.add(_le32(0));
    out.add(_le32(0));
    out.add(_le64(entries.length));
    out.add(_le64(entries.length));
    out.add(_le64(cd.length));
    out.add(_le64(cdOffset));
    out.add(_le32(0x07064b50));
    out.add(_le32(0));
    out.add(_le64(z64Offset));
    out.add(_le32(1));
  }
  out.add(_le32(0x06054b50));
  out.add(_le16(0));
  out.add(_le16(0));
  out.add(_le16(zip64 ? 0xFFFF : entries.length));
  out.add(_le16(zip64 ? 0xFFFF : entries.length));
  out.add(_le32(zip64 ? 0xFFFFFFFF : cd.length));
  out.add(_le32(zip64 ? 0xFFFFFFFF : cdOffset));
  out.add(_le16(0));

  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(out.takeBytes());
}

class _Entry {
  _Entry(this.name, this.data, {required this.compress});

  final String name;
  final Uint8List data;
  final bool compress;
}

Uint8List _le16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _le32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _le64(int v) => Uint8List(8)
  ..buffer.asByteData().setUint32(0, v & 0xFFFFFFFF, Endian.little)
  ..buffer.asByteData().setUint32(4, v ~/ 0x100000000, Endian.little);
