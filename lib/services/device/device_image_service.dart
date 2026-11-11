import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Product photos of Apple devices, looked up by model identifier
/// (`iPhone15,2`, `iPad14,1`, …).
///
/// Source: the static image CDN Apple's Find My uses for its device list.
/// It is keyed by the same identifier lockdown and `irecovery` report, covers
/// every iPhone, iPad and iPod touch, and needs no API key. When lockdown
/// gives numeric colour codes the matching colour is tried first.
///
/// Images are cached on disk, so a device seen once also shows offline.
class DeviceImageService {
  DeviceImageService({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  final String cacheDir;
  final http.Client _client;

  static const _base = 'https://statici.icloud.com/fmipmobile/deviceImages-9.0';

  /// Find My folder for an identifier, or `null` for families it has no
  /// photos of (Apple TV, Watch, Macs).
  static String? family(String productType) {
    for (final f in const ['iPhone', 'iPad', 'iPod']) {
      if (productType.startsWith(f)) return f;
    }
    return null;
  }

  /// Image keys to try, best first: with colour codes, then the default
  /// colour.
  static List<String> keys(
    String productType, {
    String? color,
    String? enclosureColor,
  }) {
    final numeric = RegExp(r'^\d+$');
    return [
      if (color != null &&
          enclosureColor != null &&
          numeric.hasMatch(color) &&
          numeric.hasMatch(enclosureColor))
        '$productType-$color-$enclosureColor-0',
      productType,
    ];
  }

  static Uri url(String family, String key) =>
      Uri.parse('$_base/$family/$key/online-infobox__3x.png');

  File _file(String key) =>
      File(p.join(cacheDir, '${key.replaceAll(RegExp(r'[^\w.,-]'), '_')}.png'));

  /// Local path of a photo for [productType], downloading it if needed.
  /// `null` when there is no photo (unknown model, offline and not cached).
  Future<String?> imageFor(
    String productType, {
    String? color,
    String? enclosureColor,
  }) async {
    final fam = family(productType);
    if (fam == null) return null;
    final candidates = keys(
      productType,
      color: color,
      enclosureColor: enclosureColor,
    );
    for (final key in candidates) {
      final f = _file(key);
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
    }
    for (final key in candidates) {
      try {
        final res = await _client
            .get(url(fam, key))
            .timeout(const Duration(seconds: 15));
        final bytes = res.bodyBytes;
        // A PNG, not an empty body or an HTML error page.
        if (res.statusCode != 200 ||
            bytes.length < 8 ||
            bytes[0] != 0x89 ||
            bytes[1] != 0x50) {
          continue;
        }
        final f = _file(key);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes);
        return f.path;
      } on Object {
        // Offline or blocked: try the next key, then give up quietly.
      }
    }
    return null;
  }
}
