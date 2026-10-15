import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'bandwidth_throttler.dart';
import 'download_exceptions.dart';
import 'download_progress.dart';
import 'positional_file_writer.dart';
import 'speed_meter.dart';

enum DownloadOutcome { completed, paused, cancelled }

class ChunkedDownloaderConfig {
  const ChunkedDownloaderConfig({
    this.threads = 8,
    this.minSplitBytes = 4 * 1024 * 1024,
    this.writeBlockBytes = 1024 * 1024,
    this.maxRetriesPerChunk = 6,
    this.maxLinkRefreshes = 3,
    this.connectTimeout = const Duration(seconds: 20),
    this.readTimeout = const Duration(seconds: 30),
    this.checkpointInterval = const Duration(seconds: 3),
    this.progressInterval = const Duration(milliseconds: 250),
    this.userAgent = 'HK-IPSW-Manager/0.1',
  }) : assert(threads >= 1 && threads <= 32);

  /// Parallel HTTP range connections (UI exposes 2–16).
  final int threads;

  /// A running chunk is only split for an idle thread if each half would be at
  /// least this big.
  final int minSplitBytes;

  /// Bytes buffered per thread before a positional write.
  final int writeBlockBytes;
  final int maxRetriesPerChunk;
  final int maxLinkRefreshes;
  final Duration connectTimeout;

  /// Max silence on a connection before it is considered stalled.
  final Duration readTimeout;
  final Duration checkpointInterval;
  final Duration progressInterval;
  final String userAgent;
}

/// Returns a fresh URL for the same payload, or `null` if none is available.
typedef LinkRefresher = Future<String?> Function();

/// Multi-connection HTTP range downloader for a single file.
///
/// * Probes the server with `Range: bytes=0-0` for size / range support.
/// * Pre-allocates the partial file at full size and has every thread write
///   straight to its offset, so no assembly pass is needed at the end.
/// * When a thread finishes early it steals the back half of the largest
///   remaining chunk (dynamic segmentation, as in AB Download Manager / IDM),
///   so slow connections never leave the tail of a file single-threaded.
/// * Persists the chunk map to a JSON sidecar every few seconds; [run] on a
///   new instance resumes from it.
/// * On 401/403/410 it asks [onLinkExpired] for a fresh URL and resumes the
///   existing chunks if the remote size / ETag still match.
///
/// One instance performs one run; create a new instance to resume.
class ChunkedDownloader {
  ChunkedDownloader({
    required this.taskId,
    required this._url,
    required this.partialPath,
    required this.targetPath,
    this.config = const ChunkedDownloaderConfig(),
    this._throttlers = const [],
    this.onLinkExpired,
    HttpClient Function()? httpClientFactory,
  }) : _clientFactory = httpClientFactory ?? HttpClient.new;

  final String taskId;
  final String partialPath;
  final String targetPath;
  final ChunkedDownloaderConfig config;
  final LinkRefresher? onLinkExpired;

  final List<BandwidthThrottler> _throttlers;
  final HttpClient Function() _clientFactory;
  final _progress = StreamController<DownloadProgress>.broadcast();
  final _meter = SpeedMeter();

  String _url;
  HttpClient? _client;
  PositionalFileWriter? _writer;
  List<_Chunk>? _chunks;
  int _total = 0;
  bool _rangeSupported = true;
  String? _etag;
  String? _lastModified;

  bool _started = false;
  bool _haltWorkers = false;
  DownloadOutcome? _stopRequest;
  int _linkRefreshes = 0;
  Future<void>? _checkpointInFlight;
  Timer? _progressTimer;
  Timer? _checkpointTimer;

  String get sidecarPath => '$partialPath.json';
  String get currentUrl => _url;
  int get linkRefreshes => _linkRefreshes;
  Stream<DownloadProgress> get progress => _progress.stream;

