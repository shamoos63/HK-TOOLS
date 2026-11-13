import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/ios_device.dart';
import '../../services/device/app_icon_service.dart';
import '../../services/device/device_image_service.dart';
import '../../services/device/device_parsers.dart';
import '../../services/device/device_service.dart';
import '../../services/device/device_toolchain.dart';
import '../../services/restore/restore_insight.dart';
import '../../services/restore/restore_runner.dart';
import 'core_providers.dart';
import '../../core/l10n/l10n.dart';

final deviceToolchainProvider = Provider<DeviceToolchain>(
  (ref) => DeviceToolchain(
    customDirectory: ref.watch(
      settingsProvider.select((s) => s.deviceToolsDirectory),
    ),
  ),
);

final deviceServiceProvider = Provider<DeviceService>(
  (ref) => DeviceService(ref.watch(deviceToolchainProvider)),
);

/// Root for backups, screenshots, pulled files and crash logs. Defaults to
/// the Downloads folder (not the IPSW repository, which is often an external
/// drive that may be unplugged).
final deviceDataDirProvider = Provider<String>(
  (ref) =>
      ref.watch(settingsProvider.select((s) => s.deviceDataDirectory)) ??
      p.join(ref.watch(downloadsDirProvider), 'HK Tools', 'Device Data'),
);

String deviceFolder(String root, ConnectedDevice d, String kind) => p.join(
  root,
  kind,
  (d.info?.name ?? d.displayName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
);

/// Folder for a new backup of [d]: `<root>/<device name> <yyyy-MM-dd HH.mm>`.
/// `idevicebackup2` puts the backup itself in a `<udid>` folder inside it,
/// so every backup is kept and is easy to recognise in Finder / Explorer.
String namedBackupDir(String root, ConnectedDevice d, [DateTime? at]) {
  final t = at ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final name = (d.info?.name ?? d.displayName)
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();
  return p.join(
    root,
    '$name ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}',
  );
}

// ───────────────────────── discovery ─────────────────────────

class DevicesState {
  const DevicesState({
    this.devices = const [],
    this.toolsMissing = false,
    this.polling = true,
    this.lastPoll,
  });

  final List<ConnectedDevice> devices;

  /// `idevice_id` / `ideviceinfo` are not installed.
  final bool toolsMissing;
  final bool polling;
  final DateTime? lastPoll;

  ConnectedDevice? byId(String? id) =>
      devices.where((d) => d.id == id).firstOrNull;
}

/// Polls for attached devices and fetches lockdown info for new ones.
/// Paused while a restore runs: `irecovery` opens the USB device directly and
/// must not compete with `idevicerestore` for it.
class DevicesController extends Notifier<DevicesState> {
  Timer? _timer;
  bool _busy = false;
  final Map<String, ConnectedDevice> _known = {};

  static const interval = Duration(milliseconds: 2500);

  @override
  DevicesState build() {
    final tools = ref.watch(deviceToolchainProvider);
    final missing =
        !tools.has(DeviceTool.ideviceId) || !tools.has(DeviceTool.ideviceinfo);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => poll());
    ref.onDispose(() => _timer?.cancel());
    scheduleMicrotask(poll);
    return DevicesState(toolsMissing: missing);
  }

  void setPaused(bool paused) => state = DevicesState(
    devices: state.devices,
    toolsMissing: state.toolsMissing,
    polling: !paused,
    lastPoll: state.lastPoll,
  );

  Future<void> poll() async {
    if (_busy || !state.polling || state.toolsMissing) return;
    _busy = true;
    try {
      final service = ref.read(deviceServiceProvider);
      final found = await service.discover();
      final next = <ConnectedDevice>[];
      for (final d in found) {
        var known = _known[d.id];
        if (known == null || known.mode != d.mode) {
          known = d;
        }
        if (d.mode.isBooted && known.pairState != PairState.paired) {
          known = await _loadInfo(service, known);
        }
        _known[d.id] = known;
        next.add(known);
      }
      _known.removeWhere((id, _) => !found.any((d) => d.id == id));
      if (!state.polling) return;
      state = DevicesState(
        devices: next,
        toolsMissing: state.toolsMissing,
        lastPoll: DateTime.now(),
      );
    } on Object {
      // A transient tool failure must not stop polling.
    } finally {
      _busy = false;
    }
  }

  Future<ConnectedDevice> _loadInfo(
    DeviceService service,
    ConnectedDevice d,
  ) async {
    try {
      final info = await service.info(d);
      return d.copyWith(
        info: () => info,
        name: info.name,
        productType: info.productType,
        ecid: info.ecid,
        pairState: PairState.paired,
        pairError: () => null,
      );
    } on ToolFailure catch (e) {
      return d.copyWith(
        pairState: DeviceParsers.pairState(e.message),
        pairError: () => e.message,
      );
    }
  }

  /// Re-reads lockdown info (after a rename, pairing, or update).
  Future<void> refresh(String id) async {
    final d = state.byId(id);
    if (d == null || !d.mode.isBooted) return;
    final updated = await _loadInfo(ref.read(deviceServiceProvider), d);
    _known[id] = updated;
    state = DevicesState(
      devices: [for (final x in state.devices) x.id == id ? updated : x],
      toolsMissing: state.toolsMissing,
      polling: state.polling,
      lastPoll: state.lastPoll,
    );
  }
}

