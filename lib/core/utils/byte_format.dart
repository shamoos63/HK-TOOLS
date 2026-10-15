/// Human-readable sizes and rates for telemetry readouts (binary units).
String formatBytes(num bytes, {int decimals = 2}) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : decimals)} ${units[unit]}';
}

String formatRate(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatEta(Duration? eta) {
  if (eta == null) return '--:--';
  final h = eta.inHours;
  final m = eta.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = eta.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
