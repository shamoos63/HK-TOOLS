import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/catalog_cache.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/ipsw_release.dart';
import '../../services/catalog/catalog_index.dart';
import '../../services/catalog/search_query.dart';
import 'core_providers.dart';
import 'ui_providers.dart' show startSearch;

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(
    ref.watch(ipswApiClientProvider),
    CatalogCache(ref.watch(catalogBoxProvider)),
  ),
);

class CatalogState {
  const CatalogState({
    required this.index,
    this.syncing = false,
    this.syncDone = 0,
    this.syncTotal = 0,
    this.syncErrors = 0,
    this.lastSync,
  });

  final CatalogIndex index;
  final bool syncing;
  final int syncDone;
  final int syncTotal;
  final int syncErrors;
  final DateTime? lastSync;

  double get syncFraction => syncTotal == 0 ? 1 : syncDone / syncTotal;

  CatalogState copyWith({
    CatalogIndex? index,
    bool? syncing,
    int? syncDone,
    int? syncTotal,
    int? syncErrors,
    DateTime? lastSync,
  }) => CatalogState(
    index: index ?? this.index,
    syncing: syncing ?? this.syncing,
    syncDone: syncDone ?? this.syncDone,
    syncTotal: syncTotal ?? this.syncTotal,
    syncErrors: syncErrors ?? this.syncErrors,
    lastSync: lastSync ?? this.lastSync,
  );
}

/// Loads the catalog from cache instantly, then refreshes stale device
/// firmware lists from IPSW.me in the background.
class CatalogController extends AsyncNotifier<CatalogState> {
  StreamSubscription<CatalogSyncEvent>? _sync;
  List<Device> _devices = const [];
  final Map<String, List<IpswRelease>> _firmwares = {};

  @override
  Future<CatalogState> build() async {
    ref.onDispose(() => _sync?.cancel());
    final repo = ref.watch(catalogRepositoryProvider);
    _devices = await repo.loadDevices();
    _firmwares
      ..clear()
      ..addAll(repo.loadCachedFirmwares(_devices.map((d) => d.identifier)));
    scheduleMicrotask(sync);
    return CatalogState(index: _buildIndex(), lastSync: repo.lastFullSync);
  }

  /// Refreshes stale entries, or everything when [force] is set.
  Future<void> sync({bool force = false}) async {
    if (_sync != null || !ref.mounted) return;
    final repo = ref.read(catalogRepositoryProvider);
    if (force) {
      try {
        _devices = await repo.loadDevices(forceRefresh: true);
      } catch (_) {}
      if (!ref.mounted) return;
    }
    final all = [for (final d in _devices) d.identifier];
    final ids = force ? all : repo.staleIdentifiers(all);
    final current = state.value;
    if (ids.isEmpty || current == null) return;

    state = AsyncData(
      current.copyWith(
        syncing: true,
        syncDone: 0,
        syncTotal: ids.length,
        syncErrors: 0,
      ),
    );
    var errors = 0;
    var lastRebuild = DateTime.now();
    final completer = Completer<void>();
    _sync = repo
        .syncFirmwares(ids)
        .listen(
          (event) {
            if (!ref.mounted) return;
            if (event.releases != null) {
              _firmwares[event.identifier] = event.releases!;
            } else {
              errors++;
            }
            final now = DateTime.now();
            final rebuild =
                now.difference(lastRebuild) >
                const Duration(milliseconds: 1500);
            if (rebuild) lastRebuild = now;
            state = AsyncData(
              state.value!.copyWith(
                syncDone: event.done,
                syncErrors: errors,
                index: rebuild ? _buildIndex() : null,
              ),
            );
          },
          onDone: () {
            _sync = null;
            if (ref.mounted) {
              state = AsyncData(
                state.value!.copyWith(
                  index: _buildIndex(),
                  syncing: false,
                  syncErrors: errors,
                  lastSync: DateTime.now(),
                ),
              );
            }
            completer.complete();
          },
        );
    return completer.future;
  }

  CatalogIndex _buildIndex() =>
      CatalogIndex(devices: _devices, firmwares: Map.of(_firmwares));
}

final catalogProvider = AsyncNotifierProvider<CatalogController, CatalogState>(
  CatalogController.new,
);

final catalogIndexProvider = Provider<CatalogIndex>(
  (ref) =>
      ref.watch(catalogProvider.select((s) => s.value?.index)) ??
      CatalogIndex.empty,
);

final searchTextProvider = NotifierProvider<ValueController<String>, String>(
  () => ValueController(startSearch),
);

final searchQueryProvider = Provider<SearchQuery>(
  (ref) => SearchQuery.parse(ref.watch(searchTextProvider)),
);

final modelLookupProvider = FutureProvider.family<String?, String>(
  (ref, model) =>
      ref.watch(catalogRepositoryProvider).resolveModelNumber(model),
);

final searchResultsProvider = Provider<SearchResult>((ref) {
  final index = ref.watch(catalogIndexProvider);
  final query = ref.watch(searchQueryProvider);
  final resolved = <String, String>{};
  for (final m in query.modelNumbers) {
    final id = ref.watch(modelLookupProvider(m)).value;
    if (id != null) resolved[m] = id;
  }
  return index.search(query, resolvedModels: resolved);
});