final devicesProvider = NotifierProvider<DevicesController, DevicesState>(
  DevicesController.new,
);

final activeDeviceIdProvider =
    NotifierProvider<ValueController<String?>, String?>(
      () => ValueController(null),
    );

/// The device shown in the detail pane: the chosen one, else the first.
final activeDeviceProvider = Provider<ConnectedDevice?>((ref) {
  final devices = ref.watch(devicesProvider).devices;
  final id = ref.watch(activeDeviceIdProvider);
  return devices.where((d) => d.id == id).firstOrNull ?? devices.firstOrNull;
});

enum DeviceTab {
  overview('Overview'),
  apps('Apps'),
  files('Files'),
  gallery('Photos'),
  contacts('Contacts'),
  screen('Screen'),
  console('Logs'),
  backup('Backup'),
  tools('Tools'),
  restore('Firmware');

  const DeviceTab(this._label);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);

  /// Tabs that work without a booted, paired OS.
  bool get lowLevel => this == overview || this == restore;
}

final deviceTabProvider =
    NotifierProvider<ValueController<DeviceTab>, DeviceTab>(
      () => ValueController(DeviceTab.overview),
    );

ConnectedDevice _require(Ref ref, String id) =>
    ref.read(devicesProvider).byId(id) ??
    (throw StateError('Device disconnected'));

final deviceBatteryProvider = FutureProvider.autoDispose
    .family<BatteryInfo, String>(
      (ref, id) => ref.watch(deviceServiceProvider).battery(_require(ref, id)),
    );

final deviceStorageProvider = FutureProvider.autoDispose
    .family<StorageInfo?, String>(
      (ref, id) => ref.watch(deviceServiceProvider).storage(_require(ref, id)),
    );

final deviceAppsProvider = FutureProvider.autoDispose
    .family<List<InstalledApp>, (String, bool)>(
      (ref, key) => ref
          .watch(deviceServiceProvider)
          .apps(_require(ref, key.$1), includeSystem: key.$2),
    );

/// AFC listing keyed by (device id, path, app id for house_arrest or null).
final deviceDirectoryProvider = FutureProvider.autoDispose
    .family<List<AfcEntry>, (String, String, String?)>(
      (ref, key) => ref
          .watch(deviceServiceProvider)
          .listDirectory(_require(ref, key.$1), key.$2, documentsOf: key.$3),
    );

// ───────────────────────── live console ─────────────────────────

class SyslogState {
  const SyslogState({this.lines = const [], this.running = false, this.error});

  final List<String> lines;
  final bool running;
  final String? error;
}

class SyslogController extends Notifier<SyslogState> {
  SyslogController(this.deviceId);

  final String deviceId;
  Process? _process;
  final List<String> _buffer = [];
  Timer? _flush;

  static const maxLines = 5000;

