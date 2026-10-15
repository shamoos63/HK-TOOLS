import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../data/cache/scan_cache.dart';
import '../../domain/entities/download_task.dart';
import '../../services/download/sha1_verifier.dart';
import '../../services/repository/repository_actions.dart';
import '../../services/repository/repository_inventory.dart';
import '../../services/repository/repository_scanner.dart';
import 'catalog_providers.dart';
import 'core_providers.dart';
import 'download_providers.dart';

final scanBoxProvider = Provider<Box<String>>(
  (_) => throw UnimplementedError(),
);

final repositoryScannerProvider = Provider<RepositoryScanner>(
  (ref) => RepositoryScanner(ScanCache(ref.watch(scanBoxProvider))),
);

class RepositoryState {
  const RepositoryState({
    this.entries = const [],
    this.scanning = false,
    this.done = 0,
    this.total = 0,
    this.currentPath,
    this.scannedAt,
    this.error,
    this.hashing = const {},
    this.busy = const {},
    this.skipped = const [],
    this.accessDenied = false,
  });

  /// Paths skipped during the last scan because they could not be read.
  final List<String> skipped;

  /// The repository folder itself could not be read.
  final bool accessDenied;

  final List<ScanEntry> entries;
  final bool scanning;
  final int done;
  final int total;
  final String? currentPath;
  final DateTime? scannedAt;
  final String? error;

  /// Physical file identity → SHA1 progress (0..1).
  final Map<String, double> hashing;

  /// Payload keys / identities with an operation in flight.
  final Set<String> busy;

  RepositoryState copyWith({
    List<ScanEntry>? entries,
    bool? scanning,
    int? done,
    int? total,
    String? Function()? currentPath,
    DateTime? scannedAt,
    String? Function()? error,
    Map<String, double>? hashing,
    Set<String>? busy,
    List<String>? skipped,
    bool? accessDenied,
  }) => RepositoryState(
    entries: entries ?? this.entries,
    scanning: scanning ?? this.scanning,
    done: done ?? this.done,
    total: total ?? this.total,
    currentPath: currentPath != null ? currentPath() : this.currentPath,
    scannedAt: scannedAt ?? this.scannedAt,
    error: error != null ? error() : this.error,
    hashing: hashing ?? this.hashing,
    busy: busy ?? this.busy,
    skipped: skipped ?? this.skipped,
    accessDenied: accessDenied ?? this.accessDenied,
  );
}

class RepositoryController extends Notifier<RepositoryState> {
  bool _rescanQueued = false;

  @override
  RepositoryState build() {
    ref.listen(
      settingsProvider.select((s) => s.targetDirectory),
      (_, _) => scan(),
    );
    scheduleMicrotask(scan);
    return const RepositoryState();
  }

  String get _folder => ref.read(settingsProvider).targetDirectory;

