import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../core/utils/folder_access.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/ipsw_release.dart';
import '../../domain/repositories/download_task_repository.dart';
import '../../domain/repositories/link_resolver.dart';
import 'bandwidth_throttler.dart';
import 'chunked_downloader.dart';
import 'download_exceptions.dart';
import 'download_progress.dart';
import 'sha1_verifier.dart';

class DownloadManagerSettings {
  const DownloadManagerSettings({
    this.maxConcurrentDownloads = 2,
    this.defaultThreads = 8,
    this.autoVerifySha1 = true,
    this.globalSpeedLimitBytesPerSecond = 0,
    this.engine = const ChunkedDownloaderConfig(),
  });

  final int maxConcurrentDownloads;
  final int defaultThreads;
  final bool autoVerifySha1;
  final int globalSpeedLimitBytesPerSecond;

  /// Engine defaults; `threads` is overridden per task.
  final ChunkedDownloaderConfig engine;
}

/// Owns the download queue: ordering, concurrency limit, pause / resume /
/// cancel / retry, bandwidth caps, link refresh and post-download SHA1.
///
/// The list order *is* the queue priority: the first `queued` task in the
/// list starts next.
class DownloadManager {
  DownloadManager({
    required this._repository,
    required this._linkResolver,
    DownloadManagerSettings settings = const DownloadManagerSettings(),
    this._httpClientFactory,
  }) : _settings = settings,
       _globalThrottler = BandwidthThrottler(
         bytesPerSecond: settings.globalSpeedLimitBytesPerSecond,
       );

  final DownloadTaskRepository _repository;
  final LinkResolver _linkResolver;
  final HttpClient Function()? _httpClientFactory;
  final BandwidthThrottler _globalThrottler;
  DownloadManagerSettings _settings;

  final List<DownloadTask> _tasks = [];
  final Map<String, _ActiveRun> _runs = {};
  final _tasksController = StreamController<List<DownloadTask>>.broadcast();
  final _progressController = StreamController<DownloadProgress>.broadcast();
  final Map<String, DownloadProgress> _latestProgress = {};
  Timer? _persistDebounce;
  bool _initialized = false;
  int _idCounter = 0;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  Stream<List<DownloadTask>> get taskStream => _tasksController.stream;
  Stream<DownloadProgress> get progressStream => _progressController.stream;
  DownloadProgress? progressOf(String taskId) => _latestProgress[taskId];
  DownloadManagerSettings get settings => _settings;

  /// Aggregate bandwidth across all running downloads.
  double get totalBytesPerSecond =>
      _latestProgress.values.fold(0, (sum, p) => sum + p.bytesPerSecond);

