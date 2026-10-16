import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The libimobiledevice command-line tools the device features are built on.
/// All are LGPL; they are invoked as separate processes, never linked.
enum DeviceTool {
  ideviceId('idevice_id', 'Device discovery', core: true),
  ideviceinfo('ideviceinfo', 'Device information', core: true),
  idevicepair('idevicepair', 'Pairing / trust'),
  idevicename('idevicename', 'Rename device'),
  idevicediagnostics('idevicediagnostics', 'Battery, restart, shutdown'),
  ideviceinstaller('ideviceinstaller', 'App list / install / uninstall'),
  afcclient('afcclient', 'File explorer, gallery, app documents'),
  idevicebackup2('idevicebackup2', 'Backup & restore'),
  idevicescreenshot('idevicescreenshot', 'Screenshots / live screen'),
  idevicesyslog('idevicesyslog', 'Live console'),
  idevicesetlocation('idevicesetlocation', 'Virtual location'),
  ideviceimagemounter('ideviceimagemounter', 'Developer disk images'),
  idevicecrashreport('idevicecrashreport', 'Crash reports'),
  idevicedevmodectl('idevicedevmodectl', 'Developer Mode'),
  ideviceenterrecovery('ideviceenterrecovery', 'Enter Recovery mode'),
  irecovery('irecovery', 'Recovery / DFU detection, exit Recovery'),
  idevicerestore('idevicerestore', 'Flash IPSW firmware'),
  ipatool('ipatool', 'App Store sign-in & downloads'),
  pymobiledevice3(
    'pymobiledevice3',
    'Activation, skip Setup Assistant, built-in app icons',
  );

  const DeviceTool(this.executable, this.purpose, {this.core = false});

  final String executable;
  final String purpose;

  /// Without these the Devices section cannot list anything.
  final bool core;
}

class ToolMissingException implements Exception {
  ToolMissingException(this.tool);

  final DeviceTool tool;

  @override
  String toString() =>
      '${tool.executable} was not found. Install the libimobiledevice tools '
      'or set the tools folder in Settings › Device tools.';
}

/// A tool exited non-zero; [message] is its last meaningful output line.
class ToolFailure implements Exception {
  ToolFailure(this.tool, this.result);

  final DeviceTool tool;
  final ToolResult result;

  String get message => result.errorMessage;

  @override
  String toString() => message;
}

class ToolResult {
  const ToolResult(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;

  /// Best single-line explanation of a failure for the UI.
  String get errorMessage {
    if (timedOut) return 'Timed out waiting for the device.';
    final lines = '$stderr\n$stdout'
        .split('\n')
        .map(stripAnsi)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final err = lines.lastWhere(
      (l) => l.toUpperCase().startsWith('ERROR') || l.contains('rror'),
      orElse: () => lines.isEmpty ? 'Exited with code $exitCode' : lines.last,
    );
    return err.replaceFirst(RegExp(r'^ERROR:\s*', caseSensitive: false), '');
  }
}

final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
String stripAnsi(String s) => s.replaceAll(_ansi, '');

/// Locates and runs the device tools.
///
/// Search order: the folder chosen in Settings, a `tools` folder next to the
/// app executable (how the Windows build ships them), `PATH`, then the usual
/// Homebrew / MacPorts prefixes (GUI apps on macOS do not inherit the shell's
/// `PATH`).
class DeviceToolchain {
  DeviceToolchain({this.customDirectory});

  final String? customDirectory;
  final Map<DeviceTool, String?> _resolved = {};

  static const _utf8 = Utf8Codec(allowMalformed: true);

  /// Folder the setup assistant installs downloaded tools into
  /// (`%LOCALAPPDATA%\HK Tools\tools` on Windows; no admin rights needed).
  static String get managedDirectory {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final base =
          env['LOCALAPPDATA'] ??
          p.join(env['USERPROFILE'] ?? '', 'AppData', 'Local');
      return p.join(base, 'HK Tools', 'tools');
    }
    return p.join(
      env['HOME'] ?? '',
      'Library',
      'Application Support',
      'HK Tools',
      'tools',
    );
  }

  List<String> get searchDirectories {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final pathDirs = (Platform.environment['PATH'] ?? '')
        .split(Platform.isWindows ? ';' : ':')
        .where((d) => d.isNotEmpty);
    return [
      if (customDirectory != null && customDirectory!.isNotEmpty)
        customDirectory!,
      managedDirectory,
      p.join(exeDir, 'tools'),
      if (Platform.isMacOS) p.join(exeDir, '..', 'Resources', 'tools'),
      if (Platform.isWindows) exeDir,
      ...pathDirs,
      if (!Platform.isWindows) ...[
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/opt/local/bin',
        '/usr/bin',
      ],
      ..._pythonScriptDirs(),
    ];
  }

