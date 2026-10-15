import 'dart:math' as math;

/// Shared token-bucket style limiter (GCRA / virtual scheduling).
///
/// Every worker calls [acquire] with the number of bytes it just read; the
/// call delays just long enough to keep the aggregate rate under [rate].
/// Delaying reads makes TCP flow control slow the sender down, so this caps
/// real network usage, not just disk writes. One instance can be shared by all
/// threads of all downloads (global cap) and chained with a per-task instance.
class BandwidthThrottler {
  BandwidthThrottler({
    int bytesPerSecond = 0,
    this.burst = const Duration(milliseconds: 250),
  }) : _rate = bytesPerSecond;

  /// How far ahead of schedule callers may run before being delayed.
  final Duration burst;
  final Stopwatch _clock = Stopwatch()..start();
  int _rate;
  double _theoreticalArrivalMicros = 0;

  /// Bytes per second; `0` disables throttling.
  int get rate => _rate;
  set rate(int bytesPerSecond) {
    _rate = math.max(0, bytesPerSecond);
    _theoreticalArrivalMicros = _clock.elapsedMicroseconds.toDouble();
  }

  bool get isUnlimited => _rate <= 0;

  Future<void> acquire(int bytes) {
    if (_rate <= 0 || bytes <= 0) return Future.value();
    final now = _clock.elapsedMicroseconds.toDouble();
    final start = math.max(now, _theoreticalArrivalMicros);
    _theoreticalArrivalMicros = start + bytes * 1e6 / _rate;
    final waitMicros = _theoreticalArrivalMicros - now - burst.inMicroseconds;
    if (waitMicros <= 0) return Future.value();
    return Future.delayed(Duration(microseconds: waitMicros.round()));
  }
}

/// Applies several throttlers in sequence (e.g. global + per-task).
extension ThrottlerChain on List<BandwidthThrottler> {
  Future<void> acquireAll(int bytes) async {
    for (final t in this) {
      if (!t.isUnlimited) await t.acquire(bytes);
    }
  }
}
