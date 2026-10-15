import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/utils/plist.dart';
import '../catalog/catalog_index.dart';
import '../repository/ipsw_manifest_reader.dart';

/// What an `.ipa` file says about itself.
class IpaInfo {
  const IpaInfo({
    required this.path,
    required this.size,
    required this.modified,
    this.bundleId,
    this.name,
    this.version,
    this.build,
    this.minimumOs,
    this.itemId,
    this.artist,
    this.error,
  });

  final String path;
  final int size;
  final DateTime modified;
  final String? bundleId;
  final String? name;

  /// CFBundleShortVersionString (user-facing, e.g. `25.20.80`).
  final String? version;

  /// CFBundleVersion.
  final String? build;
  final String? minimumOs;

  /// App Store track id from `iTunesMetadata.plist` (ipatool / iTunes IPAs).
  final int? itemId;
  final String? artist;

  /// Set when the file could not be read as an IPA.
  final String? error;

  bool get readable => error == null && bundleId != null;
  String get displayName =>
      name ?? bundleId ?? p.basenameWithoutExtension(path);

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'modified': modified.millisecondsSinceEpoch,
    'bundleId': bundleId,
    'name': name,
    'version': version,
    'build': build,
    'minimumOs': minimumOs,
    'itemId': itemId,
    'artist': artist,
    'error': error,
  };

  static IpaInfo fromJson(Map<String, dynamic> j) => IpaInfo(
    path: j['path'] as String,
    size: j['size'] as int,
    modified: DateTime.fromMillisecondsSinceEpoch(j['modified'] as int),
    bundleId: j['bundleId'] as String?,
    name: j['name'] as String?,
    version: j['version'] as String?,
    build: j['build'] as String?,
    minimumOs: j['minimumOs'] as String?,
    itemId: j['itemId'] as int?,
    artist: j['artist'] as String?,
    error: j['error'] as String?,
  );
}

abstract final class IpaReader {
  static final _infoPlist = RegExp(r'^Payload/[^/]+\.app/Info\.plist$');

  /// Reads `Payload/<App>.app/Info.plist` (usually binary) and, when present,
  /// `iTunesMetadata.plist`, straight from the ZIP without extracting it.
  static Future<IpaInfo> read(String path) async {
    final file = File(path);
    final stat = await file.stat();
    final raf = await file.open();
    try {
      final src = FileByteSource(raf);
      final (_, infoBytes) = await IpswManifestReader.extractFirst(
        src,
        _infoPlist,
      );
      final info = parsePlistBytes(infoBytes);
      if (info is! Map<String, Object?>) {
        throw const FormatException('Info.plist is not a dictionary');
      }
      Map<String, Object?> meta = const {};
      try {
        final m = parsePlistBytes(
          await IpswManifestReader.extractEntry(src, 'iTunesMetadata.plist'),
        );
        if (m is Map<String, Object?>) meta = m;
      } on Object {
        // Sideloaded / self-built IPAs have no store metadata.
      }
      return IpaInfo(
        path: path,
        size: stat.size,
        modified: stat.modified,
        bundleId:
            info.str('CFBundleIdentifier') ??
            meta.str('softwareVersionBundleId'),
        name:
            info.str('CFBundleDisplayName') ??
            meta.str('itemName') ??
            info.str('CFBundleName'),
        version:
            info.str('CFBundleShortVersionString') ??
            meta.str('bundleShortVersionString'),
        build: info.str('CFBundleVersion') ?? meta.str('bundleVersion'),
        minimumOs: info.str('MinimumOSVersion'),
        itemId: meta.integer('itemId'),
        artist: meta.str('artistName'),
      );
    } on Object catch (e) {
      return IpaInfo(
        path: path,
        size: stat.size,
        modified: stat.modified,
        error: e is FormatException ? e.message : '$e',
      );
    } finally {
      await raf.close();
    }
  }
}

/// Finds every `.ipa` under a folder. Results are cached by path + size +
/// modification time, so rescans only open new or changed files.
class IpaLibraryScanner {
  IpaLibraryScanner({required this.cacheFile});

  final String cacheFile;

  /// Subfolder levels searched below the library folder. Bounded because the
  /// library may be a big general folder such as Downloads.
  static const maxDepth = 3;

