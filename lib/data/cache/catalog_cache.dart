import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../domain/entities/device.dart';
import '../../domain/entities/ipsw_release.dart';

class Cached<T> {
  const Cached(this.value, this.fetchedAt);

  final T value;
  final DateTime fetchedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(fetchedAt) < ttl;
}

/// Hive-backed cache of IPSW.me responses so the catalog opens instantly and
/// works offline. Values are stored as JSON strings (no codegen adapters).
class CatalogCache {
  CatalogCache(this._box);

  static const boxName = 'catalog_v1';

  final Box<String> _box;

  Cached<List<Device>>? readDevices() => _read(
    'devices',
    (items) => items.cast<Map<String, dynamic>>().map(Device.fromJson).toList(),
  );

  Future<void> writeDevices(List<Device> devices) =>
      _write('devices', [for (final d in devices) d.toJson()]);

  Cached<List<IpswRelease>>? readFirmwares(String identifier) => _read(
    'fw:$identifier',
    (items) => items
        .cast<Map<String, dynamic>>()
        .map((j) => IpswRelease.fromJson(j, identifier: identifier))
        .toList(),
  );

  Future<void> writeFirmwares(String identifier, List<IpswRelease> releases) =>
      _write('fw:$identifier', [for (final r in releases) r.toJson()]);

  String? readModel(String modelNumber) => _box.get('model:$modelNumber');

  Future<void> writeModel(String modelNumber, String identifier) =>
      _box.put('model:$modelNumber', identifier);

  DateTime? get lastFullSync =>
      DateTime.tryParse(_box.get('lastFullSync') ?? '');

  Future<void> markFullSync() =>
      _box.put('lastFullSync', DateTime.now().toIso8601String());

  Future<void> clear() => _box.clear();

  Cached<T>? _read<T>(String key, T Function(List items) decode) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Cached(
        decode(json['items'] as List),
        DateTime.parse(json['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> items) => _box.put(
    key,
    jsonEncode({'fetchedAt': DateTime.now().toIso8601String(), 'items': items}),
  );
}
