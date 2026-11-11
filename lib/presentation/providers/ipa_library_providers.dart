import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/folder_access.dart';
import '../../domain/entities/ios_device.dart';
import '../../services/appstore/app_store_service.dart';
import '../../services/appstore/ipa_library.dart';
import '../../services/catalog/catalog_index.dart';
import 'app_store_providers.dart';
import 'core_providers.dart';
import 'device_providers.dart';
import '../../core/l10n/l10n.dart';

/// One app in the library: every `.ipa` of it, newest version first.
class LibraryApp {
  LibraryApp(this.files);

  final List<IpaInfo> files;

  IpaInfo get latest => files.first;
  String get bundleId => latest.bundleId!;
  String get name => latest.displayName;
  int get totalSize => files.fold(0, (a, f) => a + f.size);
}

final ipaLibraryScannerProvider = Provider<IpaLibraryScanner>(
  (ref) => IpaLibraryScanner(
    cacheFile: p.join(ref.watch(appSupportDirProvider), 'ipa_library.json'),
  ),
);

/// Every `.ipa` in the library folder (Settings › Downloads › IPA folder).
class IpaLibraryController extends AsyncNotifier<List<IpaInfo>> {
  @override
  Future<List<IpaInfo>> build() {
    final folder = ref.watch(appStoreDirProvider);
    return ref.watch(ipaLibraryScannerProvider).scan(folder);
  }

  Future<void> rescan() async {
    // Keep showing the current list while rescanning.
    state = await AsyncValue.guard(
      () => ref
          .read(ipaLibraryScannerProvider)
          .scan(ref.read(appStoreDirProvider)),
    );
  }

  /// Copies files into the library folder (existing names are kept, new ones
  /// get a numeric suffix).
  Future<int> import(List<String> paths) async {
    final folder = ref.read(appStoreDirProvider);
    await ensureWritableDirectory(folder);
    var n = 0;
    for (final src in paths) {
      if (p.isWithin(folder, src) || p.dirname(src) == folder) continue;
      var dest = p.join(folder, p.basename(src));
      for (var i = 2; File(dest).existsSync(); i++) {
        dest = p.join(
          folder,
          '${p.basenameWithoutExtension(src)} ($i)${p.extension(src)}',
        );
      }
      await File(src).copy(dest);
      n++;
    }
    await rescan();
    return n;
  }

  Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    }
    await rescan();
  }
}

final ipaLibraryProvider =
    AsyncNotifierProvider<IpaLibraryController, List<IpaInfo>>(
      IpaLibraryController.new,
    );

/// Readable IPAs grouped by bundle id, sorted by name.
final libraryAppsProvider = Provider<List<LibraryApp>>((ref) {
  final files = ref.watch(ipaLibraryProvider).value ?? const [];
  final byId = <String, List<IpaInfo>>{};
  for (final f in files.where((f) => f.readable)) {
    byId.putIfAbsent(f.bundleId!, () => []).add(f);
  }
  final apps = [
    for (final list in byId.values)
      LibraryApp(
        list..sort((a, b) {
          final v = CatalogIndex.compareVersions(
            b.version ?? '',
            a.version ?? '',
          );
          return v != 0 ? v : b.modified.compareTo(a.modified);
        }),
      ),
  ];
  apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return apps;
});

/// Files in the folder that aren't valid IPAs.
final libraryUnreadableProvider = Provider<List<IpaInfo>>(
  (ref) => [
    for (final f in ref.watch(ipaLibraryProvider).value ?? const <IpaInfo>[])
      if (!f.readable) f,
  ],
);

final storeLookupProvider = Provider<StoreLookup>((_) => StoreLookup());

/// Latest App Store version of every library app (checked automatically when
/// the library changes; only bundle ids are sent to Apple).
final libraryListingsProvider = FutureProvider<Map<String, StoreListing>>((
  ref,
) async {
  final ids = ref.watch(libraryAppsProvider).map((a) => a.bundleId).toSet();
  if (ids.isEmpty) return const {};
  final host = Platform.localeName.split(RegExp('[_.-]'));
  final country = host.length > 1 ? host[1].toLowerCase() : 'us';
  return ref
      .watch(storeLookupProvider)
      .lookup(ids, countries: {'us', country}.toList());
});

