import 'dart:convert';
import 'dart:io';

import '../../domain/entities/download_task.dart';
import '../../domain/repositories/download_task_repository.dart';

/// Stores the queue as one JSON file with atomic replace-on-write.
///
/// The queue is small (tens to hundreds of rows) and chunk maps live in
/// per-file sidecars, so a document file is sufficient here; the catalog cache
/// and scan index (thousands of rows, queried) are where Hive/Isar earn their
/// keep.
class JsonDownloadTaskRepository implements DownloadTaskRepository {
  JsonDownloadTaskRepository(this.filePath);

  final String filePath;
  Future<void> _writeChain = Future.value();

  @override
  Future<List<DownloadTask>> loadAll() async {
    final file = File(filePath);
    if (!await file.exists()) return [];
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return [
        for (final t in json['tasks'] as List)
          DownloadTask.fromJson(t as Map<String, dynamic>),
      ];
    } on FormatException {
      await file.rename(
        '$filePath.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
      return [];
    }
  }

  @override
  Future<void> saveAll(List<DownloadTask> tasks) {
    final payload = jsonEncode({
      'version': 1,
      'tasks': [for (final t in tasks) t.toJson()],
    });
    // Serialize writes so an older snapshot never lands after a newer one.
    return _writeChain = _writeChain
        .then((_) async {
          final file = File(filePath);
          await file.parent.create(recursive: true);
          final tmp = File('$filePath.tmp');
          await tmp.writeAsString(payload, flush: true);
          await tmp.rename(filePath);
        })
        .catchError((_) {});
  }
}
