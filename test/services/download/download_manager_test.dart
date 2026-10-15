import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/domain/entities/download_task.dart';
import 'package:hk_ipsw_manager/domain/entities/ipsw_release.dart';
import 'package:hk_ipsw_manager/domain/repositories/download_task_repository.dart';
import 'package:hk_ipsw_manager/domain/repositories/link_resolver.dart';
import 'package:hk_ipsw_manager/services/download/download_manager.dart';

import 'fake_range_server.dart';

class _MemoryRepo implements DownloadTaskRepository {
  List<DownloadTask> saved = [];

  @override
  Future<List<DownloadTask>> loadAll() async => saved;

  @override
  Future<void> saveAll(List<DownloadTask> tasks) async =>
      saved = List.of(tasks);
}

class _NoResolver implements LinkResolver {
  @override
  Future<String?> resolveFreshUrl(DownloadTask task) async => null;
}

IpswRelease _release(
  FakeRangeServer server,
  String id,
  String path, {
  String? sha,
}) => IpswRelease(
  identifier: id,
  version: '18.0',
  buildId: '22A3354',
  url: server.url(path),
  fileSize: server.payload.length,
  signed: true,
  sha1sum: sha,
);

void main() {
  late Directory dir;
  late FakeRangeServer server;
  late DownloadManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hk_mgr_test');
    server = await FakeRangeServer.start(4 * 1024 * 1024);
    manager = DownloadManager(
      repository: _MemoryRepo(),
      linkResolver: _NoResolver(),
      settings: const DownloadManagerSettings(maxConcurrentDownloads: 1),
    );
    await manager.init();
  });

  tearDown(() async {
    await manager.dispose();
    await server.close();
    await dir.delete(recursive: true);
  });

  Future<DownloadTask> settled(
    String id,
    bool Function(DownloadTask) done,
  ) async {
    bool check(List<DownloadTask> ts) => ts.any((t) => t.id == id && done(t));
    if (!check(manager.tasks)) {
      await manager.taskStream
          .firstWhere(check)
          .timeout(const Duration(seconds: 20));
    }
    return manager.tasks.firstWhere((t) => t.id == id);
  }

  test('shared payload is deduplicated and verified once', () async {
    final sha = sha1.convert(server.payload).toString();
    // iPhone 12 and 12 Pro share one IPSW.
    final tasks = manager.enqueueAll([
      _release(server, 'iPhone13,2', 'iPhone_6.1_18.0_Restore.ipsw', sha: sha),
      _release(server, 'iPhone13,3', 'iPhone_6.1_18.0_Restore.ipsw', sha: sha),
    ], targetDirectory: dir.path);
    expect(tasks, hasLength(1));
    expect(tasks.single.deviceIdentifiers, ['iPhone13,2', 'iPhone13,3']);

    final done = await settled(
      tasks.single.id,
      (t) => t.verification == VerificationState.passed,
    );
    expect(done.status, DownloadStatus.completed);
    expect(await File(done.targetPath).length(), server.payload.length);

    // Re-queuing the same payload returns the existing task.
    final again = manager.enqueue(
      IpswGroup(
        _release(
          server,
          'iPhone13,2',
          'iPhone_6.1_18.0_Restore.ipsw',
          sha: sha,
        ),
        ['iPhone13,2'],
      ),
      targetDirectory: dir.path,
    );
    expect(again.id, done.id);
    expect(manager.tasks, hasLength(1));
  });

  test('SHA1 mismatch marks the task failed', () async {
    final task = manager.enqueue(
      IpswGroup(_release(server, 'iPad14,1', 'bad.ipsw', sha: 'deadbeef' * 5), [
        'iPad14,1',
      ]),
      targetDirectory: dir.path,
    );
    final done = await settled(
      task.id,
      (t) => t.verification == VerificationState.failed,
    );
    expect(done.status, DownloadStatus.failed);
    expect(done.errorMessage, contains('SHA1 mismatch'));
  });

  test('concurrency limit holds extra tasks in queue order', () async {
    server.writeDelay = const Duration(milliseconds: 5);
    final a = manager.enqueue(
      IpswGroup(_release(server, 'iPhone15,2', 'a.ipsw'), ['iPhone15,2']),
      targetDirectory: dir.path,
    );
    final b = manager.enqueue(
      IpswGroup(_release(server, 'iPhone15,3', 'b.ipsw'), ['iPhone15,3']),
      targetDirectory: dir.path,
    );
    final c = manager.enqueue(
      IpswGroup(_release(server, 'iPhone16,1', 'c.ipsw'), ['iPhone16,1']),
      targetDirectory: dir.path,
    );
    expect(manager.tasks.map((t) => t.status), [
      DownloadStatus.connecting,
      DownloadStatus.queued,
      DownloadStatus.queued,
    ]);
    manager.moveUp(c.id); // c now ahead of b
    expect(manager.tasks.map((t) => t.id), [a.id, c.id, b.id]);

    await settled(a.id, (t) => t.status == DownloadStatus.completed);
    final next = await settled(c.id, (t) => t.status != DownloadStatus.queued);
    expect(next.status, isNot(DownloadStatus.queued));
    expect(
      manager.tasks.firstWhere((t) => t.id == b.id).status,
      DownloadStatus.queued,
    );

    manager.pause(c.id);
    final paused = await settled(
      c.id,
      (t) => t.status == DownloadStatus.paused,
    );
    expect(paused.status, DownloadStatus.paused);
  });
}
