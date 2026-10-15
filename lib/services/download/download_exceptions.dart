/// Base class for errors raised by the download engine.
class DownloadException implements Exception {
  DownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DownloadException: $message'
      : 'DownloadException: $message ($cause)';
}

/// The server rejected the URL (401/403/410) — typically an expired Apple CDN
/// token. Recoverable via the link refresh engine.
class LinkExpiredException extends DownloadException {
  LinkExpiredException(this.statusCode)
    : super('Download link rejected with HTTP $statusCode');

  final int statusCode;
}

/// The remote file changed (size / ETag mismatch) so existing chunks are void.
class RemoteFileChangedException extends DownloadException {
  RemoteFileChangedException(super.message);
}

/// Post-download SHA1 did not match the published hash.
class IntegrityException extends DownloadException {
  IntegrityException({required this.expected, required this.actual})
    : super('SHA1 mismatch: expected $expected, got $actual');

  final String expected;
  final String actual;
}