  /// Downloads (or resumes) the file. Completes with [DownloadOutcome.paused]
  /// or [DownloadOutcome.cancelled] if [pause] / [cancel] were called, and
  /// throws a [DownloadException] on unrecoverable failure (progress is
  /// checkpointed first so a retry resumes).
  Future<DownloadOutcome> run() async {
    if (_started) {
      throw StateError('ChunkedDownloader.run() may only be called once');
    }
    _started = true;
    _progressTimer = Timer.periodic(
      config.progressInterval,
      (_) => _emitProgress(),
    );
    _checkpointTimer = Timer.periodic(
      config.checkpointInterval,
      (_) => _checkpoint(),
    );
    try {
      while (true) {
        try {
          _ensureClient();
          await _connect();
          if (_stopRequest != null) break;
          await _runWorkers();
          break;
        } on LinkExpiredException {
          if (_stopRequest != null) break;
          if (!await _refreshLink()) rethrow;
        }
      }
      return await _settle();
    } catch (e) {
      if (_stopRequest != null) return await _settle();
      await _checkpoint(force: true);
      if (e is DownloadException) rethrow;
      throw DownloadException('Download failed', cause: e);
    } finally {
      _progressTimer?.cancel();
      _checkpointTimer?.cancel();
      _client?.close(force: true);
      await _writer?.close();
      _emitProgress();
      await _progress.close();
    }
  }

  /// Stops all threads and keeps the partial file for a later resume.
  void pause() => _stop(DownloadOutcome.paused);

  /// Stops all threads and deletes the partial file and sidecar.
  void cancel() => _stop(DownloadOutcome.cancelled);

  void _stop(DownloadOutcome reason) {
    // A cancel may upgrade a pending pause, never the reverse.
    if (_stopRequest == null || reason == DownloadOutcome.cancelled) {
      _stopRequest = reason;
    }
    _abortConnections();
  }

  void _abortConnections() {
    _haltWorkers = true;
    _client?.close(force: true);
    _client = null;
  }

  void _ensureClient() {
    _client ??= _clientFactory()
      ..autoUncompress = false
      ..connectionTimeout = config.connectTimeout
      ..maxConnectionsPerHost = config.threads + 1
      ..userAgent = config.userAgent;
  }

