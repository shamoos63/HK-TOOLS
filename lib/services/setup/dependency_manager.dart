import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../device/device_toolchain.dart';

/// Everything the device features need outside the app itself.
enum Dependency {
  appleDeviceSupport(
    'Apple device drivers',
    'USB connection to iPhone / iPad (Apple Mobile Device Service), plus the '
        'Recovery and DFU drivers used for flashing.',
    required: true,
  ),
  deviceTools(
    'libimobiledevice tools',
    'Device detection, info, files, backups, screenshots, console.',
    required: true,
  ),
  recoveryTools(
    'Restore & recovery tools',
    'idevicerestore, irecovery and ideviceinstaller: flashing IPSW firmware, '
        'Recovery / DFU detection, app installs.',
  ),
  ipatool('ipatool', 'App Store sign-in, IPA downloads and library updates.'),
  python('Python 3', 'Runs pymobiledevice3.'),
  pymobiledevice3(
    'pymobiledevice3',
    'Activation, Skip Setup, factory reset, built-in app icons; app '
        'install / uninstall when ideviceinstaller is missing.',
  );

  const Dependency(this.title, this.purpose, {this.required = false});

  final String title;
  final String purpose;

  /// Without it the Devices section can't work at all.
  final bool required;
}

class DependencyStatus {
  const DependencyStatus({
    required this.dependency,
    required this.installed,
    this.detail,
    this.canInstall = false,
    this.manualHint,
  });

  final Dependency dependency;
  final bool installed;

  /// Version, path, or why it's considered missing.
  final String? detail;

  /// The setup assistant can install it automatically.
  final bool canInstall;

  /// Shown when it can't be installed automatically.
  final String? manualHint;
}

class DependencyInstallException implements Exception {
  DependencyInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A download pinned to an exact file: its SHA-256 is checked before use.
class PinnedDownload {
  const PinnedDownload(this.url, this.sha256);

  final String url;
  final String sha256;
}

/// Pinned third-party downloads (update the URL and hash together).
abstract final class Downloads {
  /// Automated MSYS2 builds of libimobiledevice (core tools + DLLs) from
  /// github.com/jrjr/libimobiledevice-windows.
  static const windowsDeviceTools = PinnedDownload(
    'https://github.com/jrjr/libimobiledevice-windows/releases/download/'
        'v20261011-74585f8/libimobile-suite-latest_w64.zip',
    'dd9dc793a67d08bfa672eb0c215878251dc156407cf07fb88eeb241cac06d5b2',
  );

  /// Official ipatool releases (github.com/majd/ipatool).
  static const ipatoolWindowsX64 = PinnedDownload(
    'https://github.com/majd/ipatool/releases/download/v2.7.0/'
        'ipatool-2.7.0-windows-amd64.tar.gz',
    'b729608716908be287c2e6972f9e8cd05f879810ae5d182fc856c9e57cca0dd5',
  );
  static const ipatoolWindowsArm64 = PinnedDownload(
    'https://github.com/majd/ipatool/releases/download/v2.7.0/'
        'ipatool-2.7.0-windows-arm64.tar.gz',
    '85ab35a268b47e1729412178063fe11621cae1135f33d3b9ab5233d436bf2562',
  );

  /// GitHub repository ("owner/name") whose latest release carries
  /// `hk-tools-windows-device-tools.zip`, built by
  /// `.github/workflows/windows-device-tools.yml` (idevicerestore,
  /// irecovery, ideviceinstaller + DLLs). Empty until that workflow has been
  /// run and published.
  static const windowsExtrasRepo = 'shamoos63/HK-TOOLS';
  static const windowsExtrasAsset = 'hk-tools-windows-device-tools.zip';

  /// Apple Devices in the Microsoft Store (USB driver + usbmuxd service).
  static const appleDevicesStoreId = '9NP83LWLPZ9K';
}

typedef ProgressCallback = void Function(String status, double? fraction);

/// Checks and installs the external tools the device features rely on.
class DependencyManager {
  DependencyManager({
    required this.tools,
    http.Client? client,
    String? installDirectory,
  }) : _client = client ?? http.Client(),
       installDirectory = installDirectory ?? DeviceToolchain.managedDirectory;

  final DeviceToolchain tools;
  final http.Client _client;

  /// Where downloaded tools are unpacked; searched by [DeviceToolchain].
  final String installDirectory;

  // ───────────────────────── checks ─────────────────────────

  Future<List<DependencyStatus>> checkAll() async => [
    for (final d in Dependency.values) await check(d),
  ];

