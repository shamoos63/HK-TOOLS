import 'dart:async';

import '../../domain/entities/device.dart';
import '../../domain/entities/ipsw_release.dart';
import '../api/ipsw_api_client.dart';
import '../cache/catalog_cache.dart';

/// One device's firmware list arriving during a catalog sync.
class CatalogSyncEvent {
  const CatalogSyncEvent({
    required this.done,
    required this.total,
    required this.identifier,
    this.releases,
    this.error,
  });

  final int done;
  final int total;
  final String identifier;
  final List<IpswRelease>? releases;
  final Object? error;
}

/// Cache-first access to the IPSW.me catalog.
class CatalogRepository {
  CatalogRepository(this._api, this._cache);

  static const deviceTtl = Duration(hours: 24);
  static const firmwareTtl = Duration(hours: 6);

  final IpswApiClient _api;
  final CatalogCache _cache;

  DateTime? get lastFullSync => _cache.lastFullSync;

  /// Devices from cache when fresh, otherwise from the API. Falls back to a
  /// stale cache when offline.
  Future<List<Device>> loadDevices({bool forceRefresh = false}) async {
    final cached = _cache.readDevices();
    if (!forceRefresh && cached != null && cached.isFresh(deviceTtl)) {
      return cached.value;
    }
    try {
      final devices = await _api.fetchDevices();
      await _cache.writeDevices(devices);
      return devices;
    } catch (_) {
      if (cached != null) return cached.value;
      rethrow;
    }
  }

  /// Whatever firmware lists are already cached, regardless of age.
  Map<String, List<IpswRelease>> loadCachedFirmwares(Iterable<String> ids) => {
    for (final id in ids)
      if (_cache.readFirmwares(id) case final cached?) id: cached.value,
  };

  /// Identifiers whose firmware list is missing or older than the TTL.
  List<String> staleIdentifiers(Iterable<String> ids) => [
    for (final id in ids)
      if (!(_cache.readFirmwares(id)?.isFresh(firmwareTtl) ?? false)) id,
  ];

  /// Fetches firmware lists for [ids] with bounded concurrency.
  Stream<CatalogSyncEvent> syncFirmwares(
    List<String> ids, {
    int concurrency = 8,
  }) {
    final controller = StreamController<CatalogSyncEvent>();
    var next = 0;
    var done = 0;
    var cancelled = false;

    Future<void> worker() async {
      while (!cancelled && next < ids.length) {
        final id = ids[next++];
        try {
          final releases = await _api.fetchDeviceFirmwares(id);
          await _cache.writeFirmwares(id, releases);
          done++;
          if (!cancelled) {
            controller.add(
              CatalogSyncEvent(
                done: done,
                total: ids.length,
                identifier: id,
                releases: releases,
              ),
            );
          }
        } catch (e) {
          done++;
          if (!cancelled) {
            controller.add(
              CatalogSyncEvent(
                done: done,
                total: ids.length,
                identifier: id,
                error: e,
              ),
            );
          }
        }
      }
    }

    controller.onListen = () async {
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      if (!cancelled && ids.isNotEmpty) await _cache.markFullSync();
      await controller.close();
    };
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }

  /// Marketing model number (`A2403`) → identifier (`iPhone13,2`).
  Future<String?> resolveModelNumber(String modelNumber) async {
    final key = modelNumber.toUpperCase();
    final cached = _cache.readModel(key);
    if (cached != null) return cached;
    try {
      final id = await _api.fetchIdentifierForModel(key);
      if (id != null) await _cache.writeModel(key, id);
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() => _cache.clear();
}
