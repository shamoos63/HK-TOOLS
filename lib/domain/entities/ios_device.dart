/// A device attached over USB or the network, in any mode the toolchain can
/// see: booted iOS (lockdown), Recovery, or DFU.
library;

import '../../core/l10n/l10n.dart';

enum DeviceMode {
  normal('Normal'),
  recovery('Recovery'),
  dfu('DFU'),
  restore('Restore'),
  unknown('Unknown');

  const DeviceMode(this._label);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);

  /// Booted OS reachable through lockdown (apps, files, backups, …).
  bool get isBooted => this == DeviceMode.normal;

  /// Low-level boot modes: only restore / reboot are possible.
  bool get isLowLevel =>
      this == DeviceMode.recovery ||
      this == DeviceMode.dfu ||
      this == DeviceMode.restore;

  /// Maps the `MODE:` value printed by `irecovery -q`.
  static DeviceMode fromIrecovery(String? mode) {
    final m = (mode ?? '').toLowerCase();
    if (m.contains('dfu') || m == 'wtf') return DeviceMode.dfu;
    if (m.contains('recovery') || m.contains('iboot')) {
      return DeviceMode.recovery;
    }
    if (m.contains('restore')) return DeviceMode.restore;
    return DeviceMode.unknown;
  }
}

enum DeviceConnection { usb, network }

/// Lockdown pairing state of a booted device.
enum PairState {
  paired,

  /// "Trust This Computer?" is showing on the device.
  pendingTrust,

  /// Device has a passcode and is locked; it must be unlocked to pair.
  locked,

  /// The user tapped "Don't Trust".
  denied,
  unknown,
}

/// Lockdown values for a booted device (`ideviceinfo -x`).
class DeviceInfo {
  const DeviceInfo({
    required this.raw,
    this.name,
    this.productType,
    this.productVersion,
    this.buildVersion,
    this.serialNumber,
    this.ecid,
    this.modelNumber,
    this.regionInfo,
    this.hardwareModel,
    this.cpuArchitecture,
    this.deviceClass,
    this.wifiAddress,
    this.bluetoothAddress,
    this.phoneNumber,
    this.imei,
    this.activationState,
    this.basebandVersion,
    this.passwordProtected,
  });

  final Map<String, Object?> raw;
  final String? name;

  /// Hardware identifier, e.g. `iPhone13,2`. Matches IPSW.me identifiers.
  final String? productType;
  final String? productVersion;
  final String? buildVersion;
  final String? serialNumber;
  final int? ecid;
  final String? modelNumber;
  final String? regionInfo;
  final String? hardwareModel;
  final String? cpuArchitecture;
  final String? deviceClass;
  final String? wifiAddress;
  final String? bluetoothAddress;
  final String? phoneNumber;
  final String? imei;
  final String? activationState;
  final String? basebandVersion;
  final bool? passwordProtected;

  /// `MLXX2` + `LL/A` → `MLXX2LL/A`, the part number printed on the box.
  String? get partNumber =>
      modelNumber == null ? null : '$modelNumber${regionInfo ?? ''}';
}

class ConnectedDevice {
  const ConnectedDevice({
    required this.id,
    required this.mode,
    required this.connection,
    this.udid,
    this.ecid,
    this.productType,
    this.name,
    this.pairState = PairState.unknown,
    this.pairError,
    this.info,
    this.recoveryInfo = const {},
  });

  /// UDID for booted devices; `ecid:<hex>` for Recovery/DFU devices, which do
  /// not expose a UDID.
  final String id;
  final DeviceMode mode;
  final DeviceConnection connection;
  final String? udid;
  final int? ecid;
  final String? productType;
  final String? name;
  final PairState pairState;
  final String? pairError;
  final DeviceInfo? info;

  /// `irecovery -q` key/values (CPID, BDID, ECID, MODE, PRODUCT, …).
  final Map<String, String> recoveryInfo;

