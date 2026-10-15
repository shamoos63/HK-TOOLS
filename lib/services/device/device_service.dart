import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/plist.dart';
import '../../domain/entities/ios_device.dart';
import 'device_parsers.dart';
import 'device_toolchain.dart';
import 'setup_assistant.dart';

/// Device operations built on the libimobiledevice tools. Every method maps to
/// one tool invocation so failures surface with the tool's own message.
class DeviceService {
  DeviceService(this.tools);

  final DeviceToolchain tools;

  List<String> _target(ConnectedDevice d) => [
    '-u',
    d.udid!,
    if (d.connection == DeviceConnection.network) '-n',
  ];

  // ───────────────────────── discovery ─────────────────────────

  /// Every device visible right now: booted (USB + network) and one device
  /// in Recovery/DFU (irecovery only reports the first it finds).
  Future<List<ConnectedDevice>> discover() async {
    final usb = tools.has(DeviceTool.ideviceId)
        ? tools.run(DeviceTool.ideviceId, ['-l'], timeout: _short)
        : null;
    final net = tools.has(DeviceTool.ideviceId)
        ? tools.run(DeviceTool.ideviceId, ['-n'], timeout: _short)
        : null;
    final rec = tools.has(DeviceTool.irecovery)
        ? tools.run(DeviceTool.irecovery, ['-q'], timeout: _short)
        : null;

    final devices = <ConnectedDevice>[];
    final usbIds = DeviceParsers.udids((await usb)?.stdout ?? '');
    for (final id in usbIds) {
      devices.add(
        ConnectedDevice(
          id: id,
          udid: id,
          mode: DeviceMode.normal,
          connection: DeviceConnection.usb,
        ),
      );
    }
    for (final id in DeviceParsers.udids((await net)?.stdout ?? '')) {
      if (usbIds.contains(id)) continue;
      devices.add(
        ConnectedDevice(
          id: id,
          udid: id,
          mode: DeviceMode.normal,
          connection: DeviceConnection.network,
        ),
      );
    }
    final r = await rec;
    if (r != null && r.ok) {
      final q = DeviceParsers.irecoveryQuery(r.stdout);
      final ecid = DeviceParsers.ecid(q['ECID']);
      if (ecid != null) {
        devices.add(
          ConnectedDevice(
            id: 'ecid:${ecid.toRadixString(16)}',
            ecid: ecid,
            mode: DeviceMode.fromIrecovery(q['MODE']),
            connection: DeviceConnection.usb,
            productType: q['PRODUCT'],
            name: q['NAME'],
            pairState: PairState.paired,
            recoveryInfo: q,
          ),
        );
      }
    }
    return devices;
  }

  static const _short = Duration(seconds: 6);

  // ───────────────────────── info ─────────────────────────

  /// All lockdown values. Throws [ToolFailure] while the device is untrusted
  /// or locked; see [DeviceParsers.pairState].
  Future<DeviceInfo> info(ConnectedDevice d) async {
    final out = await tools.runChecked(DeviceTool.ideviceinfo, [
      ..._target(d),
      '-x',
    ]);
    return DeviceParsers.deviceInfo(parsePlistDict(out));
  }

  Future<Map<String, Object?>> domain(ConnectedDevice d, String domain) async {
    final out = await tools.runChecked(DeviceTool.ideviceinfo, [
      ..._target(d),
      '-q',
      domain,
      '-x',
    ]);
    return parsePlistDict(out);
  }

  Future<StorageInfo?> storage(ConnectedDevice d) async =>
      DeviceParsers.storage(await domain(d, 'com.apple.disk_usage'));

  Future<BatteryInfo> battery(ConnectedDevice d) async {
    final lockdown = domain(
      d,
      'com.apple.mobile.battery',
    ).then<Map<String, Object?>?>((v) => v, onError: (_) => null);
    Map<String, Object?>? ioreg;
    if (tools.has(DeviceTool.idevicediagnostics)) {
      final r = await tools.run(DeviceTool.idevicediagnostics, [
        ..._target(d),
        'ioregentry',
        'AppleSmartBattery',
      ]);
      if (r.ok) {
        try {
          ioreg = parsePlistDict(r.stdout);
        } on FormatException {
          ioreg = null;
        }
      }
    }
    return DeviceParsers.battery(ioreg, await lockdown);
  }