  // ---------------------------------------------------------------------------
  // Probe & plan
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    final info = await _probe();
    if (_chunks == null) {
      final saved = await _loadSidecar();
      if (saved != null && saved.isCompatibleWith(info)) {
        _chunks = saved.chunks;
        if (!info.rangeSupported) {
          _resetChunks(info.total, rangeSupported: false);
        }
      } else {
        await _deletePartial();
        _resetChunks(info.total, rangeSupported: info.rangeSupported);
      }
    } else if (info.total != _total ||
        (info.etag != null && _etag != null && info.etag != _etag)) {
      // The refreshed link points at different bytes; existing chunks are void.
      await _writer?.close();
      _writer = null;
      await _deletePartial();
      _resetChunks(info.total, rangeSupported: info.rangeSupported);
    } else if (!info.rangeSupported) {
      _resetChunks(info.total, rangeSupported: false);
    }
    _total = info.total;
    _rangeSupported = info.rangeSupported;
    _etag = info.etag;
    _lastModified = info.lastModified;
    _writer ??= await PositionalFileWriter.open(partialPath, _total);
  }

  Future<_ProbeResult> _probe() async {
    final request = await _client!.getUrl(Uri.parse(_url));
    _prepareRequest(request).set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close().timeout(config.readTimeout);
    try {
      _throwIfLinkExpired(response.statusCode);
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final lastModified = response.headers.value(
        HttpHeaders.lastModifiedHeader,
      );
      if (response.statusCode == HttpStatus.partialContent) {
        final total = _parseContentRangeTotal(
          response.headers.value(HttpHeaders.contentRangeHeader),
        );
        if (total == null || total <= 0) {
          throw DownloadException('Server did not report the file size');
        }
        return _ProbeResult(total, true, etag, lastModified);
      }
      if (response.statusCode == HttpStatus.ok) {
        if (response.contentLength <= 0) {
          throw DownloadException('Server did not report the file size');
        }
        return _ProbeResult(response.contentLength, false, etag, lastModified);
      }
      throw DownloadException(
        'Unexpected HTTP ${response.statusCode} from server',
      );
    } finally {
      await _discard(response);
    }
  }

  void _resetChunks(int total, {required bool rangeSupported}) {
    final threads = rangeSupported
        ? math.max(1, math.min(config.threads, total ~/ config.minSplitBytes))
        : 1;
    final size = (total / threads).ceil();
    _chunks = [
      for (var start = 0; start < total; start += size)
        _Chunk(start, math.min(start + size, total) - 1),
    ];
  }

  // ---------------------------------------------------------------------------
  // Workers
  // ---------------------------------------------------------------------------

  Future<void> _runWorkers() {
    _haltWorkers = false;
    final done = Completer<void>();
    Object? firstError;
    StackTrace? firstStack;
    var active = 0;

    void pump() {
      if (done.isCompleted) return;
      if (!_haltWorkers) {
        while (active < config.threads) {
          final chunk = _nextIdleChunk() ?? _splitLargestChunk();
          if (chunk == null) break;
          active++;
          chunk.active = true;
          _runChunk(chunk)
              .catchError((Object e, StackTrace s) {
                if (firstError == null && !_haltWorkers) {
                  firstError = e;
                  firstStack = s;
                  _abortConnections();
                }
              })
              .whenComplete(() {
                chunk.active = false;
                active--;
                pump();
              });
        }
      }
      if (active == 0) {
        final error = firstError;
        if (error != null) {
          done.completeError(error, firstStack);
        } else if (_stopRequest == null && _chunks!.any((c) => !c.isDone)) {
          done.completeError(
            DownloadException('Workers stopped before completion'),
          );
        } else {
          done.complete();
        }
      }
    }

    pump();
    return done.future;
  }

  _Chunk? _nextIdleChunk() {
    for (final c in _chunks!) {
      if (!c.active && !c.isDone) return c;
    }
    return null;
  }

  /// Gives an idle thread the back half of the running chunk with the most
  /// bytes left.
  _Chunk? _splitLargestChunk() {
    if (!_rangeSupported) return null;
    final chunks = _chunks!;
    var bestIndex = -1;
    var bestRemaining = 0;
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      if (c.active && c.remainingAfterCursor > bestRemaining) {
        bestIndex = i;
        bestRemaining = c.remainingAfterCursor;
      }
    }
    if (bestIndex < 0 || bestRemaining < 2 * config.minSplitBytes) return null;
    final victim = chunks[bestIndex];
    final splitAt = victim.cursor + bestRemaining ~/ 2;
    final stolen = _Chunk(splitAt, victim.end);
    victim.end = splitAt - 1;
    chunks.insert(bestIndex + 1, stolen);
    return stolen;
  }

  Future<void> _runChunk(_Chunk chunk) async {
    var attempt = 0;
    while (!chunk.isDone && !_haltWorkers) {
      final before = chunk.flushed;
      try {
        await _streamRange(chunk);
        if (!chunk.isDone && !_haltWorkers) {
          throw DownloadException('Connection closed before chunk completed');
        }
      } on LinkExpiredException {
        rethrow;
      } on RemoteFileChangedException {
        rethrow;
      } catch (e) {
        if (_haltWorkers) return;
        if (chunk.flushed > before) attempt = 0;
        attempt++;
        if (attempt > config.maxRetriesPerChunk) {
          throw DownloadException(
            'Range ${chunk.start}-${chunk.end} failed after '
            '${config.maxRetriesPerChunk} retries',
            cause: e,
          );
        }
        await Future<void>.delayed(
          Duration(milliseconds: math.min(30000, 500 * (1 << (attempt - 1)))),
        );
      }
    }
  }

  Future<void> _streamRange(_Chunk chunk) async {
    final client = _client;
    if (client == null) return;
    final from = chunk.position;
    final request = await client.getUrl(Uri.parse(_url));
    final headers = _prepareRequest(request);
    if (_rangeSupported) {
      headers.set(HttpHeaders.rangeHeader, 'bytes=$from-${chunk.end}');
      // If the object changed, the server answers 200 instead of 206.
      final validator = _etag ?? _lastModified;
      if (validator != null) headers.set(HttpHeaders.ifRangeHeader, validator);
    }
    final response = await request.close().timeout(config.readTimeout);
    _throwIfLinkExpired(response.statusCode);

    final status = response.statusCode;
    final wholeFile =
        status == HttpStatus.ok && from == 0 && chunk.end == _total - 1;
    if (_rangeSupported && status != HttpStatus.partialContent && !wholeFile) {
      await _discard(response);
      throw status == HttpStatus.ok
          ? RemoteFileChangedException(
              'Server ignored range request (file changed?)',
            )
          : DownloadException('Unexpected HTTP $status for range request');
    }
    if (!_rangeSupported && status != HttpStatus.ok) {
      await _discard(response);
      throw DownloadException('Unexpected HTTP $status');
    }

    final buffer = BytesBuilder(copy: false);
    try {
      await for (final data in response.timeout(config.readTimeout)) {
        if (_haltWorkers) break;
        final room = chunk.end - chunk.cursor + 1;
        if (room <= 0) break;
        final bytes = data.length > room ? data.sublist(0, room) : data;
        await _throttlers.acquireAll(bytes.length);
        buffer.add(bytes);
        chunk.buffered += bytes.length;
        chunk.meter.add(bytes.length);
        _meter.add(bytes.length);
        if (buffer.length >= config.writeBlockBytes) {
          await _flushChunk(chunk, buffer);
        }
        if (chunk.cursor > chunk.end) break;
      }
    } finally {
      // Bytes already received are valid even if the connection was aborted.
      await _flushChunk(chunk, buffer);
    }
  }

  Future<void> _flushChunk(_Chunk chunk, BytesBuilder buffer) async {
    if (buffer.isEmpty) return;
    var bytes = buffer.takeBytes();
    final room = chunk.end - chunk.position + 1;
    if (bytes.length > room) {
      bytes = Uint8List.sublistView(bytes, 0, math.max(0, room));
    }
    try {
      if (bytes.isNotEmpty) await _writer!.write(chunk.position, bytes);
      chunk.flushed += bytes.length;
    } finally {
      chunk.buffered = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Link refresh, completion, persistence
  // ---------------------------------------------------------------------------

  Future<bool> _refreshLink() async {
    final refresher = onLinkExpired;
    if (refresher == null || _linkRefreshes >= config.maxLinkRefreshes) {
      return false;
    }
    _linkRefreshes++;
    await _checkpoint(force: true);
    final fresh = await refresher();
    if (fresh == null || fresh.isEmpty) return false;
    _url = fresh;
    return true;
  }

  Future<DownloadOutcome> _settle() async {
    // No periodic checkpoint may land after the sidecar is deleted / final.
    _checkpointTimer?.cancel();
    final inFlight = _checkpointInFlight;
    if (inFlight != null) await inFlight;
    switch (_stopRequest) {
      case DownloadOutcome.cancelled:
        await _writer?.close();
        _writer = null;
        await _deletePartial();
        return DownloadOutcome.cancelled;
      case DownloadOutcome.paused:
        await _checkpoint(force: true);
        return DownloadOutcome.paused;
      case DownloadOutcome.completed:
      case null:
        await _finalize();
        return DownloadOutcome.completed;
    }
  }

  Future<void> _finalize() async {
    final writer = _writer!;
    await writer.flush();
    await writer.close();
    _writer = null;
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete();
    final partial = File(partialPath);
    if (partialPath != targetPath) {
      try {
        await partial.rename(targetPath);
      } on FileSystemException {
        // Temp folder on another volume: rename cannot cross devices.
        await partial.copy(targetPath);
        await partial.delete();
      }
    }
    await _deleteIfExists(sidecarPath);
    _emitProgress();
  }

  /// Writes the resume sidecar. Checkpoints never overlap: two writers on the
  /// same `.tmp` file could publish a truncated sidecar and void the resume.
  /// Periodic calls skip while one is running; forced calls wait their turn.
  Future<void> _checkpoint({bool force = false}) async {
    if (_checkpointInFlight != null && !force) return;
    for (
      var running = _checkpointInFlight;
      running != null;
      running = _checkpointInFlight
    ) {
      await running;
    }
    final write = _writeCheckpoint();
    _checkpointInFlight = write;
    try {
      await write;
    } finally {
      if (identical(_checkpointInFlight, write)) _checkpointInFlight = null;
    }
  }

  Future<void> _writeCheckpoint() async {
    final chunks = _chunks;
    final writer = _writer;
    if (chunks == null || writer == null || _total <= 0) return;
    try {
      await writer.flush();
      final json = jsonEncode({
        'version': 1,
        'url': _url,
        'totalBytes': _total,
        'rangeSupported': _rangeSupported,
        'etag': _etag,
        'lastModified': _lastModified,
        'chunks': [
          for (final c in chunks) [c.start, c.end, c.flushed],
        ],
      });
      final tmp = File('$sidecarPath.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(sidecarPath);
    } catch (_) {
      // Checkpoints are best-effort; the next one will retry.
    }
  }

  Future<_Sidecar?> _loadSidecar() async {
    try {
      final sidecar = File(sidecarPath);
      if (!await sidecar.exists() || !await File(partialPath).exists()) {
        return null;
      }
      final json =
          jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
      final total = (json['totalBytes'] as num).toInt();
      if (await File(partialPath).length() != total) return null;
      final chunks = [
        for (final raw in json['chunks'] as List)
          _Chunk((raw[0] as num).toInt(), (raw[1] as num).toInt())
            ..flushed = (raw[2] as num).toInt(),
      ];
      return _Sidecar(total, json['etag'] as String?, chunks);
    } catch (_) {
      return null; // Corrupt metadata: start over rather than risk bad bytes.
    }
  }

  Future<void> _deletePartial() async {
    await _deleteIfExists(partialPath);
    await _deleteIfExists(sidecarPath);
    await _deleteIfExists('$sidecarPath.tmp');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _emitProgress() {
    if (_progress.isClosed) return;
    final chunks = _chunks ?? const <_Chunk>[];
    var downloaded = 0;
    final telemetry = <ChunkTelemetry>[];
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      final got = math.min(c.flushed + c.buffered, c.end - c.start + 1);
      downloaded += got;
      telemetry.add(
        ChunkTelemetry(
          index: i,
          start: c.start,
          end: c.end,
          downloaded: got,
          bytesPerSecond: c.active ? c.meter.bytesPerSecond : 0,
          active: c.active,
        ),
      );
    }
    _progress.add(
      DownloadProgress(
        taskId: taskId,
        totalBytes: _total,
        downloadedBytes: downloaded,
        bytesPerSecond: _haltWorkers ? 0 : _meter.bytesPerSecond,
        chunks: telemetry,
      ),
    );
  }

  HttpHeaders _prepareRequest(HttpClientRequest request) {
    request.followRedirects = true;
    request.maxRedirects = 8;
    return request.headers
      ..set(HttpHeaders.acceptEncodingHeader, 'identity')
      ..set(HttpHeaders.acceptHeader, '*/*');
  }

  static void _throwIfLinkExpired(int status) {
    if (status == HttpStatus.unauthorized ||
        status == HttpStatus.forbidden ||
        status == HttpStatus.gone) {
      throw LinkExpiredException(status);
    }
  }

  /// Releases a response without reading a potentially huge body.
  static Future<void> _discard(HttpClientResponse response) async {
    try {
      if (response.contentLength >= 0 && response.contentLength <= 64 * 1024) {
        await response.drain<void>();
      } else {
        (await response.detachSocket()).destroy();
      }
    } catch (_) {}
  }

  static int? _parseContentRangeTotal(String? header) {
    // e.g. "bytes 0-0/13841244160"
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(header.substring(slash + 1).trim());
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

class _Chunk {
  _Chunk(this.start, this.end);

  final int start;

  /// Inclusive; shrinks when an idle thread steals the tail.
  int end;

  /// Bytes written to disk from [start].
  int flushed = 0;

  /// Bytes received but not yet written.
  int buffered = 0;
  bool active = false;
  final SpeedMeter meter = SpeedMeter();

  int get position => start + flushed;
  int get cursor => start + flushed + buffered;
  int get remainingAfterCursor => end - cursor + 1;
  bool get isDone => position > end;
}

class _ProbeResult {
  _ProbeResult(this.total, this.rangeSupported, this.etag, this.lastModified);

  final int total;
  final bool rangeSupported;
  final String? etag;
  final String? lastModified;
}

class _Sidecar {
  _Sidecar(this.total, this.etag, this.chunks);

  final int total;
  final String? etag;
  final List<_Chunk> chunks;

  bool isCompatibleWith(_ProbeResult probe) =>
      probe.total == total &&
      (etag == null || probe.etag == null || etag == probe.etag);
}
