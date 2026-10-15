import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Local HTTP server that serves one payload with optional range support,
/// expiring URLs and slow regions — enough to exercise the download engine.
class FakeRangeServer {
  FakeRangeServer._(this._server, this.payload);

  final HttpServer _server;
  final Uint8List payload;

  bool supportsRanges = true;

  /// Paths that answer 403 (simulates an expired CDN token).
  final Set<String> expiredPaths = {};

  /// Delay between 64 KiB writes for ranges starting before this offset.
  int slowBelowOffset = -1;
  Duration slowDelay = const Duration(milliseconds: 40);

  /// Delay between every 64 KiB write (applies to all requests).
  Duration writeDelay = Duration.zero;

  int requestCount = 0;
  int bytesServed = 0;
  final List<String> ranges = [];

  static Future<FakeRangeServer> start(int size, {int seed = 42}) async {
    final rnd = Random(seed);
    final payload = Uint8List(size);
    for (var i = 0; i < size; i++) {
      payload[i] = rnd.nextInt(256);
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeRangeServer._(server, payload);
    server.listen(fake._handle);
    return fake;
  }

  /// Bytes requested by range requests made after the [from]-th one,
  /// excluding `bytes=0-0` probes. Unlike [bytesServed], this is unaffected by
  /// handlers of aborted connections that keep writing for a while.
  int requestedSince(int from) => ranges.skip(from).fold(0, (sum, r) {
    final [start, end] = r.split('-').map(int.parse).toList();
    return end == 0 ? sum : sum + end - start + 1;
  });

  String url(String path) => 'http://127.0.0.1:${_server.port}/$path';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    requestCount++;
    final res = req.response;
    try {
      if (expiredPaths.contains(req.uri.path.substring(1))) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      res.headers.set(HttpHeaders.etagHeader, '"payload-v1"');
      var start = 0;
      var end = payload.length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (supportsRanges && range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = min(int.parse(m.group(2)!), end);
        ranges.add('$start-$end');
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${payload.length}',
        );
        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }
      res.contentLength = end - start + 1;
      const block = 64 * 1024;
      final slow = slowBelowOffset >= 0 && start < slowBelowOffset;
      for (var pos = start; pos <= end; pos += block) {
        final stop = min(pos + block, end + 1);
        res.add(Uint8List.sublistView(payload, pos, stop));
        bytesServed += stop - pos;
        await res.flush();
        if (slow) await Future<void>.delayed(slowDelay);
        if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
      }
      await res.close();
    } catch (_) {
      // Client aborted the connection (pause / range satisfied).
    }
  }
}