  /// `idevicediagnostics mobilegestalt KEY…` → `MobileGestalt` dictionary.
  Future<Map<String, Object?>> mobileGestalt(
    ConnectedDevice d,
    List<String> keys,
  ) async {
    final out = await tools.runChecked(DeviceTool.idevicediagnostics, [
      ..._target(d),
      'mobilegestalt',
      ...keys,
    ]);
    final m = parsePlistDict(out);
    return m.dict('MobileGestalt') ?? m;
  }

  // ───────────────────────── pairing & power ─────────────────────────

  Future<String> pair(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicepair, [..._target(d), 'pair']);

  Future<String> unpair(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicepair, [..._target(d), 'unpair']);

  Future<String> validatePairing(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicepair, [..._target(d), 'validate']);

  Future<void> rename(ConnectedDevice d, String name) =>
      tools.runChecked(DeviceTool.idevicename, [..._target(d), name]);

  Future<void> restart(ConnectedDevice d) => tools.runChecked(
    DeviceTool.idevicediagnostics,
    [..._target(d), 'restart'],
  );

  Future<void> shutdown(ConnectedDevice d) => tools.runChecked(
    DeviceTool.idevicediagnostics,
    [..._target(d), 'shutdown'],
  );

  Future<void> sleep(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicediagnostics, [..._target(d), 'sleep']);

  Future<void> enterRecovery(ConnectedDevice d) => tools.runChecked(
    DeviceTool.ideviceenterrecovery,
    [d.udid!],
    timeout: const Duration(seconds: 40),
  );

  /// Reboots a Recovery-mode device back into iOS (fixes a recovery loop).
  Future<void> exitRecovery(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.irecovery, [
        if (d.ecid != null) ...['-i', '0x${d.ecid!.toRadixString(16)}'],
        '-n',
      ]);

  // ───────────────────────── activation & setup ─────────────────────────

  /// pymobiledevice3 command for this device; errors carry friendly text.
  Future<String> _pmd3(
    ConnectedDevice d,
    List<String> args, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final r = await tools.run(DeviceTool.pymobiledevice3, [
      ...args,
      '--udid',
      d.udid!,
    ], timeout: timeout);
    final text = '${r.stdout}\n${r.stderr}';
    final failed = !r.ok || RegExp(r'\bERROR\b|Traceback').hasMatch(text);
    if (failed) {
      final line = text
          .split('\n')
          .map((l) => stripAnsi(l).trim())
          .lastWhere(
            (l) =>
                l.contains('ERROR') ||
                l.contains('Exception') ||
                l.contains('Error'),
            orElse: () => r.errorMessage,
          );
      throw Exception(
        friendlySetupError(line.replaceFirst(RegExp(r'^.*ERROR\s*'), '')),
      );
    }
    return r.stdout.trim();
  }

  /// Activates the device with Apple's activation server (the same request
  /// iTunes / Finder make). Fails with a clear message when Activation Lock is
  /// on.
  Future<void> activate(ConnectedDevice d) =>
      _pmd3(d, ['activation', 'activate', '--now']);

  Future<String> activationState(ConnectedDevice d) =>
      _pmd3(d, ['activation', 'state'], timeout: const Duration(seconds: 30));

  /// `true` once Setup Assistant has finished (`SetupDone` in the
  /// com.apple.purplebuddy domain).
  Future<bool?> setupDone(ConnectedDevice d) async {
    try {
      return (await domain(d, 'com.apple.purplebuddy')).boolean('SetupDone');
    } on Object {
      return null;
    }
  }