  /// Where `pip install` / `pipx` put console scripts such as pymobiledevice3,
  /// which are often missing from a GUI app's PATH.
  static List<String> _pythonScriptDirs() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    List<String> children(String parent, String Function(String) map) {
      final d = Directory(parent);
      if (!d.existsSync()) return const [];
      try {
        return [
          for (final c in d.listSync().whereType<Directory>())
            if (p.basename(c.path).toLowerCase().contains('python') ||
                RegExp(r'^\d').hasMatch(p.basename(c.path)))
              map(c.path),
        ];
      } on FileSystemException {
        return const [];
      }
    }

    if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? '';
      final local = env['LOCALAPPDATA'] ?? '';
      return [
        p.join(home, '.local', 'bin'),
        ...children(p.join(appData, 'Python'), (d) => p.join(d, 'Scripts')),
        ...children(
          p.join(local, 'Programs', 'Python'),
          (d) => p.join(d, 'Scripts'),
        ),
      ];
    }
    return [
      p.join(home, '.local', 'bin'),
      ...children(p.join(home, 'Library', 'Python'), (d) => p.join(d, 'bin')),
      ...children(
        '/Library/Frameworks/Python.framework/Versions',
        (d) => p.join(d, 'bin'),
      ),
    ];
  }

  /// Absolute path of [tool], or `null` when it is not installed.
  String? resolve(DeviceTool tool) => _resolved.putIfAbsent(tool, () {
    final name = Platform.isWindows
        ? '${tool.executable}.exe'
        : tool.executable;
    for (final dir in searchDirectories) {
      final candidate = p.join(dir, name);
      if (File(candidate).existsSync()) return p.normalize(candidate);
    }
    return null;
  });

  /// Forget resolved paths (after the setup assistant installs tools).
  void clearCache() => _resolved.clear();

  Map<DeviceTool, String?> probeAll() => {
    for (final t in DeviceTool.values) t: resolve(t),
  };

  bool has(DeviceTool tool) => resolve(tool) != null;

  String _require(DeviceTool tool) =>
      resolve(tool) ?? (throw ToolMissingException(tool));

  /// Runs [tool] to completion. Never throws for a non-zero exit; see
  /// [runChecked].
  Future<ToolResult> run(
    DeviceTool tool,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      _require(tool),
      args,
      environment: environment,
    );
    // Nothing is ever typed into these tools: closing stdin makes one that
    // unexpectedly prompts fail at once instead of waiting until the timeout.
    unawaited(process.stdin.close().catchError((_) {}));
    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = process.stdout.transform(_utf8.decoder).forEach(out.write);
    final errDone = process.stderr.transform(_utf8.decoder).forEach(err.write);
    var timedOut = false;
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    await Future.wait([outDone, errDone])
        .timeout(const Duration(seconds: 2), onTimeout: () => const []);
    return ToolResult(code, out.toString(), err.toString(), timedOut: timedOut);
  }

  /// [run], throwing [ToolFailure] unless the tool exits 0.
  Future<String> runChecked(
    DeviceTool tool,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
    Map<String, String>? environment,
  }) async {
    final r = await run(tool, args, timeout: timeout, environment: environment);
    if (!r.ok) throw ToolFailure(tool, r);
    return r.stdout;
  }

  /// Starts a long-running tool (syslog, backup, restore) and hands back the
  /// process so the caller can stream its output and kill it.
  Future<Process> start(
    DeviceTool tool,
    List<String> args, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) => Process.start(
    _require(tool),
    args,
    environment: environment,
    workingDirectory: workingDirectory,
  );

  /// Splits a process' stdout+stderr into lines, treating `\r` progress
  /// rewrites as line breaks.
  static Stream<String> lines(Process process) {
    final controller = StreamController<String>();
    var open = 2;
    void attach(Stream<List<int>> s) {
      s
          .transform(_utf8.decoder)
          .transform(const LineSplitter())
          .expand((l) => l.split('\r'))
          .map(stripAnsi)
          .listen(
            controller.add,
            onDone: () {
              if (--open == 0) controller.close();
            },
          );
    }

    attach(process.stdout);
    attach(process.stderr);
    return controller.stream;
  }
}
