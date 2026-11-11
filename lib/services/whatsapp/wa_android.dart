import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../device/device_toolchain.dart';
import '../../core/l10n/l10n.dart';

/// Pulls a WhatsApp backup straight off a USB-connected Android phone with
/// `adb`, the same way the commercial Android→iPhone transfer tools do:
///
///  1. The user turns on WhatsApp's end-to-end encrypted backup and picks
///     "Use 64-digit encryption key instead". WhatsApp shows the key on screen.
///  2. While the key is on screen we read it from the phone's UI hierarchy
///     (`uiautomator dump`), so nobody has to type 64 characters.
///  3. The user finishes the setup and taps "Back up". WhatsApp writes
///     `msgstore.db.crypt15` to shared storage (no root needed).
///  4. We `adb pull` it. That key decrypts it with [decryptWhatsAppDb]: the
///     64-digit key is the crypt15 root key that `WaBackupKey` already derives
///     from.
class AdbException implements Exception {
  AdbException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum AndroidDeviceState { ready, unauthorized, offline, other }

class AndroidDevice {
  const AndroidDevice({required this.serial, required this.state, this.model});

  final String serial;
  final AndroidDeviceState state;
  final String? model;

  String get displayName =>
      (model == null || model!.isEmpty) ? serial : model!.replaceAll('_', ' ');
}

/// What `getprop`, `dumpsys battery` and `df` report about a phone.
class AndroidDeviceInfo {
  const AndroidDeviceInfo({
    required this.serial,
    this.manufacturer,
    this.brand,
    this.model,
    this.marketName,
    this.codename,
    this.deviceName,
    this.androidVersion,
    this.sdk,
    this.securityPatch,
    this.buildId,
    this.cpuAbi,
    this.batteryLevel,
    this.charging,
    this.batteryTempC,
    this.storageTotal,
    this.storageFree,
  });

  final String serial;
  final String? manufacturer;
  final String? brand;

  /// Model number, e.g. `SM-A536E`.
  final String? model;

  /// Marketing name when the phone reports one (Xiaomi, OnePlus, …).
  final String? marketName;

  /// Device codename, e.g. `a53x`.
  final String? codename;

  /// The name the owner gave the phone.
  final String? deviceName;
  final String? androidVersion;
  final int? sdk;
  final String? securityPatch;
  final String? buildId;
  final String? cpuAbi;
  final int? batteryLevel;
  final bool? charging;
  final double? batteryTempC;

  /// Bytes.
  final int? storageTotal;
  final int? storageFree;

  static final _prop = RegExp(r'^\[([^\]]+)\]: \[(.*)\]$');

  factory AndroidDeviceInfo.parse({
    required String serial,
    required String getprop,
    String battery = '',
    String df = '',
    String deviceName = '',
  }) {
    final props = <String, String>{};
    for (final l in const LineSplitter().convert(getprop)) {
      final m = _prop.firstMatch(l.trim());
      if (m != null && m.group(2)!.isNotEmpty) props[m.group(1)!] = m.group(2)!;
    }
    String? prop(List<String> keys) =>
        keys.map((k) => props[k]).whereType<String>().firstOrNull;

    final bat = <String, String>{};
    for (final l in const LineSplitter().convert(battery)) {
      final i = l.indexOf(':');
      if (i > 0) bat[l.substring(0, i).trim()] = l.substring(i + 1).trim();
    }
    final level = int.tryParse(bat['level'] ?? '');
    final scale = int.tryParse(bat['scale'] ?? '') ?? 100;
    final temp = int.tryParse(bat['temperature'] ?? '');

    int? total, free;
    final dfLines = const LineSplitter()
        .convert(df)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (dfLines.length >= 2) {
      final cols = dfLines.last.trim().split(RegExp(r'\s+'));
      if (cols.length >= 4) {
        total = (int.tryParse(cols[1]) ?? 0) * 1024;
        free = (int.tryParse(cols[3]) ?? 0) * 1024;
        if (total == 0) total = null;
      }
    }
    final name = deviceName.trim();
    return AndroidDeviceInfo(
      serial: serial,
      manufacturer: prop([
        'ro.product.manufacturer',
        'ro.product.vendor.manufacturer',
      ]),
      brand: prop(['ro.product.brand', 'ro.product.vendor.brand']),
      model: prop(['ro.product.model', 'ro.product.vendor.model']),
      marketName: prop([
        'ro.product.marketname',
        'ro.product.vendor.marketname',
        'ro.vendor.oplus.market.name',
        'ro.config.marketing_name',
      ]),
      codename: prop(['ro.product.device', 'ro.product.vendor.device']),
      deviceName: name.isEmpty || name == 'null' ? null : name,
      androidVersion: prop(['ro.build.version.release']),
      sdk: int.tryParse(props['ro.build.version.sdk'] ?? ''),
      securityPatch: prop(['ro.build.version.security_patch']),
      buildId: prop(['ro.build.display.id']),
      cpuAbi: prop(['ro.product.cpu.abi']),
      batteryLevel: level == null ? null : (level * 100 / scale).round(),
      // BatteryManager status 2 = charging, 5 = full.
      charging: bat['status'] == null ? null : bat['status'] == '2',
      batteryTempC: temp == null ? null : temp / 10,
      storageTotal: total,
      storageFree: free,
    );
  }
}

enum WaFlavor {
  whatsapp('com.whatsapp', 'WhatsApp'),
  business('com.whatsapp.w4b', 'WhatsApp Business');