  int get queuedCount =>
      _tasks.where((t) => t.status == DownloadStatus.queued).length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final saved = await _repository.loadAll();
    for (final t in saved) {
      // Anything that was mid-flight when the app closed goes back in the
      // queue; the engine resumes from its sidecar.
      _tasks.add(
        t.status.isActive && t.status != DownloadStatus.verifying
            ? t.copyWith(status: DownloadStatus.queued)
            : t.status == DownloadStatus.verifying
            ? t.copyWith(
                status: DownloadStatus.completed,
                verification: VerificationState.pending,
              )
            : t,
      );
    }
    _notify();
    _pump();
    // Re-run interrupted verifications.
    for (final t in List.of(_tasks)) {
      if (t.status == DownloadStatus.completed &&
          t.verification == VerificationState.pending) {
        unawaited(_verify(t.id));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Queue operations
  // ---------------------------------------------------------------------------

  /// Queues one physical payload. If the same payload (by SHA1 / URL) is
  /// already queued or downloaded into the same folder, the existing task is
  /// returned with the device list merged instead of downloading it twice.
  DownloadTask enqueue(
    IpswGroup group, {
    required String targetDirectory,
    String? tempDirectory,
    int? threads,
  }) {
    final existing = _findDuplicate(group, targetDirectory);
    if (existing != null) {
      final merged = {
        ...existing.deviceIdentifiers,
        ...group.deviceIdentifiers,
      }.toList();
      final updated = existing.status == DownloadStatus.cancelled
          ? existing.copyWith(
              deviceIdentifiers: merged,
              status: DownloadStatus.queued,
              downloadedBytes: 0,
              errorMessage: () => null,
            )
          : existing.copyWith(deviceIdentifiers: merged);
      _replace(updated);
      _pump();
      return updated;
    }
    final task = DownloadTask.fromGroup(
      id: _newId(),
      group: group,
      targetDirectory: targetDirectory,
      tempDirectory: tempDirectory,
      threadCount: (threads ?? _settings.defaultThreads).clamp(1, 16),
    );
    _tasks.add(task);
    _notify();
    _pump();
    return task;
  }

  /// Bulk queue (e.g. "all signed files for iOS 18.0.1"). Groups are
  /// deduplicated first so shared payloads are fetched once.
  List<DownloadTask> enqueueAll(
    Iterable<IpswRelease> releases, {
    required String targetDirectory,
    String? tempDirectory,
  }) => [
    for (final g in IpswGroup.groupReleases(releases))
      enqueue(
        g,
        targetDirectory: targetDirectory,
        tempDirectory: tempDirectory,
      ),
  ];

  void pause(String id) {
    final run = _runs[id];
    if (run != null) {
      run.downloader?.pause();
      run.verifyJob?.cancel();
      return; // status updated when the run settles
    }
    final t = _byId(id);
    if (t != null && t.status == DownloadStatus.queued) {
      _replace(t.copyWith(status: DownloadStatus.paused));
    }
  }

  void resume(String id) {
    final t = _byId(id);
    if (t == null || _runs.containsKey(id)) return;
    if (t.status.isResumable || t.status == DownloadStatus.cancelled) {
      _replace(
        t.copyWith(status: DownloadStatus.queued, errorMessage: () => null),
      );
      _pump();
    } else if (t.status == DownloadStatus.completed &&
        t.verification == VerificationState.failed) {
      retry(id);
    }
  }

  /// Retries a failed task, discarding partial data if it failed integrity.
  Future<void> retry(String id) async {
    final t = _byId(id);
    if (t == null || _runs.containsKey(id)) return;
    if (t.verification == VerificationState.failed) {
      await _deleteFiles(t, includeTarget: true);
      _replace(
        t.copyWith(
          downloadedBytes: 0,
          verification: VerificationState.notRequested,
          completedAt: () => null,
        ),
      );
    }
    resume(id);
  }

  Future<void> cancel(String id, {bool remove = false}) async {
    final run = _runs[id];
    if (run != null) {
      run.removeOnSettle = remove;
      run.downloader?.cancel();
      run.verifyJob?.cancel();
      return;
    }
    final t = _byId(id);
    if (t == null) return;
    if (t.status != DownloadStatus.completed) await _deleteFiles(t);
    if (remove) {
      _tasks.removeWhere((x) => x.id == id);
      _notify();
    } else if (t.status != DownloadStatus.completed) {
      _replace(
        t.copyWith(status: DownloadStatus.cancelled, downloadedBytes: 0),
      );
    }
  }

  void moveUp(String id) => _moveBy(id, -1);
  void moveDown(String id) => _moveBy(id, 1);

  void moveTo(String id, int index) {
    final from = _tasks.indexWhere((t) => t.id == id);
    if (from < 0) return;
    final task = _tasks.removeAt(from);
    _tasks.insert(index.clamp(0, _tasks.length), task);
    _notify();
  }

  void setGlobalSpeedLimit(int bytesPerSecond) {
    _globalThrottler.rate = bytesPerSecond;
    _settings = DownloadManagerSettings(
      maxConcurrentDownloads: _settings.maxConcurrentDownloads,
      defaultThreads: _settings.defaultThreads,
      autoVerifySha1: _settings.autoVerifySha1,
      globalSpeedLimitBytesPerSecond: bytesPerSecond,
      engine: _settings.engine,
    );
  }

  void setTaskSpeedLimit(String id, int bytesPerSecond) {
    final t = _byId(id);
    if (t == null) return;
    _runs[id]?.taskThrottler.rate = bytesPerSecond;
    _replace(t.copyWith(speedLimitBytesPerSecond: bytesPerSecond));
  }

  void updateSettings(DownloadManagerSettings settings) {
    _settings = settings;
    _globalThrottler.rate = settings.globalSpeedLimitBytesPerSecond;
    _pump();
  }

  /// Manual "Refresh Link": re-resolves the URL now (e.g. for a failed task).
  Future<bool> refreshLink(String id) async {
    final t = _byId(id);
    if (t == null) return false;
    final fresh = await _linkResolver.resolveFreshUrl(t);
    if (fresh == null) return false;
    _replace(
      _byId(id)!.copyWith(url: fresh, linkRefreshCount: t.linkRefreshCount + 1),
    );
    if (!_runs.containsKey(id) && _byId(id)!.status == DownloadStatus.failed) {
      resume(id);
    }
    return true;
  }

  Future<void> dispose() async {
    for (final run in _runs.values) {
      run.downloader?.pause();
      run.verifyJob?.cancel();
    }
    await Future.wait(_runs.values.map((r) => r.settled.future));
    _persistDebounce?.cancel();
    await _repository.saveAll(_tasks);
    await _tasksController.close();
    await _progressController.close();
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _pump() {
    final downloading = _runs.values.where((r) => r.downloader != null).length;
    var slots = _settings.maxConcurrentDownloads - downloading;
    for (final t in List.of(_tasks)) {
      if (slots <= 0) break;
      if (t.status == DownloadStatus.queued && !_runs.containsKey(t.id)) {
        slots--;
        unawaited(_start(t.id));
      }
    }
  }

  Future<void> _start(String id) async {
    var task = _byId(id)!;
    final taskThrottler = BandwidthThrottler(
      bytesPerSecond: task.speedLimitBytesPerSecond,
    );
    final run = _ActiveRun(taskThrottler);
    _runs[id] = run;
    _replace(
      task.copyWith(
        status: DownloadStatus.connecting,
        errorMessage: () => null,
      ),
    );

    final e = _settings.engine;
    final downloader = ChunkedDownloader(
      taskId: id,
      url: task.url,
      partialPath: task.partialPath,
      targetPath: task.targetPath,
      throttlers: [_globalThrottler, taskThrottler],
      httpClientFactory: _httpClientFactory,
      config: ChunkedDownloaderConfig(
        threads: task.threadCount,
        minSplitBytes: e.minSplitBytes,
        writeBlockBytes: e.writeBlockBytes,
        maxRetriesPerChunk: e.maxRetriesPerChunk,
        maxLinkRefreshes: e.maxLinkRefreshes,
        connectTimeout: e.connectTimeout,
        readTimeout: e.readTimeout,
        checkpointInterval: e.checkpointInterval,
        progressInterval: e.progressInterval,
        userAgent: e.userAgent,
      ),
      onLinkExpired: () async {
        final current = _byId(id)!;
        _replace(current.copyWith(status: DownloadStatus.refreshingLink));
        final fresh = await _linkResolver.resolveFreshUrl(current);
        final after = _byId(id)!;
        _replace(
          after.copyWith(
            url: fresh,
            status: DownloadStatus.connecting,
            linkRefreshCount: after.linkRefreshCount + (fresh != null ? 1 : 0),
          ),
        );
        return fresh;
      },
    );
    run.downloader = downloader;

    final sub = downloader.progress.listen((p) {
      _latestProgress[id] = p;
      _progressController.add(p);
      final t = _byId(id);
      if (t == null) return;
      final status =
          t.status == DownloadStatus.connecting && p.downloadedBytes > 0
          ? DownloadStatus.downloading
          : t.status;
      if (status != t.status || t.totalBytes != p.totalBytes) {
        _replace(
          t.copyWith(
            status: status,
            totalBytes: p.totalBytes,
            downloadedBytes: p.downloadedBytes,
          ),
        );
      } else {
        // Hot path: update in place without a list notification storm.
        _replaceSilently(t.copyWith(downloadedBytes: p.downloadedBytes));
      }
    });

    DownloadOutcome? outcome;
    Object? error;
    try {
      outcome = await downloader.run();
    } catch (err) {
      error = err;
    } finally {
      await sub.cancel();
      _latestProgress.remove(id);
      run.downloader = null;
    }

    task = _byId(id) ?? task;
    if (error != null) {
      _replace(
        task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: () => switch (error) {
            DownloadException(:final message) => message,
            FileSystemException() => describeFolderError(
              error,
              task.targetDirectory,
            ),
            _ => '$error',
          },
        ),
      );
    } else {
      switch (outcome!) {
        case DownloadOutcome.paused:
          _replace(task.copyWith(status: DownloadStatus.paused));
        case DownloadOutcome.cancelled:
          _replace(
            task.copyWith(status: DownloadStatus.cancelled, downloadedBytes: 0),
          );
        case DownloadOutcome.completed:
          final needsVerify = _settings.autoVerifySha1 && task.sha1sum != null;
          _replace(
            task.copyWith(
              status: DownloadStatus.completed,
              downloadedBytes: task.totalBytes,
              completedAt: () => DateTime.now(),
              verification: task.sha1sum == null
                  ? VerificationState.unavailable
                  : needsVerify
                  ? VerificationState.pending
                  : VerificationState.notRequested,
            ),
          );
      }
    }

    // Free the download slot before hashing so the next file can start.
    _pump();
    if (outcome == DownloadOutcome.completed &&
        _byId(id)?.verification == VerificationState.pending) {
      await _verify(id, run: run);
    }

    _runs.remove(id);
    run.settled.complete();
    if (run.removeOnSettle) {
      _tasks.removeWhere((t) => t.id == id);
      _notify();
    }
    _pump();
  }

  Future<void> _verify(String id, {_ActiveRun? run}) async {
    final t = _byId(id);
    final expected = t?.sha1sum?.toLowerCase();
    if (t == null || expected == null) return;
    final ownRun = run == null;
    run ??= _runs[id] = _ActiveRun(BandwidthThrottler());
    _replace(
      t.copyWith(
        status: DownloadStatus.verifying,
        verification: VerificationState.verifying,
      ),
    );
    final job = Sha1Verifier.start(t.targetPath);
    run.verifyJob = job;
    try {
      final actual = await job.result;
      final ok = actual == expected;
      _replace(
        _byId(id)!.copyWith(
          status: ok ? DownloadStatus.completed : DownloadStatus.failed,
          verification: ok
              ? VerificationState.passed
              : VerificationState.failed,
          errorMessage: () => ok
              ? null
              : IntegrityException(expected: expected, actual: actual).message,
        ),
      );
    } catch (_) {
      // Cancelled (pause / app exit) or unreadable: leave it pending.
      final cur = _byId(id);
      if (cur != null) {
        _replace(
          cur.copyWith(
            status: DownloadStatus.completed,
            verification: VerificationState.pending,
          ),
        );
      }
    } finally {
      run.verifyJob = null;
      if (ownRun) {
        _runs.remove(id);
        run.settled.complete();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  DownloadTask? _findDuplicate(IpswGroup group, String targetDirectory) {
    for (final t in _tasks) {
      final sameFolder = t.targetDirectory == targetDirectory;
      final samePayload =
          (group.release.sha1sum != null &&
              t.sha1sum?.toLowerCase() ==
                  group.release.sha1sum!.toLowerCase()) ||
          t.url == group.release.url;
      if (sameFolder && samePayload) return t;
    }
    return null;
  }

  void _moveBy(String id, int delta) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    moveTo(id, math.max(0, i + delta));
  }

  DownloadTask? _byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _replace(DownloadTask task) {
    if (_replaceSilently(task)) _notify();
  }

  bool _replaceSilently(DownloadTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return false;
    _tasks[i] = task;
    _schedulePersist();
    return true;
  }

  void _notify() {
    if (!_tasksController.isClosed) _tasksController.add(tasks);
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(_repository.saveAll(_tasks).catchError((_) {}));
    });
  }

  Future<void> _deleteFiles(
    DownloadTask t, {
    bool includeTarget = false,
  }) async {
    for (final path in [
      t.partialPath,
      t.sidecarPath,
      '${t.sidecarPath}.tmp',
      if (includeTarget) t.targetPath,
    ]) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_idCounter++).toRadixString(36)}';
}

class _ActiveRun {
  _ActiveRun(this.taskThrottler);

  final BandwidthThrottler taskThrottler;
  final Completer<void> settled = Completer();
  ChunkedDownloader? downloader;
  Sha1Job? verifyJob;
  bool removeOnSettle = false;
}
