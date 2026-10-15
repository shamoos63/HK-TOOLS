import '../entities/download_task.dart';

/// Persists the download queue (order is significant: it is the queue order).
abstract interface class DownloadTaskRepository {
  Future<List<DownloadTask>> loadAll();
  Future<void> saveAll(List<DownloadTask> tasks);
}
