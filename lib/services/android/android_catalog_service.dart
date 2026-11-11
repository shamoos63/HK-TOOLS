import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Friendly names and product photos for Android phones.
///
/// - **Name:** Google Play's public device catalog
///   (`supported_devices.csv`: brand, marketing name, codename, model). It
///   turns `SM-A536E` into "Galaxy A53 5G". Downloaded once and cached for a
///   month.
/// - **Photo:** the Wikipedia page summary API for that name. Only product
///   renders (PNG / WebP) are used; anything else falls back to the app's
///   drawn phone. Photos are cached on disk.
class AndroidCatalogService {
  AndroidCatalogService({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  final String cacheDir;
  final http.Client _client;

  static final _catalogUrl = Uri.parse(
    'https://storage.googleapis.com/play_public/supported_devices.csv',
  );

  Future<String?>? _catalog;

  File get _catalogFile => File(p.join(cacheDir, 'supported_devices.csv'));

  Future<String?> _loadCatalog() async {
    final f = _catalogFile;
    final fresh =
        f.existsSync() &&
        DateTime.now().difference(f.lastModifiedSync()).inDays < 30;
    if (!fresh) {
      try {
        final res = await _client
            .get(_catalogUrl)
            .timeout(const Duration(seconds: 40));
        if (res.statusCode == 200 && res.bodyBytes.length > 1000) {
          await f.parent.create(recursive: true);
          await f.writeAsString(decodeCatalog(res.bodyBytes));
        }
      } on Object {
        // Offline: use an old copy if there is one.
      }
    }
    return f.existsSync() ? f.readAsString() : null;
  }

  /// The catalog is UTF-16 (with BOM) on Google's side; accept UTF-8 too.
  static String decodeCatalog(List<int> bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      final le = bytes[0] == 0xFF;
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2)
          le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
      ];
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// `Samsung Galaxy A53 5G` for model `SM-A536E` (codename helps when
  /// several regions share a model number). `null` when unknown.
  Future<String?> marketingName({
    required String? model,
    String? codename,
  }) async {
    if (model == null || model.isEmpty) return null;
    final csv = await (_catalog ??= _loadCatalog());
    if (csv == null) return null;
    return findName(csv, model: model, codename: codename);
  }

  static String? findName(
    String csv, {
    required String model,
    String? codename,
  }) {
    String? fallback;
    final needle = '"${model.toLowerCase()}"';
    for (final line in const LineSplitter().convert(csv)) {
      if (!line.toLowerCase().endsWith(needle)) continue;
      final cols = _split(line);
      if (cols.length < 4) continue;
      final brand = cols[0].trim();
      final name = cols[1].trim();
      if (name.isEmpty) continue;
      final full =
          name.toLowerCase().startsWith(brand.toLowerCase()) || brand.isEmpty
          ? name
          : '$brand $name';
      if (codename == null || cols[2].toLowerCase() == codename.toLowerCase()) {
        return full;
      }
      fallback ??= full;
    }
    return fallback;
  }

  static List<String> _split(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  File _photoFile(String name) => File(
    p.join(
      cacheDir,
      'photos',
      '${name.replaceAll(RegExp(r'[^\w.-]'), '_')}.img',
    ),
  );

  /// Local product photo for [name] (e.g. "Samsung Galaxy A53 5G"), or
  /// `null`.
  Future<String?> photoFor(String name) async {
    final f = _photoFile(name);
    if (f.existsSync()) return f.lengthSync() > 0 ? f.path : null;
    try {
      final title = Uri.encodeComponent(name.replaceAll(' ', '_'));
      final res = await _client
          .get(
            Uri.parse(
              'https://en.wikipedia.org/api/rest_v1/page/summary/$title',
            ),
            headers: const {'User-Agent': 'HKTools/1.0 (desktop app)'},
          )
          .timeout(const Duration(seconds: 15));
      String? url;
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json is Map && json['type'] == 'standard') {
          final thumb = (json['thumbnail'] as Map?)?['source'] as String?;
          // Product renders are PNG / WebP; JPEGs are usually photos of
          // shops, boxes or people.
          if (thumb != null &&
              RegExp(r'\.(png|webp)', caseSensitive: false).hasMatch(thumb)) {
            url = thumb.replaceFirst(RegExp(r'/\d+px-'), '/400px-');
          }
        }
      }
      await f.parent.create(recursive: true);
      if (url == null) {
        await f.writeAsBytes(const []); // remember "no photo"
        return null;
      }
      final img = await _client
          .get(Uri.parse(url), headers: const {'User-Agent': 'HKTools/1.0'})
          .timeout(const Duration(seconds: 20));
      if (img.statusCode != 200 || img.bodyBytes.isEmpty) return null;
      await f.writeAsBytes(img.bodyBytes);
      return f.path;
    } on Object {
      return null; // Offline: try again next time.
    }
  }
}
