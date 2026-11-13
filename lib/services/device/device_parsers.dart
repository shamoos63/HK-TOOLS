/// Pure parsers for libimobiledevice tool output. Kept free of IO so they can
/// be unit-tested against captured output.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../core/utils/plist.dart';
import '../../domain/entities/ios_device.dart';
import 'device_toolchain.dart';

abstract final class DeviceParsers {
  static final _udid = RegExp(r'^[0-9A-Fa-f-]{24,}$');

  /// `idevice_id -l` / `-n`: one UDID per line (older builds append
  /// ` (USB)` / ` (Network)`).
  static List<String> udids(String output) => [
    for (final line in output.split('\n'))
      if (line.trim().split(RegExp(r'\s+')).first case final id
          when _udid.hasMatch(id))
        id,
  ];

  /// `irecovery -q`: `KEY: VALUE` lines.
  static Map<String, String> irecoveryQuery(String output) {
    final out = <String, String>{};
    for (final raw in output.split('\n')) {
      final line = stripAnsi(raw).trim();
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final key = line.substring(0, i).trim().toUpperCase();
      if (key.contains(' ') || key == 'ERROR') continue;
      out[key] = line.substring(i + 1).trim();
    }
    return out;
  }

  /// Parses an ECID in either decimal (lockdown `UniqueChipID`) or `0x` hex
  /// (irecovery) notation.
  static int? ecid(String? s) {
    if (s == null || s.isEmpty) return null;
    final t = s.trim();
    if (t.toLowerCase().startsWith('0x')) {
      return int.tryParse(t.substring(2), radix: 16);
    }
    return int.tryParse(t);
  }

  static DeviceInfo deviceInfo(Map<String, Object?> m) => DeviceInfo(
    raw: m,
    name: m.str('DeviceName'),
    productType: m.str('ProductType'),
    productVersion: m.str('ProductVersion'),
    buildVersion: m.str('BuildVersion'),
    serialNumber: m.str('SerialNumber'),
    ecid: m.integer('UniqueChipID'),
    modelNumber: m.str('ModelNumber'),
    regionInfo: m.str('RegionInfo'),
    hardwareModel: m.str('HardwareModel'),
    cpuArchitecture: m.str('CPUArchitecture'),
    deviceClass: m.str('DeviceClass'),
    wifiAddress: m.str('WiFiAddress'),
    bluetoothAddress: m.str('BluetoothAddress'),
    phoneNumber: m.str('PhoneNumber'),
    imei: m.str('InternationalMobileEquipmentIdentity'),
    activationState: m.str('ActivationState'),
    basebandVersion: m.str('BasebandVersion'),
    passwordProtected: m.boolean('PasswordProtected'),
  );

  /// Classifies lockdown connection errors from ideviceinfo / idevicepair.
  static PairState pairState(String error) {
    final e = error.toLowerCase();
    if (e.contains('pairing dialog response pending') ||
        e.contains('pairing_dialog_response_pending') ||
        e.contains('(-19)')) {
      return PairState.pendingTrust;
    }
    if (e.contains('password protected') ||
        e.contains('passcode') ||
        e.contains('(-17)')) {
      return PairState.locked;
    }
    if (e.contains('user denied') || e.contains('(-18)')) {
      return PairState.denied;
    }
    return PairState.unknown;
  }

  /// [ioreg]: `idevicediagnostics ioregentry AppleSmartBattery` (the entry is
  /// either top level or under `IORegistry`). [lockdown]: `ideviceinfo -q
  /// com.apple.mobile.battery`.
  static BatteryInfo battery(
    Map<String, Object?>? ioreg,
    Map<String, Object?>? lockdown,
  ) {
    final r = ioreg?.dict('IORegistry') ?? ioreg ?? const {};
    // Newer iOS versions keep the mAh figures (design / full-charge
    // capacity) only in the nested BatteryData dictionary, while the top
    // level reports percentages; read the top level first, then BatteryData.
    final bd = r.dict('BatteryData') ?? const {};
    final l = lockdown ?? const {};
    int? n(String key) => r.integer(key) ?? bd.integer(key);
    double? real(String key) => r.real(key) ?? bd.real(key);
    int? mah(int? v) => v != null && v > 100 ? v : null;
    final rawTemp = real('Temperature') ?? real('VirtualTemperature');
    final rawVoltage = real('Voltage') ?? real('AppleRawBatteryVoltage');
    final currentPct = r.integer('CurrentCapacity');
    return BatteryInfo(
      level:
          l.integer('BatteryCurrentCapacity') ??
          (currentPct != null && currentPct <= 100 ? currentPct : null),
      isCharging: l.boolean('BatteryIsCharging') ?? r.boolean('IsCharging'),
      fullyCharged: l.boolean('FullyCharged') ?? r.boolean('FullyCharged'),
      externalConnected:
          l.boolean('ExternalConnected') ?? r.boolean('ExternalConnected'),
      cycleCount: n('CycleCount'),
      designCapacity: mah(n('DesignCapacity')),
      // NominalChargeCapacity is what Settings › Battery › Health uses.
      maxCapacity:
          mah(n('NominalChargeCapacity')) ??
          mah(n('AppleRawMaxCapacity')) ??
          mah(n('FullChargeCapacity')) ??
          mah(n('MaxCapacity')),
      currentCapacity:
          mah(n('AppleRawCurrentCapacity')) ??
          mah(n('TrueRemainingCapacity')) ??
          mah(n('RemainingCapacity')) ??
          mah(currentPct),
      // Reported in centi-degrees Celsius.
      temperatureC: rawTemp == null ? null : rawTemp / 100,
      // Reported in millivolts.
      voltage: rawVoltage == null ? null : rawVoltage / 1000,
      amperage: n('InstantAmperage') ?? n('Amperage'),
      serial:
          r.str('Serial') ?? r.str('BatterySerialNumber') ?? bd.str('Serial'),
    );
  }

