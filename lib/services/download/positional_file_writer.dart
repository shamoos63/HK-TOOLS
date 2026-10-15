import 'dart:io';

/// Writes byte blocks at arbitrary offsets of a single pre-allocated file.
///
/// Dart's [RandomAccessFile] forbids overlapping async operations, so all
/// workers funnel through one handle and writes are serialized on a future
/// chain. Workers hand over ~1 MiB blocks, so the serialization is never the
/// bottleneck relative to network throughput.
class PositionalFileWriter {
  PositionalFileWriter._(this._raf);

  final RandomAccessFile _raf;
  Future<void> _tail = Future.value();
  bool _closed = false;

  /// Opens [path] for writing without truncating it and makes sure it is
  /// exactly [length] bytes.
  ///
  /// Extending with `truncate` reserves the full size up front: on NTFS this
  /// calls `SetEndOfFile`, which lets the allocator pick large contiguous
  /// extents (less fragmentation than growing a file chunk by chunk, and
  /// unlike a sparse file it fails fast when the volume is full). On APFS the
  /// file is sparse until written.
  static Future<PositionalFileWriter> open(String path, int length) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    // FileMode.append opens read/write without truncation; positions are set
    // explicitly for every write.
    final raf = await file.open(mode: FileMode.append);
    if (await raf.length() != length) {
      await raf.truncate(length);
    }
    return PositionalFileWriter._(raf);
  }

  Future<void> write(int position, List<int> bytes) => _enqueue(() async {
    await _raf.setPosition(position);
    await _raf.writeFrom(bytes);
  });

  /// Flushes OS buffers to disk (call before persisting resume metadata).
  Future<void> flush() => _enqueue(() => _raf.flush());

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _raf.close();
  }

  Future<void> _enqueue(Future<void> Function() op) {
    if (_closed) return Future.error(StateError('writer is closed'));
    final next = _tail.then((_) => op());
    // Keep the chain alive after a failure; the caller still sees the error.
    _tail = next.catchError((_) {});
    return next;
  }
}