  /// Applies an unsupervised cloud configuration that skips the given Setup
  /// Assistant panes. See setup_assistant.dart.
  Future<void> skipSetup(ConnectedDevice d, List<String> panes) async {
    final dir = await Directory.systemTemp.createTemp('hk_cloudcfg_');
    try {
      final file = File(p.join(dir.path, 'cloud_configuration.plist'));
      await file.writeAsString(cloudConfigurationPlist(panes));
      await _pmd3(d, ['profile', 'cloud-configuration', file.path]);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// "Erase All Content and Settings" through the device's configuration
  /// service (what Apple Configurator's Erase does). The device reboots into
  /// Setup Assistant; if Find My was on, Activation Lock still applies.
  Future<void> factoryReset(
    ConnectedDevice d, {
    bool preserveDataPlan = true,
  }) => _pmd3(d, [
    'profile',
    'erase-device',
    preserveDataPlan ? '--preserve-data-plan' : '--no-preserve-data-plan',
  ], timeout: const Duration(minutes: 2));

  /// Home-screen icon PNG straight from SpringBoard (works for built-in apps
  /// too). Needs pymobiledevice3.
  Future<void> appIconFromDevice(
    ConnectedDevice d,
    String bundleId,
    String outPath,
  ) => _pmd3(d, [
    'springboard',
    'icon',
    bundleId,
    outPath,
  ], timeout: const Duration(seconds: 40));

  // ───────────────────────── apps ─────────────────────────

  static const _appAttributes = [
    'CFBundleIdentifier',
    'CFBundleDisplayName',
    'CFBundleName',
    'CFBundleShortVersionString',
    'CFBundleVersion',
    'ApplicationType',
    'StaticDiskUsage',
    'DynamicDiskUsage',
    'UIFileSharingEnabled',
  ];

  /// ideviceinstaller when present; otherwise pymobiledevice3 (the default
  /// on Windows, where no trusted ideviceinstaller build is available).
  bool get _usePmd3ForApps =>
      !tools.has(DeviceTool.ideviceinstaller) &&
      tools.has(DeviceTool.pymobiledevice3);

  Future<List<InstalledApp>> apps(
    ConnectedDevice d, {
    bool includeSystem = false,
  }) async {
    if (_usePmd3ForApps) {
      final out = await _pmd3(d, [
        'apps',
        'list',
        '--type',
        includeSystem ? 'Any' : 'User',
        '--calculate-sizes',
      ], timeout: const Duration(minutes: 2));
      return DeviceParsers.appsFromJson(out);
    }
    final out = await tools.runChecked(DeviceTool.ideviceinstaller, [
      ..._target(d),
      'list',
      includeSystem ? '--all' : '--user',
      '--xml',
      for (final a in _appAttributes) ...['-a', a],
    ], timeout: const Duration(seconds: 60));
    return DeviceParsers.apps(parsePlistXml(out));
  }

  Future<String> installApp(ConnectedDevice d, String ipaPath) =>
      _usePmd3ForApps
      ? _pmd3(d, [
          'apps',
          'install',
          ipaPath,
        ], timeout: const Duration(minutes: 15))
      : tools.runChecked(DeviceTool.ideviceinstaller, [
          ..._target(d),
          'install',
          ipaPath,
        ], timeout: const Duration(minutes: 15));

  Future<String> uninstallApp(ConnectedDevice d, String bundleId) =>
      _usePmd3ForApps
      ? _pmd3(d, [
          'apps',
          'uninstall',
          bundleId,
        ], timeout: const Duration(minutes: 3))
      : tools.runChecked(DeviceTool.ideviceinstaller, [
          ..._target(d),
          'uninstall',
          bundleId,
        ], timeout: const Duration(minutes: 3));

  // ───────────────────────── files (AFC) ─────────────────────────

  /// AFC root is `/private/var/mobile/Media`; with [documentsOf] it is the
  /// Documents folder of that app (house_arrest, file-sharing apps only).
  ///
  /// Ends with `--`: afcclient parses options anywhere on the command line,
  /// so without it the command's own flags (`ls -l`, `get -rf`, `put -f`)
  /// are rejected as unknown afcclient options and nothing runs.
  List<String> _afc(ConnectedDevice d, String? documentsOf) => [
    ..._target(d),
    if (documentsOf != null) ...['--documents', documentsOf],
    '--',
  ];

  Future<List<AfcEntry>> listDirectory(
    ConnectedDevice d,
    String dir, {
    String? documentsOf,
  }) async {
    final r = await tools.run(DeviceTool.afcclient, [
      ..._afc(d, documentsOf),
      'ls',
      '-l',
      dir,
    ], timeout: const Duration(seconds: 30));
    final entries = DeviceParsers.afcListing(r.stdout, dir);
    if (entries.isEmpty && r.stdout.contains('Error:')) {
      throw ToolFailure(DeviceTool.afcclient, r);
    }
    return entries;
  }

  /// Copies a device file or folder to [localPath].
  Future<void> pull(
    ConnectedDevice d,
    String remotePath,
    String localPath, {
    String? documentsOf,
    bool recursive = false,
  }) async {
    final r = await tools.run(DeviceTool.afcclient, [
      ..._afc(d, documentsOf),
      'get',
      recursive ? '-rf' : '-f',
      remotePath,
      localPath,
    ], timeout: const Duration(hours: 2));
    if (!r.ok || r.stdout.contains('Error:')) {
      throw ToolFailure(DeviceTool.afcclient, r);
    }
  }

  Future<void> push(
    ConnectedDevice d,
    String localPath,
    String remoteDir, {
    String? documentsOf,
  }) async {
    final isDir = FileSystemEntity.isDirectorySync(localPath);
    final r = await tools.run(DeviceTool.afcclient, [
      ..._afc(d, documentsOf),
      'put',
      isDir ? '-rf' : '-f',
      localPath,
      p.posix.join(remoteDir, p.basename(localPath)),
    ], timeout: const Duration(hours: 2));
    if (!r.ok || r.stdout.contains('Error:')) {
      throw ToolFailure(DeviceTool.afcclient, r);
    }
  }

  Future<void> _afcSimple(
    ConnectedDevice d,
    List<String> cmd, {
    String? documentsOf,
  }) async {
    final r = await tools.run(DeviceTool.afcclient, [
      ..._afc(d, documentsOf),
      ...cmd,
    ]);
    if (!r.ok || r.stdout.contains('Error:')) {
      throw ToolFailure(DeviceTool.afcclient, r);
    }
  }

  Future<void> deletePath(
    ConnectedDevice d,
    String path, {
    String? documentsOf,
  }) => _afcSimple(d, ['rm', path], documentsOf: documentsOf);

  Future<void> makeDirectory(
    ConnectedDevice d,
    String path, {
    String? documentsOf,
  }) => _afcSimple(d, ['mkdir', path], documentsOf: documentsOf);

  Future<void> movePath(
    ConnectedDevice d,
    String from,
    String to, {
    String? documentsOf,
  }) => _afcSimple(d, ['mv', from, to], documentsOf: documentsOf);

  // ───────────────────────── screen, location, DDI ─────────────────────────

  /// Saves a PNG to [path]. Needs a mounted developer disk image.
  Future<void> screenshot(ConnectedDevice d, String path) async {
    await tools.runChecked(DeviceTool.idevicescreenshot, [
      ..._target(d),
      path,
    ], timeout: const Duration(seconds: 15));
  }

  Future<void> setLocation(ConnectedDevice d, double lat, double lon) =>
      tools.runChecked(DeviceTool.idevicesetlocation, [
        ..._target(d),
        '--',
        lat.toStringAsFixed(6),
        lon.toStringAsFixed(6),
      ]);

  Future<void> resetLocation(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicesetlocation, [..._target(d), 'reset']);

  Future<int> mountedImageCount(ConnectedDevice d) async {
    final out = await tools.runChecked(DeviceTool.ideviceimagemounter, [
      ..._target(d),
      '-x',
      'list',
    ]);
    try {
      return DeviceParsers.mountedImageCount(parsePlistXml(out));
    } on FormatException {
      return 0;
    }
  }

  /// [path]: a `.dmg` (with `.dmg.signature` beside it) for iOS ≤ 16, or a
  /// personalized DDI folder (BuildManifest.plist + Image.dmg + Firmware/)
  /// for iOS 17+.
  Future<String> mountDeveloperImage(ConnectedDevice d, String path) =>
      tools.runChecked(DeviceTool.ideviceimagemounter, [
        ..._target(d),
        'mount',
        path,
      ], timeout: const Duration(minutes: 3));

  Future<bool?> developerModeEnabled(ConnectedDevice d) async {
    final r = await tools.run(DeviceTool.idevicedevmodectl, [
      ..._target(d),
      'list',
    ]);
    return r.ok ? DeviceParsers.developerMode(r.stdout, d.udid!) : null;
  }

  Future<String> revealDeveloperMode(ConnectedDevice d) =>
      tools.runChecked(DeviceTool.idevicedevmodectl, [..._target(d), 'reveal']);

  Future<String> enableDeveloperMode(ConnectedDevice d) => tools.runChecked(
    DeviceTool.idevicedevmodectl,
    [..._target(d), 'enable'],
    timeout: const Duration(minutes: 3),
  );

  // ───────────────────────── crash reports, syslog, backup ───────────────

  /// Copies crash logs into [directory] and returns how many files arrived;
  /// with [remove] they are deleted from the device afterwards (the tool's
  /// default behaviour).
  Future<int> pullCrashReports(
    ConnectedDevice d,
    String directory, {
    bool remove = false,
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);
    int count() => dir.listSync(recursive: true).whereType<File>().length;
    final before = count();
    await tools.runChecked(DeviceTool.idevicecrashreport, [
      ..._target(d),
      '-e',
      if (!remove) '-k',
      directory,
    ], timeout: const Duration(minutes: 10));
    return count() - before;
  }

  Future<Process> startSyslog(
    ConnectedDevice d, {
    bool quiet = true,
    String? process,
  }) => tools.start(DeviceTool.idevicesyslog, [
    ..._target(d),
    '--no-colors',
    if (quiet) '-q',
    if (process != null && process.isNotEmpty) ...['-p', process],
  ]);

  /// `idevicebackup2 backup [--full] DIR`. The backup lands in
  /// `DIR/<udid>/`. Encrypted backups read the password from
  /// `BACKUP_PASSWORD`, never from the command line.
  Future<Process> startBackup(
    ConnectedDevice d,
    String directory, {
    bool full = false,
  }) async {
    await Directory(directory).create(recursive: true);
    return tools.start(DeviceTool.idevicebackup2, [
      ..._target(d),
      'backup',
      if (full) '--full',
      directory,
    ]);
  }

  Future<Process> startBackupRestore(
    ConnectedDevice d,
    String directory, {
    required String sourceUdid,
    bool system = false,
    bool settings = true,
    bool reboot = true,
    String? password,
  }) => tools.start(DeviceTool.idevicebackup2, [
    ..._target(d),
    '-s',
    sourceUdid,
    'restore',
    if (system) '--system',
    if (settings) '--settings',
    if (!reboot) '--no-reboot',
    directory,
  ], environment: password == null ? null : {'BACKUP_PASSWORD': password});

  Future<String> backupEncryption(
    ConnectedDevice d,
    String directory, {
    required bool enable,
    required String password,
  }) => tools.runChecked(
    DeviceTool.idevicebackup2,
    [..._target(d), 'encryption', enable ? 'on' : 'off', directory],
    environment: {'BACKUP_PASSWORD': password},
    timeout: const Duration(minutes: 2),
  );

  /// Lockdown flag: are this device's backups encrypted?
  Future<bool?> backupWillEncrypt(ConnectedDevice d) async {
    try {
      return (await domain(
        d,
        'com.apple.mobile.backup',
      )).boolean('WillEncrypt');
    } on Object {
      return null;
    }
  }
}
