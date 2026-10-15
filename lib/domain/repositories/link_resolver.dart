import '../entities/download_task.dart';

/// Re-queries the catalog for a fresh download URL when the current one has
/// expired (403/410 from the Apple CDN after a long pause).
abstract interface class LinkResolver {
  /// Returns a fresh URL for the same payload, or `null` if none is found.
  Future<String?> resolveFreshUrl(DownloadTask task);
}