  const WaFlavor(this.package, this.label);

  final String package;
  final String label;

  /// Where each WhatsApp version keeps its local backups, newest layout first
  /// (Android 11+ scoped storage, then the legacy root folder).
  List<String> get databaseDirs => switch (this) {
    WaFlavor.whatsapp => const [
      '/sdcard/Android/media/com.whatsapp/WhatsApp/Databases',
      '/sdcard/WhatsApp/Databases',
    ],
    WaFlavor.business => const [
      '/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business/Databases',
      '/sdcard/WhatsApp Business/Databases',
    ],
  };
}

/// A backup file found on the phone.
class AndroidWaBackup {
  const AndroidWaBackup({
    required this.remotePath,
    required this.size,
    required this.modified,
    required this.flavor,
  });

  final String remotePath;
  final int size;
  final DateTime modified;
  final WaFlavor flavor;

  String get fileName => p.posix.basename(remotePath);

  /// `msgstore.db.crypt15` is the latest backup; dated files are older ones.
  bool get isLatest => fileName.startsWith('msgstore.db.');
}

class WaAndroidClient {
  WaAndroidClient({this.customDirectory});

  /// The device-tools folder chosen in Settings; also searched for `adb`.
  final String? customDirectory;

  String? _adb;
  static const _utf8 = Utf8Codec(allowMalformed: true);

  /// Folders searched for `adb`: the device-tools folders, then the Android
  /// SDK's platform-tools (Android Studio's default install location).
  List<String> get searchDirectories {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return [
      ...DeviceToolchain(customDirectory: customDirectory).searchDirectories,
      for (final k in ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
        if ((env[k] ?? '').isNotEmpty) p.join(env[k]!, 'platform-tools'),
      if (Platform.isMacOS)
        p.join(home, 'Library', 'Android', 'sdk', 'platform-tools'),
      if (Platform.isWindows)
        p.join(env['LOCALAPPDATA'] ?? '', 'Android', 'Sdk', 'platform-tools'),
      if (Platform.isLinux) p.join(home, 'Android', 'Sdk', 'platform-tools'),
      if (Platform.isMacOS) '/opt/homebrew/Caskroom/android-platform-tools',
    ];
  }

  /// Absolute path of `adb`, or `null` if it is not installed.
  String? resolveAdb() {
    if (_adb != null) return _adb;
    final name = Platform.isWindows ? 'adb.exe' : 'adb';
    for (final dir in searchDirectories) {
      final candidate = p.join(dir, name);
      if (File(candidate).existsSync()) return _adb = p.normalize(candidate);
    }
    return null;
  }

  bool get hasAdb => resolveAdb() != null;

  Future<ToolResult> _run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final adb =
        resolveAdb() ??
        (throw AdbException(
          tr(
            'adb was not found. Install Android platform-tools (macOS: "brew install --cask android-platform-tools"; Windows: "winget install Google.PlatformTools") or put adb in the device tools folder.',
          ),
        ));
    final process = await Process.start(adb, args);
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

  Future<String> _shell(
    String serial,
    String command, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final r = await _run(['-s', serial, 'shell', command], timeout: timeout);
    if (r.timedOut) {
      throw AdbException(
        tr('The phone stopped responding. Reconnect the cable.'),
      );
    }
    return r.stdout;
  }

  /// Connected phones (`adb devices -l`).
  Future<List<AndroidDevice>> devices() async {
    final r = await _run(['devices', '-l']);
    if (!r.ok) throw AdbException(r.errorMessage);
    return parseDevices(r.stdout);
  }

  static List<AndroidDevice> parseDevices(String output) {
    final list = <AndroidDevice>[];
    for (final raw in const LineSplitter().convert(output)) {
      final line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('List of devices') ||
          line.startsWith('*')) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final state = switch (parts[1]) {
        'device' => AndroidDeviceState.ready,
        'unauthorized' => AndroidDeviceState.unauthorized,
        'offline' => AndroidDeviceState.offline,
        _ => AndroidDeviceState.other,
      };
      String? model;
      for (final kv in parts.skip(2)) {
        if (kv.startsWith('model:')) model = kv.substring(6);
      }
      list.add(AndroidDevice(serial: parts[0], state: state, model: model));
    }
    return list;
  }

