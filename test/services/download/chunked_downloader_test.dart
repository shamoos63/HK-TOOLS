import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/download/bandwidth_throttler.dart';
import 'package:hk_ipsw_manager/services/download/chunked_downloader.dart';
import 'package:hk_ipsw_manager/services/download/download_exceptions.dart';
import 'package:path/path.dart' as p;

import 'fake_range_server.dart';

const _mib = 1024 * 1024;

void main() {
  late Directory dir;
  late FakeRangeServer server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hk_dl_test');
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  ChunkedDownloader downloader(
    String path, {
    int threads = 8,
    int minSplit = 256 * 1024,
    List<BandwidthThrottler> throttlers = const [],
    LinkRefresher? onLinkExpired,
  }) {
    final target = p.join(dir.path, 'out.ipsw');
    return ChunkedDownloader(
      taskId: 't1',
      url: server.url(path),
      partialPath: '$target.hkdl',
      targetPath: target,
      throttlers: throttlers,
      onLinkExpired: onLinkExpired,
      config: ChunkedDownloaderConfig(
        threads: threads,
        minSplitBytes: minSplit,
        writeBlockBytes: 128 * 1024,
        checkpointInterval: const Duration(milliseconds: 100),
        progressInterval: const Duration(milliseconds: 50),
      ),
    );
  }

  Future<void> expectPayloadMatches() async {
    final out = File(p.join(dir.path, 'out.ipsw'));
    expect(await out.exists(), isTrue);
    final got = await out.readAsBytes();
    expect(got.length, server.payload.length);
    expect(sha1.convert(got), sha1.convert(server.payload));
    expect(await File('${out.path}.hkdl').exists(), isFalse);
    expect(await File('${out.path}.hkdl.json').exists(), isFalse);
  }

  test('downloads with parallel ranges and assembles in place', () async {
    server = await FakeRangeServer.start(20 * _mib + 12345);
    final outcome = await downloader('a.ipsw').run();
    expect(outcome, DownloadOutcome.completed);
    await expectPayloadMatches();
    // probe + at least 8 range workers
    expect(server.ranges.length, greaterThanOrEqualTo(9));
  });

  test('idle threads steal the tail of a slow chunk', () async {
    server = await FakeRangeServer.start(8 * _mib)
      ..slowBelowOffset =
          2 *
          _mib // first chunk crawls
      ..slowDelay = const Duration(milliseconds: 30);
    final outcome = await downloader('a.ipsw', threads: 4).run();
    expect(outcome, DownloadOutcome.completed);
    await expectPayloadMatches();
    // 1 probe + 4 initial ranges, plus at least one split-off range.
    expect(server.ranges.length, greaterThan(5));
  });

  test(
    'pause checkpoints and a new instance resumes without refetching',
    () async {
      server = await FakeRangeServer.start(12 * _mib)
        ..writeDelay = const Duration(milliseconds: 5);
      final first = downloader('a.ipsw', threads: 4);
      final run = first.run();
      await first.progress.firstWhere((pr) => pr.downloadedBytes > 4 * _mib);
      first.pause();
      expect(await run, DownloadOutcome.paused);

      final out = p.join(dir.path, 'out.ipsw');
      expect(await File('$out.hkdl.json').exists(), isTrue);
      expect(await File('$out.hkdl').length(), server.payload.length);

      final rangesBefore = server.ranges.length;
      server.writeDelay = Duration.zero;
      expect(
        await downloader('a.ipsw', threads: 4).run(),
        DownloadOutcome.completed,
      );
      await expectPayloadMatches();
      // The resumed run only asks for what the first run didn't finish.
      final resumedBytes = server.requestedSince(rangesBefore);
      expect(resumedBytes, lessThan(server.payload.length * 0.8));
    },
  );

  test('cancel removes partial data', () async {
    server = await FakeRangeServer.start(8 * _mib)
      ..writeDelay = const Duration(milliseconds: 5);
    final d = downloader('a.ipsw');
    final run = d.run();
    await d.progress.firstWhere((pr) => pr.downloadedBytes > 0);
    d.cancel();
    expect(await run, DownloadOutcome.cancelled);
    expect(dir.listSync(), isEmpty);
  });

  test('expired link is refreshed and existing chunks are kept', () async {
    server = await FakeRangeServer.start(10 * _mib)
      ..writeDelay = const Duration(milliseconds: 5);
    final first = downloader('old.ipsw', threads: 4);
    final run = first.run();
    await first.progress.firstWhere((pr) => pr.downloadedBytes > 3 * _mib);
    first.pause();
    await run;

    // Hours later: the old token is dead.
    server
      ..expiredPaths.add('old.ipsw')
      ..writeDelay = Duration.zero;
    final rangesBefore = server.ranges.length;
    var refreshes = 0;
    final second = downloader(
      'old.ipsw',
      threads: 4,
      onLinkExpired: () async {
        refreshes++;
        return server.url('new.ipsw');
      },
    );
    expect(await second.run(), DownloadOutcome.completed);
    expect(refreshes, 1);
    expect(second.currentUrl, server.url('new.ipsw'));
    await expectPayloadMatches();
    expect(
      server.requestedSince(rangesBefore),
      lessThan(server.payload.length * 0.8),
    );
  });

  test(
    'expired link without a refresher fails with LinkExpiredException',
    () async {
      server = await FakeRangeServer.start(1 * _mib)
        ..expiredPaths.add('a.ipsw');
      await expectLater(
        downloader('a.ipsw').run(),
        throwsA(isA<LinkExpiredException>()),
      );
    },
  );

  test('falls back to a single stream when ranges are unsupported', () async {
    server = await FakeRangeServer.start(3 * _mib)
      ..supportsRanges = false;
    expect(await downloader('a.ipsw').run(), DownloadOutcome.completed);
    await expectPayloadMatches();
    expect(server.requestCount, 2); // probe + one full GET
  });

  test('bandwidth throttler caps aggregate throughput', () async {
    server = await FakeRangeServer.start(3 * _mib);
    final sw = Stopwatch()..start();
    final throttle = BandwidthThrottler(bytesPerSecond: 2 * _mib);
    expect(
      await downloader('a.ipsw', threads: 4, throttlers: [throttle]).run(),
      DownloadOutcome.completed,
    );
    sw.stop();
    await expectPayloadMatches();
    // 3 MiB at 2 MiB/s with a 250 ms burst allowance ≈ ≥1.25 s.
    expect(sw.elapsedMilliseconds, greaterThan(1100));
  });
}