  String get displayName =>
      name ?? info?.name ?? (productType != null ? productType! : (udid ?? id));

  String? get ecidHex =>
      ecid == null ? null : '0x${ecid!.toRadixString(16).toUpperCase()}';

  ConnectedDevice copyWith({
    PairState? pairState,
    String? Function()? pairError,
    DeviceInfo? Function()? info,
    String? name,
    String? productType,
    int? ecid,
  }) => ConnectedDevice(
    id: id,
    mode: mode,
    connection: connection,
    udid: udid,
    ecid: ecid ?? this.ecid,
    productType: productType ?? this.productType,
    name: name ?? this.name,
    pairState: pairState ?? this.pairState,
    pairError: pairError != null ? pairError() : this.pairError,
    info: info != null ? info() : this.info,
    recoveryInfo: recoveryInfo,
  );
}

/// Battery health from `idevicediagnostics ioregentry AppleSmartBattery`
/// merged with the lockdown battery domain.
class BatteryInfo {
  const BatteryInfo({
    this.level,
    this.isCharging,
    this.fullyCharged,
    this.externalConnected,
    this.cycleCount,
    this.designCapacity,
    this.maxCapacity,
    this.currentCapacity,
    this.temperatureC,
    this.voltage,
    this.amperage,
    this.serial,
  });

  /// State of charge, 0–100.
  final int? level;
  final bool? isCharging;
  final bool? fullyCharged;
  final bool? externalConnected;
  final int? cycleCount;

  /// mAh.
  final int? designCapacity;

  /// Full-charge capacity today, mAh.
  final int? maxCapacity;
  final int? currentCapacity;
  final double? temperatureC;

  /// Volts.
  final double? voltage;

  /// mA; negative while discharging.
  final int? amperage;
  final String? serial;

  /// Full-charge capacity relative to design capacity, 0–100+.
  double? get healthPercent => (designCapacity ?? 0) > 0 && maxCapacity != null
      ? maxCapacity! * 100 / designCapacity!
      : null;
}

/// `ideviceinfo -q com.apple.disk_usage`.
class StorageInfo {
  const StorageInfo({
    required this.totalDisk,
    required this.totalData,
    required this.availableData,
    this.totalSystem,
  });

  final int totalDisk;
  final int totalData;
  final int availableData;
  final int? totalSystem;

  int get used => totalDisk - availableData;
  double get usedFraction => totalDisk == 0 ? 0 : used / totalDisk;
}

class InstalledApp {
  const InstalledApp({
    required this.bundleId,
    this.name,
    this.version,
    this.build,
    this.type,
    this.staticSize,
    this.dynamicSize,
    this.fileSharing = false,
  });

  final String bundleId;
  final String? name;
  final String? version;
  final String? build;

  /// `User` or `System`.
  final String? type;
  final int? staticSize;
  final int? dynamicSize;

  /// UIFileSharingEnabled: its Documents folder is reachable over house_arrest.
  final bool fileSharing;

  String get displayName => (name == null || name!.isEmpty) ? bundleId : name!;
  int get totalSize => (staticSize ?? 0) + (dynamicSize ?? 0);
  bool get isSystem => type == 'System';
}

/// One entry from an AFC directory listing.
class AfcEntry {
  const AfcEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isLink = false,
    this.size = 0,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isLink;
  final int size;
  final DateTime? modified;
}

/// Phases reported by `idevicerestore -P` (`progress: <step> <fraction>`),
/// in the order of the RESTORE_STEP enum in idevicerestore.h.
enum RestoreStep {
  detect('Detecting device'),
  prepare('Preparing'),
  uploadFilesystem('Sending filesystem'),
  verifyFilesystem('Verifying filesystem'),
  flashFirmware('Flashing firmware'),
  flashBaseband('Flashing baseband'),
  firmwareUpdate('Updating peripherals'),
  uploadImage('Uploading images');

  const RestoreStep(this._label);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);

  static RestoreStep? fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : null;
}
