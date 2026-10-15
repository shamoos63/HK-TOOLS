import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../services/repository/ipsw_manifest_reader.dart';

/// What we learned about one file, valid while its size + mtime are unchanged.
class ScanCacheEntry {
  const ScanCacheEntry({
    required this.size,
    required this.modifiedMs,
    this.manifest,
    this.manifestError,
    this.sha1,
  });

  final int size;
  final int modifiedMs;
  final IpswManifest? manifest;
  final String? manifestError;

  /// Computed SHA1 (expensive; kept so verification is a one-time cost).
  final String? sha1;

  ScanCacheEntry copyWith({String? sha1}) => ScanCacheEntry(
    size: size,
    modifiedMs: modifiedMs,
    manifest: manifest,
    manifestError: manifestError,
    sha1: sha1 ?? this.sha1,
  );

  Map<String, dynamic> toJson() => {
    'size': size,
    'mtime': modifiedMs,
    'manifest': manifest?.toJson(),
    'manifestError': manifestError,
    'sha1': sha1,
  };

  static ScanCacheEntry fromJson(Map<String, dynamic> j) => ScanCacheEntry(
    size: (j['size'] as num).toInt(),
    modifiedMs: (j['mtime'] as num).toInt(),
    manifest: j['manifest'] == null
        ? null
        : IpswManifest.fromJson(j['manifest'] as Map<String, dynamic>),
    manifestError: j['manifestError'] as String?,
    sha1: j['sha1'] as String?,
  );
}

/// Hive-backed scan index keyed by absolute path.
class ScanCache {
  ScanCache(this._box);

  static const boxName = 'scan_v1';

  final Box<String> _box;

  ScanCacheEntry? get(
    String path, {
    required int size,
    required int modifiedMs,
  }) {
    final raw = _box.get(path);
    if (raw == null) return null;
    try {
      final e = ScanCacheEntry.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return e.size == size && e.modifiedMs == modifiedMs ? e : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String path, ScanCacheEntry entry) =>
      _box.put(path, jsonEncode(entry.toJson()));

  /// Drops entries under the [prefix] directory whose files no longer exist.
  Future<void> prune(
    String prefix,
    Set<String> alive, {
    List<String> keepUnder = const [],
  }) async {
    final stale = [
      for (final k in _box.keys.cast<String>())
        if (k.startsWith(prefix) &&
            !alive.contains(k) &&
            !keepUnder.any(k.startsWith))
          k,
    ];
    await _box.deleteAll(stale);
  }
}