  @override
  SyslogState build() {
    ref.onDispose(stop);
    return const SyslogState();
  }

  Future<void> start({bool quiet = true, String? process}) async {
    await stop();
    final device = ref.read(devicesProvider).byId(deviceId);
    if (device == null) return;
    try {
      final proc = await ref
          .read(deviceServiceProvider)
          .startSyslog(device, quiet: quiet, process: process);
      _process = proc;
      _buffer.clear();
      state = const SyslogState(running: true);
      DeviceToolchain.lines(proc).listen((l) {
        if (l.trim().isEmpty) return;
        _buffer.add(l);
        if (_buffer.length > maxLines) {
          _buffer.removeRange(0, _buffer.length - maxLines);
        }
        // Batch UI updates: syslog can emit hundreds of lines a second.
        _flush ??= Timer(const Duration(milliseconds: 150), () {
          _flush = null;
          state = SyslogState(lines: List.of(_buffer), running: true);
        });
      });
      unawaited(
        proc.exitCode.then((_) {
          if (_process == proc) {
            _process = null;
            state = SyslogState(lines: List.of(_buffer));
          }
        }),
      );
    } on Object catch (e) {
      state = SyslogState(error: '$e');
    }
  }

  Future<void> stop() async {
    _flush?.cancel();
    _flush = null;
    final proc = _process;
    _process = null;
    proc?.kill();
    if (ref.mounted) state = SyslogState(lines: List.of(_buffer));
  }

  void clear() {
    _buffer.clear();
    state = SyslogState(running: state.running);
  }
}

final syslogProvider = NotifierProvider.autoDispose
    .family<SyslogController, SyslogState, String>(SyslogController.new);

// ───────────────────────── long-running jobs ─────────────────────────

enum JobStatus { idle, running, succeeded, failed }

/// Output and progress of one long-running tool process (backup, restore of
/// a backup).
class JobState {
  const JobState({
    this.status = JobStatus.idle,
    this.title = '',
    this.progress,
    this.log = const [],
  });

  final JobStatus status;
  final String title;

  /// 0–1 when the tool reports a percentage.
  final double? progress;
  final List<String> log;
}

class BackupJobController extends Notifier<JobState> {
  Process? _process;
  static final _percent = RegExp(r'(\d{1,3}(?:\.\d+)?)%');

  /// idevicebackup2 prints a bar per file (`[===] 40% (1.2 MB/3 MB)`) and,
  /// between files, the overall progress: `[===] 45% Finished`. Only the
  /// overall lines move the job's bar, so it doesn't restart for every file.
  static final _overall = RegExp(
    r'(\d{1,3}(?:\.\d+)?)%\s*Finished',
    caseSensitive: false,
  );

  @override
  JobState build() {
    ref.onDispose(() => _process?.kill());
    return const JobState();
  }

  bool get running => _process != null;

  Future<void> run(String title, Future<Process> Function() start) async {
    if (_process != null) return;
    state = JobState(status: JobStatus.running, title: title);
    try {
      final proc = await start();
      _process = proc;
      final log = <String>[];
      var sawOverall = false;
      await for (final line in DeviceToolchain.lines(proc)) {
        final l = line.trim();
        if (l.isEmpty) continue;
        final m = _percent.allMatches(l).lastOrNull;
        if (m != null && log.isNotEmpty && _percent.hasMatch(log.last)) {
          log[log.length - 1] = l; // progress bars rewrite one line
        } else {
          log.add(l);
        }
        if (log.length > 400) log.removeAt(0);
        final overall = _overall.firstMatch(l);
        if (overall != null) sawOverall = true;
        // Tools without overall lines: use any percentage, but never let
        // the bar go backwards.
        final pct = overall ?? (sawOverall ? null : m);
        final value = pct == null
            ? null
            : (double.parse(pct.group(1)!) / 100).clamp(0.0, 1.0);
        state = JobState(
          status: JobStatus.running,
          title: title,
          progress: value == null
              ? state.progress
              : (overall != null
                    ? value
                    : (value > (state.progress ?? 0) ? value : state.progress)),
          log: List.of(log),
        );
      }
      final code = await proc.exitCode;
      final failed =
          code != 0 || log.any((l) => l.toLowerCase().contains('failed'));
      state = JobState(
        status: failed ? JobStatus.failed : JobStatus.succeeded,
        title: title,
        progress: failed ? state.progress : 1,
        log: state.log,
      );
    } on Object catch (e) {
      state = JobState(status: JobStatus.failed, title: title, log: ['$e']);
    } finally {
      _process = null;
    }
  }