/// Library apps with a newer App Store version (sidebar badge).
final libraryUpdateCountProvider = Provider<int>((ref) {
  final listings = ref.watch(libraryListingsProvider).value ?? const {};
  return ref
      .watch(libraryAppsProvider)
      .where(
        (a) => isNewerVersion(listings[a.bundleId]?.version, a.latest.version),
      )
      .length;
});

/// Device that "Install" targets: the chosen one, else the first usable.
final libraryTargetIdProvider =
    NotifierProvider<ValueController<String?>, String?>(
      () => ValueController(null),
    );

final libraryTargetProvider = Provider<ConnectedDevice?>((ref) {
  final usable = ref
      .watch(devicesProvider)
      .devices
      .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
      .toList();
  final id = ref.watch(libraryTargetIdProvider);
  return usable.where((d) => d.id == id).firstOrNull ?? usable.firstOrNull;
});

/// Installed user apps on the target device, by bundle id.
final libraryInstalledProvider = Provider<Map<String, InstalledApp>>((ref) {
  final d = ref.watch(libraryTargetProvider);
  if (d == null) return const {};
  final apps = ref.watch(deviceAppsProvider((d.id, false))).value ?? const [];
  return {for (final a in apps) a.bundleId: a};
});

sealed class LibraryJob {
  const LibraryJob();
}

class LibraryJobRunning extends LibraryJob {
  const LibraryJobRunning(this.label);

  final String label;
}

class LibraryJobDone extends LibraryJob {
  const LibraryJobDone(this.message);

  final String message;
}

class LibraryJobFailed extends LibraryJob {
  const LibraryJobFailed(this.message);

  final String message;
}

/// Install / update jobs per bundle id.
class LibraryActions extends Notifier<Map<String, LibraryJob>> {
  @override
  Map<String, LibraryJob> build() => const {};

  void _set(String id, LibraryJob job) => state = {...state, id: job};

  Future<bool> install(IpaInfo ipa, ConnectedDevice device) async {
    final id = ipa.bundleId!;
    _set(
      id,
      LibraryJobRunning(trf('Installing on {0}…', [device.displayName])),
    );
    try {
      await ref.read(deviceServiceProvider).installApp(device, ipa.path);
      _set(
        id,
        LibraryJobDone(
          trf('Installed {0} on {1}', [ipa.version ?? '', device.displayName]),
        ),
      );
      ref.invalidate(deviceAppsProvider((device.id, false)));
      return true;
    } on Object catch (e) {
      _set(id, LibraryJobFailed('$e'));
      return false;
    }
  }

  /// Installs each app's newest file; returns how many succeeded.
  Future<int> installAll(
    Iterable<LibraryApp> apps,
    ConnectedDevice device,
  ) async {
    var ok = 0;
    for (final a in apps) {
      if (await install(a.latest, device)) ok++;
    }
    return ok;
  }

  /// Downloads the current App Store version into the library, then removes
  /// the older files unless Settings keeps them.
  Future<bool> update(LibraryApp app, StoreListing listing) async {
    final id = app.bundleId;
    _set(id, LibraryJobRunning(trf('Downloading {0}…', [listing.version])));
    final path = await ref
        .read(storeDownloadsProvider.notifier)
        .start(
          StoreApp(
            id: app.latest.itemId ?? listing.trackId,
            bundleId: id,
            name: app.name,
            version: listing.version,
            price: listing.price,
          ),
          platform: StorePlatform.iphone,
          versionLabel: listing.version,
          directory: ref.read(appStoreDirProvider),
        );
    if (path == null) {
      final job = ref
          .read(storeDownloadsProvider)
          .where((j) => j.app.bundleId == id)
          .firstOrNull;
      _set(id, LibraryJobFailed(job?.error ?? tr('Download failed')));
      return false;
    }
    if (!ref.read(settingsProvider).keepOldIpaVersions) {
      for (final f in app.files) {
        if (f.path != path && File(f.path).existsSync()) {
          await File(f.path).delete();
        }
      }
    }
    _set(id, LibraryJobDone(trf('Updated to {0}', [listing.version])));
    await ref.read(ipaLibraryProvider.notifier).rescan();
    return true;
  }

  void clear(String bundleId) => state = {...state}..remove(bundleId);
}

final libraryActionsProvider =
    NotifierProvider<LibraryActions, Map<String, LibraryJob>>(
      LibraryActions.new,
    );