  static StorageInfo? storage(Map<String, Object?> m) {
    final total = m.integer('TotalDiskCapacity');
    final available = m.integer('AmountDataAvailable');
    if (total == null || available == null) return null;
    return StorageInfo(
      totalDisk: total,
      totalData: m.integer('TotalDataCapacity') ?? total,
      availableData: available,
      totalSystem: m.integer('TotalSystemCapacity'),
      apps: m.integer('MobileApplicationUsage'),
      photos: switch ((m.integer('PhotoUsage'), m.integer('CameraUsage'))) {
        (null, null) => null,
        (final a, final b) => (a ?? 0) + (b ?? 0),
      },
    );
  }

  /// `ideviceinstaller list --xml`: an array of app dictionaries.
  static List<InstalledApp> apps(Object? plist) {
    if (plist is! List) return const [];
    final apps = <InstalledApp>[];
    for (final item in plist) {
      if (item is! Map<String, Object?>) continue;
      final id = item.str('CFBundleIdentifier');
      if (id == null) continue;
      apps.add(
        InstalledApp(
          bundleId: id,
          name: item.str('CFBundleDisplayName') ?? item.str('CFBundleName'),
          version: item.str('CFBundleShortVersionString'),
          build: item.str('CFBundleVersion'),
          type: item.str('ApplicationType'),
          staticSize: item.integer('StaticDiskUsage'),
          dynamicSize: item.integer('DynamicDiskUsage'),
          fileSharing: item.boolean('UIFileSharingEnabled') ?? false,
        ),
      );
    }
    apps.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return apps;
  }

  /// `pymobiledevice3 apps list` JSON: bundle id → app info dictionary.
  static List<InstalledApp> appsFromJson(String output) {
    final start = output.indexOf('{');
    if (start < 0) return const [];
    final decoded = jsonDecode(output.substring(start));
    if (decoded is! Map) return const [];
    return apps([
      for (final e in decoded.entries)
        if (e.value is Map)
          <String, Object?>{
            'CFBundleIdentifier': e.key,
            ...(e.value as Map).cast<String, Object?>(),
          },
    ]);
  }

  // drwxr-xr-x   3 mobile mobile        96 05 Oct 2026 14:22:11 DCIM
  static final _afcLong = RegExp(
    r'^([-dlfbcs][rwx-]{8,9})\s+(\d+)\s+\S+\s+\S+\s+(\d+)\s+'
    r'(\d{1,2}) (\S{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})\s(.+)$',
  );
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// `afcclient ls -l DIR`. Hidden `.`/`..` entries are dropped; folders sort
  /// first.
  static List<AfcEntry> afcListing(String output, String dir) {
    final entries = <AfcEntry>[];
    for (final raw in output.split('\n')) {
      final line = stripAnsi(raw).trimRight();
      final m = _afcLong.firstMatch(line);
      if (m == null) continue;
      final name = m.group(10)!;
      if (name == '.' || name == '..') continue;
      final perms = m.group(1)!;
      final month = _months[m.group(5)!.toLowerCase()];
      entries.add(
        AfcEntry(
          name: name,
          path: p.posix.join(dir, name),
          isDirectory: perms.startsWith('d'),
          isLink: perms.startsWith('l'),
          size: int.parse(m.group(3)!),
          modified: month == null
              ? null
              : DateTime(
                  int.parse(m.group(6)!),
                  month,
                  int.parse(m.group(4)!),
                  int.parse(m.group(7)!),
                  int.parse(m.group(8)!),
                  int.parse(m.group(9)!),
                ),
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// `ideviceimagemounter list -x`: signatures of mounted images.
  static int mountedImageCount(Object? plist) {
    if (plist is! Map<String, Object?>) return 0;
    final sigs = plist['ImageSignature'];
    return sigs is List ? sigs.length : 0;
  }

  /// `idevicedevmodectl list`: `<udid>  enabled|disabled`.
  static bool? developerMode(String output, String udid) {
    for (final line in output.split('\n')) {
      if (!line.contains(udid)) continue;
      final l = line.toLowerCase();
      if (l.contains('disabled')) return false;
      if (l.contains('enabled')) return true;
    }
    return null;
  }
}

/// One update from `idevicerestore -P`.
sealed class RestoreEvent {
  const RestoreEvent();
}

class RestoreProgressEvent extends RestoreEvent {
  const RestoreProgressEvent(this.step, this.fraction);

  final RestoreStep step;
  final double fraction;
}

class RestoreLogEvent extends RestoreEvent {
  const RestoreLogEvent(this.line, {this.isError = false});

  final String line;
  final bool isError;
}

class RestoreFinishedEvent extends RestoreEvent {
  const RestoreFinishedEvent({required this.success});

  final bool success;
}

abstract final class RestoreOutputParser {
  static final _progress = RegExp(r'^progress:\s*(\d+)\s+([\d.]+)');

  static RestoreEvent? parse(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;
    final m = _progress.firstMatch(line);
    if (m != null) {
      final step = RestoreStep.fromIndex(int.parse(m.group(1)!));
      if (step == null) return null;
      final f = double.tryParse(m.group(2)!) ?? 0;
      return RestoreProgressEvent(step, f.clamp(0.0, 1.0));
    }
    if (line == 'DONE') return const RestoreFinishedEvent(success: true);
    if (line == 'RESTORE FAILED') {
      return const RestoreFinishedEvent(success: false);
    }
    final upper = line.toUpperCase();
    return RestoreLogEvent(
      line,
      isError:
          upper.startsWith('ERROR') ||
          upper.contains('FAILED') ||
          upper.startsWith('UNABLE'),
    );
  }
}
