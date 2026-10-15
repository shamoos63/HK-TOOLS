import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/folder_access.dart';
import '../../data/repositories/json_download_task_repository.dart';
import '../../data/resolvers/ipsw_me_link_resolver.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/ipsw_release.dart';
import '../../services/download/download_manager.dart';
import '../../services/download/download_progress.dart';
import 'core_providers.dart';

DownloadManagerSettings managerSettingsFrom(AppSettings s) =>
    DownloadManagerSettings(
      maxConcurrentDownloads: s.maxConcurrentDownloads,
      defaultThreads: s.threads,
      autoVerifySha1: s.autoVerifySha1,
      globalSpeedLimitBytesPerSecond: s.globalSpeedLimitBytesPerSecond,
    );

final downloadManagerProvider = FutureProvider<DownloadManager>((ref) async {
  final manager = DownloadManager(
    repository: JsonDownloadTaskRepository(
      p.join(ref.watch(appSupportDirProvider), 'download_queue.json'),
    ),
    linkResolver: IpswMeLinkResolver(
      ref.watch(ipswApiClientProvider),
      timeout: () => ref.read(settingsProvider).linkRefreshTimeout,
    ),
    settings: managerSettingsFrom(ref.read(settingsProvider)),
  );
  ref.listen(
    settingsProvider,
    (_, next) => manager.updateSettings(managerSettingsFrom(next)),
  );
  ref.onDispose(manager.dispose);
  await manager.init();
  return manager;
});

final downloadTasksProvider = StreamProvider<List<DownloadTask>>((ref) async* {
  final manager = await ref.watch(downloadManagerProvider.future);
  yield manager.tasks;
  yield* manager.taskStream;
});

/// Live (non-cancelled) task for each catalog payload key.
final payloadTasksProvider = Provider<Map<String, DownloadTask>>((ref) {
  final tasks = ref.watch(downloadTasksProvider).value ?? const [];
  return {
    for (final t in tasks)
      if (t.status != DownloadStatus.cancelled) t.payloadKey: t,
  };
});

/// Live telemetry (per-thread speeds, ETA) for one task.
final downloadProgressProvider =
    StreamProvider.family<DownloadProgress, String>((ref, taskId) async* {
      final manager = await ref.watch(downloadManagerProvider.future);
      final latest = manager.progressOf(taskId);
      if (latest != null) yield latest;
      yield* manager.progressStream.where((p) => p.taskId == taskId);
    });

class HudTelemetry {
  const HudTelemetry({
    required this.bytesPerSecond,
    required this.history,
    required this.active,
    required this.queued,
  });

  final double bytesPerSecond;

  /// Recent aggregate speed samples (oldest first) for the bandwidth meter.
  final List<double> history;
  final int active;
  final int queued;
}

/// Aggregate bandwidth sampled twice a second.
final hudTelemetryProvider = StreamProvider<HudTelemetry>((ref) async* {
  final manager = await ref.watch(downloadManagerProvider.future);
  final history = <double>[];
  HudTelemetry sample() {
    final speed = manager.totalBytesPerSecond;
    history.add(speed);
    if (history.length > 120) history.removeAt(0);
    return HudTelemetry(
      bytesPerSecond: speed,
      history: List.unmodifiable(history),
      active: manager.tasks.where((t) => t.status.isActive).length,
      queued: manager.queuedCount,
    );
  }

  yield sample();
  yield* Stream.periodic(const Duration(milliseconds: 500), (_) => sample());
});

/// UI-facing commands that need both the manager and current settings.
class DownloadActions {
  DownloadActions(this._ref);

  final Ref _ref;

  Future<DownloadManager> get _manager =>
      _ref.read(downloadManagerProvider.future);

  /// Queues payloads (deduplicated by the manager). Returns tasks created or
  /// reused.
  ///
  /// Throws [FolderAccessException] when the download folder can't be used
  /// (drive unplugged, no permission).
  Future<List<DownloadTask>> queue(Iterable<IpswGroup> groups) async {
    final manager = await _manager;
    final s = _ref.read(settingsProvider);
    await ensureWritableDirectory(s.targetDirectory);
    if (s.tempDirectory != null) {
      await ensureWritableDirectory(s.tempDirectory!);
    }
    return [
      for (final g in groups)
        manager.enqueue(
          g,
          targetDirectory: s.targetDirectory,
          tempDirectory: s.tempDirectory,
          threads: s.threads,
        ),
    ];
  }

  Future<void> run(void Function(DownloadManager m) action) async =>
      action(await _manager);
}

final downloadActionsProvider = Provider<DownloadActions>(DownloadActions.new);