  Future<DependencyStatus> check(Dependency d) async {
    switch (d) {
      case Dependency.appleDeviceSupport:
        return _checkAppleSupport();
      case Dependency.deviceTools:
        final missing = [
          DeviceTool.ideviceId,
          DeviceTool.ideviceinfo,
          DeviceTool.afcclient,
          DeviceTool.idevicebackup2,
        ].where((t) => !tools.has(t)).toList();
        return DependencyStatus(
          dependency: d,
          installed: missing.isEmpty,
          detail: missing.isEmpty
              ? p.dirname(tools.resolve(DeviceTool.ideviceinfo)!)
              : 'Missing ${missing.map((t) => t.executable).join(', ')}',
          canInstall: Platform.isWindows || _brew != null,
        );
      case Dependency.recoveryTools:
        final missing = [
          DeviceTool.idevicerestore,
          DeviceTool.irecovery,
          DeviceTool.ideviceinstaller,
        ].where((t) => !tools.has(t)).toList();
        final windowsAuto =
            Platform.isWindows && Downloads.windowsExtrasRepo.isNotEmpty;
        return DependencyStatus(
          dependency: d,
          installed: missing.isEmpty,
          detail: missing.isEmpty
              ? null
              : 'Missing ${missing.map((t) => t.executable).join(', ')}',
          canInstall: windowsAuto || (!Platform.isWindows && _brew != null),
          manualHint: Platform.isWindows && !windowsAuto
              ? 'Build them with .github/workflows/windows-device-tools.yml (or '
                    'MSYS2) and put the .exe/.dll files in $installDirectory. '
                    'App installs fall back to pymobiledevice3 meanwhile.'
              : (!Platform.isWindows &&
                    missing.contains(DeviceTool.idevicerestore))
              ? 'idevicerestore is not in Homebrew: build it from '
                    'github.com/libimobiledevice/idevicerestore.'
              : null,
        );
      case Dependency.ipatool:
        final path = tools.resolve(DeviceTool.ipatool);
        return DependencyStatus(
          dependency: d,
          installed: path != null,
          detail: path,
          canInstall: Platform.isWindows || _brew != null,
        );
      case Dependency.python:
        final py = await _python();
        return DependencyStatus(
          dependency: d,
          installed: py != null,
          detail: py?.$2,
          canInstall: Platform.isWindows ? await _hasWinget() : _brew != null,
          manualHint: 'Install Python 3 from python.org.',
        );
      case Dependency.pymobiledevice3:
        final path = tools.resolve(DeviceTool.pymobiledevice3);
        return DependencyStatus(
          dependency: d,
          installed: path != null,
          detail: path,
          canInstall: await _python() != null,
          manualHint: 'Install Python 3 first.',
        );
    }
  }

  Future<DependencyStatus> _checkAppleSupport() async {
    const d = Dependency.appleDeviceSupport;
    if (!Platform.isWindows) {
      // macOS ships usbmuxd and the device drivers.
      return const DependencyStatus(
        dependency: d,
        installed: true,
        detail: 'Built into macOS',
      );
    }
    // Apple Mobile Device Service (from Apple Devices or iTunes) serves
    // usbmuxd on 127.0.0.1:27015.
    try {
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        27015,
        timeout: const Duration(seconds: 2),
      );
      s.destroy();
      return const DependencyStatus(
        dependency: d,
        installed: true,
        detail: 'Apple Mobile Device Service is running',
      );
    } on SocketException {
      // Installed but stopped?
      final q = await _run('sc', ['query', 'Apple Mobile Device Service']);
      final present = q?.exitCode == 0;
      return DependencyStatus(
        dependency: d,
        installed: false,
        detail: present
            ? 'Apple Mobile Device Service is installed but not running'
            : 'Not installed',
        canInstall: !present,
        manualHint: present
            ? 'Start "Apple Mobile Device Service" in Windows Services, or '
                  'restart the computer.'
            : 'Install "Apple Devices" from the Microsoft Store (or iTunes).',
      );
    }
  }

  // ───────────────────────── installs ─────────────────────────

