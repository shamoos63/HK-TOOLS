/// Telemetry for one HTTP range worker ("thread").
class ChunkTelemetry {
  const ChunkTelemetry({
    required this.index,
    required this.start,
    required this.end,
    required this.downloaded,
    required this.bytesPerSecond,
    required this.active,
  });

  final int index;
  final int start;

  /// Inclusive end offset.
  final int end;
  final int downloaded;
  final double bytesPerSecond;
  final bool active;

  int get length => end - start + 1;
  double get fraction => length > 0 ? downloaded / length : 1;
}

/// Periodic snapshot emitted by a running download (~4 Hz).
class DownloadProgress {
  const DownloadProgress({
    required this.taskId,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.bytesPerSecond,
    required this.chunks,
  });

  final String taskId;
  final int totalBytes;
  final int downloadedBytes;
  final double bytesPerSecond;
  final List<ChunkTelemetry> chunks;

  double get fraction =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0;

  Duration? get eta {
    if (bytesPerSecond < 1 || totalBytes <= 0) return null;
    return Duration(
      seconds: ((totalBytes - downloadedBytes) / bytesPerSecond).ceil(),
    );
  }

  int get activeThreads => chunks.where((c) => c.active).length;
}
