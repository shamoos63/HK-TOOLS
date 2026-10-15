import 'dart:collection';

/// Sliding-window throughput meter.
class SpeedMeter {
  SpeedMeter({this.window = const Duration(seconds: 3)});

  final Duration window;
  final Stopwatch _clock = Stopwatch()..start();
  final Queue<(int, int)> _samples = Queue(); // (micros, bytes)
  int _windowBytes = 0;

  void add(int bytes) {
    _samples.add((_clock.elapsedMicroseconds, bytes));
    _windowBytes += bytes;
    _evict();
  }

  double get bytesPerSecond {
    _evict();
    if (_samples.isEmpty) return 0;
    // Before the window fills, divide by elapsed time so the first seconds of
    // a download don't under-report.
    final span = _clock.elapsedMicroseconds < window.inMicroseconds
        ? _clock.elapsedMicroseconds
        : window.inMicroseconds;
    return span <= 0 ? 0 : _windowBytes * 1e6 / span;
  }

  void _evict() {
    final cutoff = _clock.elapsedMicroseconds - window.inMicroseconds;
    while (_samples.isNotEmpty && _samples.first.$1 < cutoff) {
      _windowBytes -= _samples.removeFirst().$2;
    }
  }
}
