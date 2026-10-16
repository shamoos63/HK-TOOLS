@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/services/device/device_parsers.dart';
import 'package:hk_ipsw_manager/services/device/device_service.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:hk_ipsw_manager/services/restore/restore_runner.dart';
import 'package:path/path.dart' as p;

/// Runs the real process plumbing against shell-script stand-ins for the
/// libimobiledevice tools.
void main() {
  late Directory dir;

  Future<void> script(String name, String body) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', f.path]);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hk_tools_');
  });
  tearDown(() => dir.delete(recursive: true));

  test('discover merges USB, network and recovery devices', () async {
    await script('idevice_id', r'''
if [ "$1" = "-l" ]; then echo 00008101-000A1C3E0C38001E; fi
if [ "$1" = "-n" ]; then
  echo 00008101-000A1C3E0C38001E
  echo a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
fi''');
    await script('irecovery', r'''
printf 'CPID: 0x8020\nECID: 0x1AB2C3\nMODE: DFU\nPRODUCT: iPhone11,8\n' ''');
    await script('ideviceinfo', 'exit 0');

    final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
    final devices = await svc.discover();
    expect(devices.map((d) => (d.id, d.mode, d.connection)), [
      ('00008101-000A1C3E0C38001E', DeviceMode.normal, DeviceConnection.usb),
      (
        'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
        DeviceMode.normal,
        DeviceConnection.network,
      ),
      ('ecid:1ab2c3', DeviceMode.dfu, DeviceConnection.usb),
    ]);
    expect(devices.last.productType, 'iPhone11,8');
  });

  test('afcclient commands end options with -- so ls -l works', () async {
    final args = p.join(dir.path, 'afc_args.txt');
    await script('afcclient', '''
echo "\$@" >> "$args"
echo "drwxr-xr-x    2 mobile mobile      14400 15 Oct 2026 14:45:04 103APPLE"
echo "drwxr-xr-x    4 mobile mobile        128 07 Oct 2026 06:49:14 .MISC"''');
    final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
    const d = ConnectedDevice(
      id: 'u',
      udid: 'abc',
      mode: DeviceMode.normal,
      connection: DeviceConnection.usb,
    );
    final entries = await svc.listDirectory(d, '/DCIM');
    expect(entries.map((e) => e.name), ['.MISC', '103APPLE']);
    await svc.pull(d, '/DCIM/103APPLE', '/tmp/out', recursive: true);
    final calls = File(args).readAsLinesSync();
    expect(calls[0], '-u abc -- ls -l /DCIM');
    expect(calls[1], '-u abc -- get -rf /DCIM/103APPLE /tmp/out');
  });

  test('a tool that prompts gets EOF instead of hanging', () async {
    await script(
      'ideviceinfo',
      'read answer || { echo "no input" >&2; exit 3; }',
    );
    final sw = Stopwatch()..start();
    final r = await DeviceToolchain(customDirectory: dir.path).run(
      DeviceTool.ideviceinfo,
      const [],
      timeout: const Duration(seconds: 10),
    );
    expect(r.timedOut, isFalse);
    expect(r.exitCode, 3);
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('restore runner streams progress and reports success', () async {
    final args = p.join(dir.path, 'args.txt');
    await script('idevicerestore', '''
echo "\$@" > "$args"
echo "Found device in DFU mode"
echo "progress: 1 0.500000"
printf "progress: 2 0.250000\\rprogress: 2 1.000000\\n"
echo "ERROR: harmless warning" >&2
echo "DONE"
exit 0''');
    final ipsw = File(p.join(dir.path, 'fw.ipsw'))..writeAsStringSync('x');

    final runner = RestoreRunner(DeviceToolchain(customDirectory: dir.path));
    final events = await runner
        .run(
          RestoreRequest(
            ipswPath: ipsw.path,
            device: const ConnectedDevice(
              id: 'ecid:1ab2c3',
              ecid: 0x1AB2C3,
              mode: DeviceMode.dfu,
              connection: DeviceConnection.usb,
            ),
            erase: true,
            cacheDirectory: p.join(dir.path, 'cache'),
          ),
        )
        .toList();

    final progress = events.whereType<RestoreProgressEvent>().toList();
    expect(progress.map((e) => (e.step, e.fraction)), [
      (RestoreStep.prepare, 0.5),
      (RestoreStep.uploadFilesystem, 0.25),
      (RestoreStep.uploadFilesystem, 1.0),
    ]);
    expect(events.whereType<RestoreLogEvent>().any((e) => e.isError), isTrue);
    expect(events.last, isA<RestoreFinishedEvent>());
    expect((events.last as RestoreFinishedEvent).success, isTrue);
    expect(
      File(args).readAsStringSync().trim(),
      '-y -P -e -i 0x1ab2c3 -C ${p.join(dir.path, 'cache')} ${ipsw.path}',
    );
    expect(runner.isRunning, isFalse);
  });

  test('restore runner reports failure from the exit code', () async {
    await script('idevicerestore', 'echo "Unable to restore device"; exit 255');
    final ipsw = File(p.join(dir.path, 'fw.ipsw'))..writeAsStringSync('x');
    final events =
        await RestoreRunner(DeviceToolchain(customDirectory: dir.path))
            .run(
              RestoreRequest(
                ipswPath: ipsw.path,
                device: const ConnectedDevice(
                  id: 'u',
                  udid: 'abc',
                  mode: DeviceMode.normal,
                  connection: DeviceConnection.usb,
                ),
                erase: false,
                cacheDirectory: p.join(dir.path, 'cache'),
              ),
            )
            .toList();
    expect((events.last as RestoreFinishedEvent).success, isFalse);
  });

  test('missing tool raises a helpful error', () async {
    final tools = DeviceToolchain(customDirectory: dir.path);
    // The real tools may be installed on this machine; only assert the
    // message shape.
    expect(
      ToolMissingException(DeviceTool.idevicerestore).toString(),
      contains('idevicerestore was not found'),
    );
    expect(tools.searchDirectories.first, dir.path);
  });
}
