import '../../domain/entities/download_task.dart';
import '../../domain/repositories/link_resolver.dart';
import '../api/ipsw_api_client.dart';

/// Finds a fresh URL for a task by re-querying IPSW.me for each of the task's
/// devices and matching the same build (and SHA1, when known).
class IpswMeLinkResolver implements LinkResolver {
  IpswMeLinkResolver(this._api, {Duration Function()? timeout})
    : _timeout = timeout ?? (() => const Duration(seconds: 30));

  final IpswApiClient _api;

  /// Read on every call so Settings changes apply without a restart.
  final Duration Function() _timeout;

  @override
  Future<String?> resolveFreshUrl(DownloadTask task) async {
    final sha = task.sha1sum?.toLowerCase();
    final timeout = _timeout();
    for (final identifier in task.deviceIdentifiers) {
      try {
        final releases = await _api
            .fetchDeviceFirmwares(identifier)
            .timeout(timeout);
        for (final r in releases) {
          if (r.buildId != task.buildId) continue;
          if (sha != null &&
              r.sha1sum != null &&
              r.sha1sum!.toLowerCase() != sha) {
            continue;
          }
          if (r.url.isNotEmpty) return r.url;
        }
      } on Exception {
        continue; // try the next device that shares this payload
      }
    }
    return null;
  }
}