  static Future<List<File>> _ipaFiles(
    Directory dir, {
    required int depth,
  }) async {
    final out = <File>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (e is File && p.extension(name).toLowerCase() == '.ipa') {
          out.add(e);
        } else if (e is Directory &&
            depth > 0 &&
            // Skip bundles and package internals.
            !name.endsWith('.app') &&
            !name.endsWith('.xcarchive') &&
            name != 'node_modules') {
          out.addAll(await _ipaFiles(e, depth: depth - 1));
        }
      }
    } on FileSystemException {
      // Unreadable subfolder: skip it.
    }
    return out;
  }

  Map<String, IpaInfo> _loadCache() {
    try {
      final f = File(cacheFile);
      if (!f.existsSync()) return {};
      final list = jsonDecode(f.readAsStringSync()) as List;
      return {
        for (final j in list.cast<Map<String, dynamic>>())
          j['path'] as String: IpaInfo.fromJson(j),
      };
    } on Object {
      return {};
    }
  }

  Future<List<IpaInfo>> scan(String folder) async {
    final dir = Directory(folder);
    if (!dir.existsSync()) return const [];
    final cache = _loadCache();
    final out = <IpaInfo>[];
    for (final e in await _ipaFiles(dir, depth: maxDepth)) {
      final stat = await e.stat();
      final hit = cache[e.path];
      out.add(
        hit != null &&
                hit.size == stat.size &&
                hit.modified.millisecondsSinceEpoch ==
                    stat.modified.millisecondsSinceEpoch
            ? hit
            : await IpaReader.read(e.path),
      );
    }
    try {
      final f = File(cacheFile);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode([for (final i in out) i.toJson()]));
    } on FileSystemException {
      // Cache is an optimisation only.
    }
    return out;
  }
}

/// Current App Store listing for an app (iTunes Search API).
class StoreListing {
  const StoreListing({
    required this.bundleId,
    required this.trackId,
    required this.version,
    this.name,
    this.releaseNotes,
    this.releaseDate,
    this.fileSize,
    this.minimumOs,
    this.price = 0,
  });

  final String bundleId;
  final int trackId;
  final String version;
  final String? name;
  final String? releaseNotes;
  final DateTime? releaseDate;
  final int? fileSize;
  final String? minimumOs;
  final double price;
}

class StoreLookup {
  StoreLookup({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Map<String, StoreListing> parse(String body) {
    final out = <String, StoreListing>{};
    final json = jsonDecode(body);
    if (json is! Map || json['results'] is! List) return out;
    for (final r in json['results'] as List) {
      if (r is! Map) continue;
      final id = r['bundleId'];
      final track = r['trackId'];
      final version = r['version'];
      if (id is! String || track is! num || version is! String) continue;
      out[id] = StoreListing(
        bundleId: id,
        trackId: track.toInt(),
        version: version,
        name: r['trackName'] as String?,
        releaseNotes: r['releaseNotes'] as String?,
        releaseDate: DateTime.tryParse(
          '${r['currentVersionReleaseDate'] ?? ''}',
        ),
        fileSize: int.tryParse('${r['fileSizeBytes'] ?? ''}'),
        minimumOs: r['minimumOsVersion'] as String?,
        price: (r['price'] as num?)?.toDouble() ?? 0,
      );
    }
    return out;
  }

  /// Latest listings for [bundleIds], 100 per request, trying each country
  /// in turn for apps not found in the previous one.
  Future<Map<String, StoreListing>> lookup(
    Iterable<String> bundleIds, {
    List<String> countries = const ['us'],
  }) async {
    final left = {...bundleIds};
    final out = <String, StoreListing>{};
    for (final country in countries) {
      final ids = left.toList();
      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.sublist(i, (i + 100).clamp(0, ids.length));
        final res = await _client
            .get(
              Uri.https('itunes.apple.com', '/lookup', {
                'bundleId': chunk.join(','),
                'country': country,
                'entity': 'software',
                'limit': '100',
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) continue;
        final found = parse(res.body);
        out.addAll(found);
        left.removeAll(found.keys);
      }
      if (left.isEmpty) break;
    }
    return out;
  }
}

/// `true` when [store] is a newer version than [local].
bool isNewerVersion(String? store, String? local) =>
    store != null &&
    local != null &&
    CatalogIndex.compareVersions(store, local) > 0;