  void cancel() => _process?.kill();
}

final backupJobProvider = NotifierProvider<BackupJobController, JobState>(
  BackupJobController.new,
);

// ───────────────────────── firmware restore ─────────────────────────

/// Activating the device after a successful restore.
enum AutoActivation { none, waiting, activating, done, failed, skipped }

class RestoreState {
  const RestoreState({
    this.status = JobStatus.idle,
    this.request,
    this.step,
    this.fraction = 0,
    this.stepsSeen = const [],
    this.log = const [],
    this.startedAt,
    this.finishedAt,
    this.overall = 0,
    this.activity,
    this.aborted = false,
    this.activation = AutoActivation.none,
    this.activationNote,
  });

  final JobStatus status;

  /// Activation that runs once the restored device has booted.
  final AutoActivation activation;

  /// Why activation was skipped or failed.
  final String? activationNote;
  final RestoreRequest? request;
  final RestoreStep? step;

  /// Progress through [step], 0–1.
  final double fraction;

  /// Progress through the whole restore, 0–1; never goes backwards.
  final double overall;

  /// What the tool is doing in plain words, between progress updates.
  final String? activity;

  /// The user stopped the restore.
  final bool aborted;
  final List<RestoreStep> stepsSeen;
  final List<RestoreLogEvent> log;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get running => status == JobStatus.running;

  /// Whole-restore progress shown to the user.
  double get shownProgress => status == JobStatus.succeeded
      ? 1
      : math.max(overall, RestoreInsight.overall(step, fraction));

  RestoreState copyWith({
    JobStatus? status,
    RestoreStep? step,
    double? fraction,
    List<RestoreStep>? stepsSeen,
    List<RestoreLogEvent>? log,
    DateTime? finishedAt,
    double? overall,
    String? activity,
    bool? aborted,
    AutoActivation? activation,
    String? Function()? activationNote,
  }) => RestoreState(
    status: status ?? this.status,
    request: request,
    step: step ?? this.step,
    fraction: fraction ?? this.fraction,
    stepsSeen: stepsSeen ?? this.stepsSeen,
    log: log ?? this.log,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    overall: overall ?? this.overall,
    activity: activity ?? this.activity,
    aborted: aborted ?? this.aborted,
    activation: activation ?? this.activation,
    activationNote: activationNote != null
        ? activationNote()
        : this.activationNote,
  );
}

class RestoreController extends Notifier<RestoreState> {
  RestoreRunner? _runner;

  @override
  RestoreState build() {
    ref.onDispose(() => _runner?.abort());
    return const RestoreState();
  }

  String get cacheDirectory =>
      p.join(ref.read(appSupportDirProvider), 'restore_cache');

  String newLogFile() => p.join(
    ref.read(appSupportDirProvider),
    'restore_logs',
    'restore_${DateTime.now().toIso8601String().replaceAll(':', '-')}.log',
  );

