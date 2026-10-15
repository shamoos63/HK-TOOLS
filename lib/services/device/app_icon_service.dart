import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// App icons for the Apps tab and the App Store screen.
///
/// Source order: disk cache → Apple's public iTunes Search API (batched, one
/// request per 100 bundle IDs; covers App Store apps) → the device's own
/// SpringBoard icon (built-in apps; caller supplies [fromDevice]).
class AppIconService {
  AppIconService({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  final String cacheDir;
  final http.Client _client;

  static const _batch = 100;

  File cacheFile(String bundleId) => File(
    p.join(cacheDir, '${bundleId.replaceAll(RegExp(r'[^\w.-]'), '_')}.png'),
  );

  String? cached(String bundleId) {
    final f = cacheFile(bundleId);
    return f.existsSync() && f.lengthSync() > 0 ? f.path : null;
  }

  /// Artwork URLs (256 px) by bundle ID from the iTunes Search API.
  Future<Map<String, String>> lookupArtwork(
    List<String> bundleIds, {
    String country = 'us',
  }) async {
    final out = <String, String>{};
    for (var i = 0; i < bundleIds.length; i += _batch) {
      final chunk = bundleIds.sublist(
        i,
        (i + _batch).clamp(0, bundleIds.length),
      );
      final uri = Uri.https('itunes.apple.com', '/lookup', {
        'bundleId': chunk.join(','),
        'country': country,
        'entity': 'software',
        'limit': '$_batch',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) continue;
      out.addAll(parseLookup(res.body));
    }
    return out;
  }

  static Map<String, String> parseLookup(String body) {
    final out = <String, String>{};
    final json = jsonDecode(body);
    if (json is! Map || json['results'] is! List) return out;
    for (final r in json['results'] as List) {
      if (r is! Map) continue;
      final id = r['bundleId'];
      final url = r['artworkUrl512'] ?? r['artworkUrl100'] ?? r['artworkUrl60'];
      if (id is String && url is String) {
        // mzstatic serves any size: …/100x100bb.jpg → 256x256bb.png
        out[id] = url.replaceFirst(
          RegExp(r'/\d+x\d+bb\.(jpg|png)$'),
          '/256x256bb.png',
        );
      }
    }
    return out;
  }

  Future<String?> download(String bundleId, String url) async {
    final res = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final f = cacheFile(bundleId);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(res.bodyBytes);
    return f.path;
  }

  /// Fills [missing] icons; calls [onIcon] as each one lands. Bundle IDs that
  /// still have no icon are returned.
  Future<Set<String>> resolve(
    Iterable<String> missing, {
    required void Function(String bundleId, String path) onIcon,
    List<String> countries = const ['us'],
    Future<void> Function(String bundleId, String outPath)? fromDevice,
  }) async {
    final left = {...missing};
    for (final country in countries) {
      if (left.isEmpty) break;
      try {
        final urls = await lookupArtwork(left.toList(), country: country);
        await Future.wait([
          for (final e in urls.entries)
            download(e.key, e.value).then((path) {
              if (path != null) {
                left.remove(e.key);
                onIcon(e.key, path);
              }
            }, onError: (_) {}),
        ]);
      } on Object {
        // Offline: fall through to the device.
      }
    }
    if (fromDevice != null) {
      for (final id in left.toList()) {
        final f = cacheFile(id);
        try {
          await f.parent.create(recursive: true);
          await fromDevice(id, f.path);
          if (f.existsSync() && f.lengthSync() > 0) {
            left.remove(id);
            onIcon(id, f.path);
          }
        } on Object {
          // No icon for this one (e.g. hidden system component).
        }
      }
    }
    return left;
  }
}