  Future<void> scan() async {
    if (!ref.mounted) return;
    if (state.scanning) {
      _rescanQueued = true;
      return;
    }
    state = state.copyWith(
      scanning: true,
      done: 0,
      total: 0,
      error: () => null,
      accessDenied: false,
    );
    try {
      await for (final pr
          in ref.read(repositoryScannerProvider).scan(_folder)) {
        if (!ref.mounted) return;
        state = state.copyWith(
          done: pr.done,
          total: pr.total,
          currentPath: () => pr.currentPath,
          entries: pr.entries,
          skipped: pr.skipped,
          scannedAt: pr.isComplete ? DateTime.now() : null,
        );
      }
    } on RepositoryAccessException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          entries: const [],
          skipped: [e.folder],
          accessDenied: true,
          error: () => 'No permission to read this folder.',
        );
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => 'Scan failed: $e');
    } finally {
      if (ref.mounted) {
        state = state.copyWith(scanning: false, currentPath: () => null);
      }
    }
    if (_rescanQueued) {
      _rescanQueued = false;
      await scan();
    }
  }

  /// Computes (or reuses) the SHA1 of a physical file and records it.
  Future<String> sha1Of(PhysicalFile file) async {
    final cached = file.sha1;
    if (cached != null) return cached;
    final id = file.identityId;
    state = state.copyWith(hashing: {...state.hashing, id: 0});
    try {
      final job = Sha1Verifier.start(
        file.primary.path,
        onProgress: (f) {
          if (ref.mounted) {
            state = state.copyWith(hashing: {...state.hashing, id: f});
          }
        },
      );
      final sha = await job.result;
      final scanner = ref.read(repositoryScannerProvider);
      final updated = <ScanEntry>[];
      for (final e in state.entries) {
        if (e.identity.id == id) {
          await scanner.rememberSha1(e, sha);
          updated.add(e.withSha1(sha));
        } else {
          updated.add(e);
        }
      }
      if (ref.mounted) state = state.copyWith(entries: updated);
      return sha;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(hashing: {...state.hashing}..remove(id));
      }
    }
  }

  Future<void> verify(PhysicalFile file) => sha1Of(file);

  /// Hashes every identified-but-unverified file, one at a time.
  Future<void> verifyAll(List<PhysicalFile> files) async {
    for (final f in files) {
      if (!ref.mounted) return;
      if (f.integrity == Integrity.unverified) await sha1Of(f);
    }
  }

  /// Merges duplicate copies into hardlinks. Returns bytes freed.
  Future<int> reclaim(DuplicateSet set) async {
    final key = set.group.payloadKey;
    state = state.copyWith(busy: {...state.busy, key});
    try {
      return await RepositoryActions.reclaim(set, sha1Of);
    } finally {
      if (ref.mounted) {
        state = state.copyWith(busy: {...state.busy}..remove(key));
      }
      await scan();
    }
  }

  Future<int> createDeviceLinks(PhysicalFile file) async {
    state = state.copyWith(busy: {...state.busy, file.identityId});
    try {
      return await RepositoryActions.createDeviceLinks(
        folder: _folder,
        sourcePath: file.primary.path,
        deviceIdentifiers: file.deviceIdentifiers,
        version: file.version,
        buildId: file.buildId,
      );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(busy: {...state.busy}..remove(file.identityId));
      }
      await scan();
    }
  }
}

final repositoryProvider =
    NotifierProvider<RepositoryController, RepositoryState>(
      RepositoryController.new,
    );

final inventoryProvider = Provider<RepositoryInventory>((ref) {
  final entries = ref.watch(repositoryProvider.select((s) => s.entries));
  return RepositoryInventory.analyze(
    ref.watch(settingsProvider.select((s) => s.targetDirectory)),
    entries,
    ref.watch(catalogIndexProvider),
  );
});

/// Reacts to finished downloads: per-device hardlinks + repository rescan.
final postDownloadHookProvider = Provider<void>((ref) {
  bool finished(DownloadTask t) =>
      t.status == DownloadStatus.completed &&
      t.verification != VerificationState.pending &&
      t.verification != VerificationState.verifying;

  ref.listen(downloadTasksProvider, (prev, next) async {
    final before = {
      for (final t in prev?.value ?? const <DownloadTask>[]) t.id: t,
    };
    var changed = false;
    for (final t in next.value ?? const <DownloadTask>[]) {
      final b = before[t.id];
      if (b == null || finished(b) || !finished(t)) continue;
      changed = true;
      if (ref.read(settingsProvider).autoDeviceLinks) {
        try {
          await RepositoryActions.createDeviceLinks(
            folder: t.targetDirectory,
            sourcePath: t.targetPath,
            deviceIdentifiers: t.deviceIdentifiers,
            version: t.version,
            buildId: t.buildId,
          );
        } catch (_) {
          // Different volume / permissions: the file itself is still fine.
        }
      }
    }
    if (changed && ref.mounted) {
      unawaited(ref.read(repositoryProvider.notifier).scan());
    }
  });
});