  Future<void> start(RestoreRequest request) async {
    if (state.running) return;
    final runner = RestoreRunner(ref.read(deviceToolchainProvider));
    _runner = runner;
    if (request.logFile != null) {
      await Directory(p.dirname(request.logFile!)).create(recursive: true);
    }
    final devices = ref.read(devicesProvider.notifier)..setPaused(true);
    state = RestoreState(
      status: JobStatus.running,
      request: request,
      startedAt: DateTime.now(),
    );
    final log = <RestoreLogEvent>[];
    var success = false;
    try {
      await for (final e in runner.run(request)) {
        switch (e) {
          case RestoreProgressEvent(:final step, :final fraction):
            state = state.copyWith(
              step: step,
              fraction: fraction,
              stepsSeen: state.stepsSeen.contains(step)
                  ? state.stepsSeen
                  : [...state.stepsSeen, step],
              overall: math.max(
                state.overall,
                RestoreInsight.overall(step, fraction),
              ),
            );
          case RestoreLogEvent():
            log.add(e);
            if (log.length > 1500) log.removeAt(0);
            state = state.copyWith(
              log: List.of(log),
              activity: RestoreInsight.activity(e.line),
            );
          case RestoreFinishedEvent(success: final ok):
            success = ok;
        }
      }
    } on Object catch (e) {
      log.add(RestoreLogEvent('$e', isError: true));
    } finally {
      _runner = null;
      devices.setPaused(false);
      state = state.copyWith(
        status: success ? JobStatus.succeeded : JobStatus.failed,
        fraction: success ? 1 : state.fraction,
        overall: success ? 1 : state.overall,
        log: List.of(log),
        finishedAt: DateTime.now(),
      );
      if (success && ref.read(settingsProvider).autoActivate) {
        unawaited(_autoActivate(request));
      }
    }
  }

  /// After a restore the device boots into Setup Assistant, unactivated.
  /// Waits for it to come back, then activates it with Apple's activation
  /// server (as Finder does), so it is ready to set up.
  Future<void> _autoActivate(RestoreRequest request) async {
    void set(AutoActivation a, [String? note]) {
      if (!ref.mounted || state.request != request) return;
      state = state.copyWith(activation: a, activationNote: () => note);
    }

    if (!ref.read(deviceToolchainProvider).has(DeviceTool.pymobiledevice3)) {
      return set(
        AutoActivation.skipped,
        tr(
          'Install pymobiledevice3 (Settings › Device tools › Setup assistant) to activate devices automatically.',
        ),
      );
    }
    set(AutoActivation.waiting);
    final udid = request.device.udid;
    final ecid = request.device.ecid ?? request.device.info?.ecid;
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    ConnectedDevice? device;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!ref.mounted || state.request != request) return;
      final booted = ref
          .read(devicesProvider)
          .devices
          .where((d) => d.mode.isBooted)
          .toList();
      device =
          booted
              .where(
                (d) =>
                    (udid != null && d.udid == udid) ||
                    (ecid != null && (d.ecid ?? d.info?.ecid) == ecid),
              )
              .firstOrNull ??
          (booted.length == 1 ? booted.first : null);
      if (device != null) break;
    }
    if (device == null) {
      return set(
        AutoActivation.failed,
        tr(
          'The device didn\'t come back after the restore. Activate it from My Device › Overview once it has started.',
        ),
      );
    }
    if (device.info?.activationState == 'Activated') {
      return set(AutoActivation.done);
    }
    set(AutoActivation.activating);
    Object? error;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await ref.read(deviceServiceProvider).activate(device!);
        error = null;
        break;
      } on Object catch (e) {
        error = e;
        // Services may still be starting right after boot.
        await Future<void>.delayed(const Duration(seconds: 10));
        if (!ref.mounted) return;
        device = ref.read(devicesProvider).byId(device!.id) ?? device;
      }
    }
    if (error != null) {
      return set(
        AutoActivation.failed,
        trf(
          'Automatic activation failed: {0}. If Activation Lock is on, sign in with the owner\'s Apple ID on the device.',
          [error],
        ),
      );
    }
    set(AutoActivation.done);
    unawaited(ref.read(devicesProvider.notifier).refresh(device!.id));
  }

  void abort() {
    if (_runner == null) return;
    state = state.copyWith(aborted: true);
    _runner?.abort();
  }

  /// Runs the last restore again (same IPSW, device and mode).
  /// [erase] overrides the last restore's choice (e.g. a failed update that
  /// now needs an erase).
  Future<void> retry({bool? erase}) async {
    final last = state.request;
    if (state.running || last == null) return;
    // The device may have come back with a different id (e.g. now in
    // Recovery mode); ECID targeting in the runner still finds it.
    await start(
      RestoreRequest(
        ipswPath: last.ipswPath,
        device: last.device,
        erase: erase ?? last.erase,
        cacheDirectory: last.cacheDirectory,
        logFile: newLogFile(),
      ),
    );
  }

  void reset() {
    if (!state.running) state = const RestoreState();
  }
}