  /// Model, Android version, battery and storage of [serial] (one round
  /// trip per source; values a phone doesn't report stay `null`).
  Future<AndroidDeviceInfo> deviceInfo(String serial) async {
    final results = await Future.wait([
      _shell(serial, 'getprop'),
      _shell(serial, 'dumpsys battery').catchError((_) => ''),
      _shell(serial, 'df /data').catchError((_) => ''),
      _shell(serial, 'settings get global device_name').catchError((_) => ''),
    ]);
    return AndroidDeviceInfo.parse(
      serial: serial,
      getprop: results[0],
      battery: results[1],
      df: results[2],
      deviceName: results[3],
    );
  }

  /// Which WhatsApp versions are installed on [serial].
  Future<List<WaFlavor>> installedFlavors(String serial) async {
    final out = await _shell(serial, 'pm list packages com.whatsapp');
    final pkgs = {
      for (final l in const LineSplitter().convert(out))
        l.trim().replaceFirst('package:', ''),
    };
    return [
      for (final f in WaFlavor.values)
        if (pkgs.contains(f.package)) f,
    ];
  }

  /// Opens WhatsApp's Chat backup settings on the phone, or just launches
  /// WhatsApp when that screen can't be opened directly.
  Future<void> openWhatsApp(String serial, WaFlavor flavor) async {
    final out = await _shell(
      serial,
      'am start -n ${flavor.package}/com.whatsapp.backup.google.SettingsGoogleDrive 2>&1',
    );
    if (out.contains('Error') || out.contains('Exception')) {
      await _shell(
        serial,
        'monkey -p ${flavor.package} -c android.intent.category.LAUNCHER 1',
      );
    }
  }

  /// Reads the 64-digit backup key off the phone's screen. The phone must be
  /// showing WhatsApp's "Your 64-digit encryption key" page. Returns `null`
  /// when no key is visible.
  Future<String?> readKeyFromScreen(String serial, {int attempts = 3}) async {
    const remote = '/sdcard/hk_wa_ui.xml';
    // The first dump often catches the screen mid-animation (the paid tools
    // retry too), so try a few times.
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _shell(
        serial,
        'rm -f $remote; uiautomator dump $remote >/dev/null 2>&1',
        timeout: const Duration(seconds: 30),
      );
      final xml = await _shell(
        serial,
        'cat $remote 2>/dev/null; rm -f $remote',
      );
      final key = extractKeyFromUiDump(xml);
      if (key != null) return key;
    }
    return null;
  }

  /// Finds a 64-hex-digit key in a `uiautomator dump`. WhatsApp shows the key
  /// either as one text block or as 16 groups of 4; both are handled.
  static String? extractKeyFromUiDump(String xml) {
    final values = <String>[
      for (final m in RegExp(
        r'''(?:text|content-desc)="([^"]*)"''',
      ).allMatches(xml))
        _unescape(m.group(1)!),
    ];
    final whole = RegExp(r'^[0-9a-f]{64}$');
    final groupsOnly = RegExp(r'^(?:[0-9a-f]{4}\s*)+$');
    // One node holding the whole key (possibly spaced / line-broken).
    for (final v in values) {
      final compact = v.toLowerCase().replaceAll(RegExp(r'\s'), '');
      if (whole.hasMatch(compact)) return compact;
    }
    // The key split across nodes in 4-character groups, in screen order.
    final buffer = StringBuffer();
    for (final v in values) {
      final t = v.toLowerCase().trim();
      if (t.isNotEmpty && groupsOnly.hasMatch(t)) {
        buffer.write(t.replaceAll(RegExp(r'\s'), ''));
      }
    }
    final joined = buffer.toString();
    if (joined.length == 64) return joined;
    return null;
  }

  static String _unescape(String s) => s
      .replaceAll('&#10;', '\n')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// WhatsApp backups on the phone, newest first.
  Future<List<AndroidWaBackup>> findBackups(
    String serial, {
    List<WaFlavor> flavors = WaFlavor.values,
  }) async {
    final found = <AndroidWaBackup>[];
    for (final flavor in flavors) {
      for (final dir in flavor.databaseDirs) {
        // `stat` (toybox) prints size|mtime|path; the glob is outside the
        // quotes so the folder name may contain spaces.
        final out = await _shell(
          serial,
          "stat -c '%s|%Y|%n' '$dir'/msgstore*.db.crypt1* 2>/dev/null",
        );
        found.addAll(parseStat(out, flavor));
      }
    }
    found.sort((a, b) => b.modified.compareTo(a.modified));
    return found;
  }