  Future<void> install(Dependency d, {ProgressCallback? onProgress}) async {
    final progress = onProgress ?? (_, _) {};
    switch (d) {
      case Dependency.appleDeviceSupport:
        await _installAppleDevices(progress);
      case Dependency.deviceTools:
        if (Platform.isWindows) {
          await downloadAndExtract(Downloads.windowsDeviceTools, progress);
        } else {
          await _brewInstall(['libimobiledevice'], progress);
        }
      case Dependency.recoveryTools:
        if (Platform.isWindows) {
          await _installWindowsExtras(progress);
        } else {
          await _brewInstall(['libirecovery', 'ideviceinstaller'], progress);
        }
      case Dependency.ipatool:
        if (Platform.isWindows) {
          final arm =
              (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
                  .toUpperCase() ==
              'ARM64';
          await downloadAndExtract(
            arm ? Downloads.ipatoolWindowsArm64 : Downloads.ipatoolWindowsX64,
            progress,
            renameExe: (name) =>
                name.toLowerCase().startsWith('ipatool') ? 'ipatool.exe' : null,
          );
        } else {
          await _brewInstall(['ipatool'], progress);
        }
      case Dependency.python:
        if (Platform.isWindows) {
          await _winget(
            [
              'install',
              '--id',
              'Python.Python.3.12',
              '--exact',
              '--source',
              'winget',
              '--scope',
              'user',
            ],
            'Installing Python 3.12…',
            progress,
          );
        } else {
          await _brewInstall(['python'], progress);
        }
      case Dependency.pymobiledevice3:
        final py = await _python();
        if (py == null) {
          throw DependencyInstallException('Install Python 3 first.');
        }
        progress('Installing pymobiledevice3 with pip…', null);
        final r = await _run(py.$1.first, [
          ...py.$1.skip(1),
          '-m',
          'pip',
          'install',
          '--user',
          '--upgrade',
          'pymobiledevice3',
        ], timeout: const Duration(minutes: 15));
        if (r == null || r.exitCode != 0) {
          throw DependencyInstallException(
            'pip failed: ${_lastLine(r?.stderr ?? r?.stdout ?? 'not started')}',
          );
        }
    }
    tools.clearCache();
  }

  Future<void> _installAppleDevices(ProgressCallback progress) async {
    if (!Platform.isWindows) return;
    if (await _hasWinget()) {
      await _winget(
        [
          'install',
          '--id',
          Downloads.appleDevicesStoreId,
          '--exact',
          '--source',
          'msstore',
        ],
        'Installing Apple Devices from the Microsoft Store…',
        progress,
      );
      return;
    }
    // No winget: open the Store page so the user can install it.
    await Process.start('explorer.exe', [
      'ms-windows-store://pdp/?ProductId=${Downloads.appleDevicesStoreId}',
    ]);
    throw DependencyInstallException(
      'The Microsoft Store opened on Apple Devices. Install it there, then '
      'press Check again.',
    );
  }

  Future<void> _installWindowsExtras(ProgressCallback progress) async {
    if (Downloads.windowsExtrasRepo.isEmpty) {
      throw DependencyInstallException(
        'No download configured for idevicerestore / irecovery / '
        'ideviceinstaller on Windows yet.',
      );
    }
    progress('Looking up the latest build…', null);
    final res = await _client
        .get(
          Uri.https(
            'api.github.com',
            '/repos/${Downloads.windowsExtrasRepo}/releases/latest',
          ),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) {
      throw DependencyInstallException(
        'No Windows device tools release is published in '
        '${Downloads.windowsExtrasRepo} yet. Run the "Windows device tools" '
        'workflow on GitHub, then try again.',
      );
    }
    if (res.statusCode != 200) {
      throw DependencyInstallException(
        'GitHub returned ${res.statusCode} for ${Downloads.windowsExtrasRepo}.',
      );
    }
    final release = jsonDecode(res.body) as Map<String, dynamic>;
    final asset = (release['assets'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['name'] == Downloads.windowsExtrasAsset)
        .firstOrNull;
    final digest = '${asset?['digest'] ?? ''}';
    if (asset == null || !digest.startsWith('sha256:')) {
      throw DependencyInstallException(
        'The latest release has no ${Downloads.windowsExtrasAsset} with a '
        'SHA-256 digest.',
      );
    }
    await downloadAndExtract(
      PinnedDownload(
        asset['browser_download_url'] as String,
        digest.substring(7),
      ),
      progress,
    );
  }

  /// Downloads [d], verifies its SHA-256, then unpacks it into
  /// [installDirectory] with Windows' built-in `tar` (zip and tar.gz).
  @visibleForTesting
  Future<void> downloadAndExtract(
    PinnedDownload d,
    ProgressCallback progress, {
    String? Function(String fileName)? renameExe,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('hk_dep_');
    try {
      final file = File(p.join(tmp.path, p.basename(Uri.parse(d.url).path)));
      final req = http.Request('GET', Uri.parse(d.url));
      final res = await _client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw DependencyInstallException(
          'Download failed (HTTP ${res.statusCode}): ${d.url}',
        );
      }
      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      final hashSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashSink);
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        progress(
          'Downloading ${p.basename(file.path)}…',
          total == null || total == 0 ? null : received / total,
        );
      }
      await sink.close();
      hasher.close();
      if (hashSink.value.toString() != d.sha256.toLowerCase()) {
        throw DependencyInstallException(
          'Checksum mismatch for ${p.basename(file.path)}: the download was '
          'corrupted or changed. Nothing was installed.',
        );
      }

      progress('Unpacking…', null);
      final out = Directory(p.join(tmp.path, 'x'))..createSync();
      final r = await _run('tar', ['-xf', file.path, '-C', out.path]);
      if (r == null || r.exitCode != 0) {
        throw DependencyInstallException(
          'Could not unpack ${p.basename(file.path)}: '
          '${_lastLine(r?.stderr ?? 'tar not found')}',
        );
      }

      // Flatten: executables and DLLs go straight into the tools folder.
      final dest = Directory(installDirectory)..createSync(recursive: true);
      var copied = 0;
      for (final f in out.listSync(recursive: true).whereType<File>()) {
        final name = p.basename(f.path);
        final ext = p.extension(name).toLowerCase();
        if (ext != '.exe' && ext != '.dll' && ext.isNotEmpty) continue;
        final target = renameExe?.call(name) ?? name;
        await f.copy(p.join(dest.path, target));
        copied++;
      }
      if (copied == 0) {
        throw DependencyInstallException('The archive contained no programs.');
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  // ───────────────────────── helpers ─────────────────────────

  String? get _brew {
    for (final b in ['/opt/homebrew/bin/brew', '/usr/local/bin/brew']) {
      if (File(b).existsSync()) return b;
    }
    return null;
  }

  Future<void> _brewInstall(
    List<String> formulas,
    ProgressCallback progress,
  ) async {
    final brew = _brew;
    if (brew == null) {
      throw DependencyInstallException('Homebrew is not installed (brew.sh).');
    }
    progress('brew install ${formulas.join(' ')}…', null);
    final r = await _run(brew, [
      'install',
      ...formulas,
    ], timeout: const Duration(minutes: 20));
    if (r == null || r.exitCode != 0) {
      throw DependencyInstallException(
        'Homebrew failed: ${_lastLine(r?.stderr ?? 'not started')}',
      );
    }
  }

  Future<bool> _hasWinget() async =>
      Platform.isWindows &&
      (await _run('winget', ['--version']))?.exitCode == 0;

  /// The user consents in the setup assistant before this runs; the flags
  /// only stop winget from prompting in a window that has no console.
  Future<void> _winget(
    List<String> args,
    String status,
    ProgressCallback progress,
  ) async {
    progress(status, null);
    final r = await _run('winget', [
      ...args,
      '--accept-package-agreements',
      '--accept-source-agreements',
      '--disable-interactivity',
    ], timeout: const Duration(minutes: 20));
    // 0 = installed; 0x8A15002B = already installed / no applicable upgrade.
    if (r == null || (r.exitCode != 0 && r.exitCode != -1978335189)) {
      throw DependencyInstallException(
        'winget failed (${r?.exitCode}): ${_lastLine(r?.stdout ?? 'not started')}',
      );
    }
  }

  /// A working Python 3 command and its version, avoiding the Windows Store
  /// "python.exe" alias that only opens the Store.
  Future<(List<String>, String)?> _python() async {
    final candidates = Platform.isWindows
        ? [
            ['py', '-3'],
            ['python'],
            // Installed during this session: not on this process' PATH yet.
            ..._windowsPythonExes().map((e) => [e]),
          ]
        : [
            ['python3'],
            ['/opt/homebrew/bin/python3'],
            ['/usr/local/bin/python3'],
            ['/usr/bin/python3'],
          ];
    for (final c in candidates) {
      final r = await _run(c.first, [...c.skip(1), '--version']);
      final out = '${r?.stdout ?? ''}${r?.stderr ?? ''}'.trim();
      if (r?.exitCode == 0 && out.startsWith('Python 3')) return (c, out);
    }
    return null;
  }

  static List<String> _windowsPythonExes() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return const [];
    final out = <String>[];
    final launcher = p.join(local, 'Programs', 'Python', 'Launcher', 'py.exe');
    if (File(launcher).existsSync()) out.add(launcher);
    final root = Directory(p.join(local, 'Programs', 'Python'));
    if (root.existsSync()) {
      for (final d in root.listSync().whereType<Directory>()) {
        final exe = p.join(d.path, 'python.exe');
        if (p.basename(d.path).toLowerCase().startsWith('python3') &&
            File(exe).existsSync()) {
          out.add(exe);
        }
      }
    }
    return out;
  }

  static Future<ProcessResult?> _run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      return await Process.run(
        exe,
        args,
        runInShell: Platform.isWindows,
      ).timeout(timeout);
    } on Object {
      return null;
    }
  }

  static String _lastLine(Object text) => '$text'
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .lastWhere((l) => l.isNotEmpty, orElse: () => '');
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