final restoreProvider = NotifierProvider<RestoreController, RestoreState>(
  RestoreController.new,
);

// ───────────────────────── app icons ─────────────────────────

final appIconServiceProvider = Provider<AppIconService>(
  (ref) => AppIconService(
    cacheDir: p.join(ref.watch(appSupportDirProvider), 'app_icons'),
  ),
);

/// Bundle ID → local icon file. Shared by the Apps tab and the App Store.
class AppIconsController extends Notifier<Map<String, String>> {
  final Set<String> _requested = {};

  @override
  Map<String, String> build() => const {};

  /// Resolves icons for [bundleIds] in the background. With [device], icons
  /// the App Store lookup can't find (built-in apps) are read from the
  /// device's SpringBoard when pymobiledevice3 is installed.
  Future<void> ensure(
    Iterable<String> bundleIds, {
    ConnectedDevice? device,
  }) async {
    final service = ref.read(appIconServiceProvider);
    final found = <String, String>{};
    final missing = <String>[];
    for (final id in bundleIds) {
      if (state.containsKey(id) || !_requested.add(id)) continue;
      final path = service.cached(id);
      if (path != null) {
        found[id] = path;
      } else {
        missing.add(id);
      }
    }
    if (found.isNotEmpty) state = {...state, ...found};
    if (missing.isEmpty) return;

    final host = Platform.localeName.split(RegExp('[_.-]'));
    final country = host.length > 1 ? host[1].toLowerCase() : 'us';
    final tools = ref.read(deviceToolchainProvider);
    final svc = ref.read(deviceServiceProvider);
    final pending = <String, String>{};
    Timer? flush;
    void onIcon(String id, String path) {
      pending[id] = path;
      flush ??= Timer(const Duration(milliseconds: 200), () {
        flush = null;
        if (!ref.mounted) return;
        state = {...state, ...pending};
        pending.clear();
      });
    }

    await service.resolve(
      missing,
      onIcon: onIcon,
      countries: {'us', country}.toList(),
      fromDevice:
          device != null &&
              device.udid != null &&
              tools.has(DeviceTool.pymobiledevice3)
          ? (id, out) => svc.appIconFromDevice(device, id, out)
          : null,
    );
    flush?.cancel();
    if (ref.mounted && pending.isNotEmpty) state = {...state, ...pending};
  }
}

final appIconsProvider =
    NotifierProvider<AppIconsController, Map<String, String>>(
      AppIconsController.new,
    );

// ───────────────────────── activation / setup ─────────────────────────

final deviceSetupDoneProvider = FutureProvider.autoDispose
    .family<bool?, String>(
      (ref, id) =>
          ref.watch(deviceServiceProvider).setupDone(_require(ref, id)),
    );

// ───────────────────────── device photos ─────────────────────────

final deviceImageServiceProvider = Provider<DeviceImageService>(
  (ref) => DeviceImageService(
    cacheDir: p.join(ref.watch(appSupportDirProvider), 'device_images'),
  ),
);

/// Local path of a product photo for a connected device (`null` when there
/// is none). Keyed by `productType|DeviceColor|DeviceEnclosureColor`.
final deviceImageProvider = FutureProvider.family<String?, String>((ref, key) {
  final parts = key.split('|');
  String? at(int i) =>
      i < parts.length && parts[i].isNotEmpty ? parts[i] : null;
  return ref
      .watch(deviceImageServiceProvider)
      .imageFor(parts.first, color: at(1), enclosureColor: at(2));
});

/// [deviceImageProvider] key for [d], or `null` before its model is known.
String? deviceImageKey(ConnectedDevice d) {
  final type = d.productType ?? d.info?.productType;
  if (type == null) return null;
  final raw = d.info?.raw ?? const {};
  return [
    type,
    raw['DeviceColor']?.toString() ?? '',
    raw['DeviceEnclosureColor']?.toString() ?? '',
  ].join('|');
}