  static List<AndroidWaBackup> parseStat(String output, WaFlavor flavor) => [
    for (final line in const LineSplitter().convert(output))
      if (line.split('|') case [final size, final mtime, ...final path]
          when int.tryParse(size.trim()) != null &&
              int.tryParse(mtime.trim()) != null)
        AndroidWaBackup(
          remotePath: path.join('|').trim(),
          size: int.parse(size.trim()),
          modified: DateTime.fromMillisecondsSinceEpoch(
            int.parse(mtime.trim()) * 1000,
          ),
          flavor: flavor,
        ),
  ];

  /// Polls until a backup newer than [since] appears (the user tapped "Back
  /// up" in WhatsApp) and its size stops changing. Throws on [timeout].
  Future<AndroidWaBackup> waitForNewBackup(
    String serial, {
    required DateTime since,
    List<WaFlavor> flavors = WaFlavor.values,
    Duration timeout = const Duration(minutes: 15),
    bool Function()? cancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    AndroidWaBackup? last;
    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) {
        throw AdbException(tr('Stopped waiting for the backup.'));
      }
      final latest = (await findBackups(
        serial,
        flavors: flavors,
      )).where((b) => b.isLatest && b.modified.isAfter(since)).firstOrNull;
      if (latest != null) {
        // Done once the file is stable across two polls.
        if (last != null &&
            last.remotePath == latest.remotePath &&
            last.size == latest.size &&
            last.modified == latest.modified) {
          return latest;
        }
        last = latest;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw AdbException(
      tr(
        'No new backup appeared. In WhatsApp open Settings → Chats → Chat backup and tap "Back up", then try again.',
      ),
    );
  }

  /// The WhatsApp root folder (holding `Media/`) for [backup].
  static String whatsAppRootOf(AndroidWaBackup backup) =>
      p.posix.dirname(p.posix.dirname(backup.remotePath));

  /// Copies the phone's WhatsApp `Media` folder (photos, videos, voice notes,
  /// documents…) to `<localDir>/Media`, one subfolder at a time so progress can
  /// be reported. Returns the number of bytes copied. Folders that only hold
  /// status updates or caches are skipped.
  Future<int> pullMedia(
    String serial,
    AndroidWaBackup backup,
    String localDir, {
    void Function(double fraction, String folder)? onProgress,
  }) async {
    final media = '${whatsAppRootOf(backup)}/Media';
    final listing = await _shell(serial, "ls -1 '$media' 2>/dev/null");
    final folders = [
      for (final l in const LineSplitter().convert(listing))
        if (l.trim().isNotEmpty &&
            !l.trim().startsWith('.') &&
            !l.contains('Statuses') &&
            !l.contains('Profile Photos') &&
            !l.contains('Backup Excluded'))
          l.trim(),
    ];
    final sizes = <String, int>{};
    for (final f in folders) {
      final du = await _shell(serial, "du -sk '$media/$f' 2>/dev/null");
      sizes[f] =
          (int.tryParse(du.trim().split(RegExp(r'\s+')).first) ?? 0) * 1024;
    }
    final total = sizes.values.fold<int>(0, (a, b) => a + b);
    final out = Directory(p.join(localDir, 'Media'))
      ..createSync(recursive: true);
    var done = 0;
    for (final f in folders) {
      onProgress?.call(total == 0 ? 0 : done / total, f);
      await _pullWithRetry(
        serial,
        '$media/$f',
        out.path,
        trf('Copying "{0}"', [f]),
      );
      done += sizes[f] ?? 0;
    }
    onProgress?.call(1, '');
    return total;
  }

  /// `adb pull` that survives the USB hiccups ("protocol fault") phones
  /// often have during long copies: waits for the phone and retries.
  Future<void> _pullWithRetry(
    String serial,
    String remote,
    String local,
    String what, {
    int attempts = 3,
  }) async {
    ToolResult? last;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await _run([
          '-s',
          serial,
          'wait-for-device',
        ], timeout: const Duration(minutes: 2));
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      last = await _run([
        '-s',
        serial,
        'pull',
        remote,
        local,
      ], timeout: const Duration(hours: 3));
      if (last.ok) return;
    }
    throw AdbException(trf('{0} failed: {1}', [what, last!.errorMessage]));
  }

  /// Copies [backup] to [localDir] and returns the local path.
  Future<String> pull(
    String serial,
    AndroidWaBackup backup,
    String localDir,
  ) async {
    Directory(localDir).createSync(recursive: true);
    final local = p.join(localDir, backup.fileName);
    final f = File(local);
    if (f.existsSync()) f.deleteSync();
    await _pullWithRetry(
      serial,
      backup.remotePath,
      local,
      tr('Copying the backup'),
    );
    if (!f.existsSync()) {
      throw AdbException(tr('Copying the backup failed.'));
    }
    if (f.lengthSync() != backup.size) {
      throw AdbException(
        tr(
          'The copied backup is incomplete. Keep the phone connected and retry.',
        ),
      );
    }
    return local;
  }
}
