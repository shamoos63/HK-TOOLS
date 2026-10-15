import 'dart:async';
import 'dart:io';

import '../../domain/entities/ios_device.dart';
import '../device/device_parsers.dart';
import '../device/device_toolchain.dart';

/// What to flash and how.
class RestoreRequest {
  const RestoreRequest({
    required this.ipswPath,
    required this.device,
    required this.erase,
    required this.cacheDirectory,
    this.logFile,
  });

  final String ipswPath;
  final ConnectedDevice device;

  /// `true` = full erase restore; `false` = update, keeping user data.
  final bool erase;

  /// idevicerestore extracts the root filesystem here (several GB); reusing
  /// it makes a retry of the same IPSW much faster.
  final String cacheDirectory;
  final String? logFile;
}

/// Drives `idevicerestore` and turns its output into [RestoreEvent]s.
///
/// The device is targeted by ECID when known: unlike the UDID, it stays the
/// same while the device reboots through Recovery → Restore mode.
class RestoreRunner {
  RestoreRunner(this.tools);

  final DeviceToolchain tools;
  Process? _process;

  bool get isRunning => _process != null;

  static List<String> buildArgs(RestoreRequest r) {
    final d = r.device;
    final ecid = d.ecid ?? d.info?.ecid;
    return [
      '-y', // never block on a prompt: there is no terminal to answer it
      '-P', // `progress: <step> <fraction>` lines
      if (r.erase) '-e',
      if (ecid != null) ...[
        '-i',
        '0x${ecid.toRadixString(16)}',
      ] else if (d.udid != null) ...[
        '-u',
        d.udid!,
      ],
      '-C',
      r.cacheDirectory,
      if (r.logFile != null) '--logfile=${r.logFile}',
      r.ipswPath,
    ];
  }

  Stream<RestoreEvent> run(RestoreRequest request) async* {
    if (_process != null) throw StateError('A restore is already running');
    if (!File(request.ipswPath).existsSync()) {
      yield RestoreLogEvent(
        'IPSW not found: ${request.ipswPath}',
        isError: true,
      );
      yield const RestoreFinishedEvent(success: false);
      return;
    }
    await Directory(request.cacheDirectory).create(recursive: true);
    final args = buildArgs(request);
    yield RestoreLogEvent('\$ idevicerestore ${args.join(' ')}');

    final process = await tools.start(DeviceTool.idevicerestore, args);
    _process = process;
    // DONE / RESTORE FAILED decide the outcome; the exit code is the fallback.
    // The result is emitted only after the process exits, because stderr can
    // still deliver lines after DONE.
    bool? outcome;
    try {
      await for (final line in DeviceToolchain.lines(process)) {
        final event = RestoreOutputParser.parse(line);
        if (event == null) continue;
        if (event is RestoreFinishedEvent) {
          outcome = event.success;
          continue;
        }
        yield event;
      }
      final code = await process.exitCode;
      if (outcome == null || code != 0) {
        yield RestoreLogEvent(
          'idevicerestore exited with code $code',
          isError: code != 0,
        );
      }
      yield RestoreFinishedEvent(success: outcome ?? code == 0);
    } finally {
      _process = null;
    }
  }

  /// Kills the tool. Interrupting a restore after the filesystem upload has
  /// started leaves the device in Recovery mode; it then needs a new restore.
  void abort() => _process?.kill();
}
