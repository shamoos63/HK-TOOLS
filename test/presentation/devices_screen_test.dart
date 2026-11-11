import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/presentation/providers/catalog_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/device_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/repository_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/devices/devices_screen.dart';
import 'package:hk_ipsw_manager/presentation/widgets/hud_widgets.dart';
import 'package:hk_ipsw_manager/services/catalog/catalog_index.dart';
import 'package:hk_ipsw_manager/services/device/device_parsers.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:hk_ipsw_manager/services/repository/repository_inventory.dart';
import 'package:hk_ipsw_manager/services/restore/restore_runner.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(targetDirectory: '/tmp/hk_repo');
}

class _Devices extends DevicesController {
  _Devices(this.fixed);

  final DevicesState fixed;

  @override
  DevicesState build() => fixed;
}

/// Pretends every tool is installed without touching the filesystem.
class _AllTools extends DeviceToolchain {
  @override
  String? resolve(DeviceTool tool) => '/fake/${tool.executable}';
}

class _Icons extends AppIconsController {
  @override
  Map<String, String> build() => const {};

  @override
  Future<void> ensure(
    Iterable<String> bundleIds, {
    ConnectedDevice? device,
  }) async {}
}

class _Restore extends RestoreController {
  _Restore(this.fixed);

  final RestoreState fixed;

  @override
  RestoreState build() => fixed;
}

const _info = DeviceInfo(
  raw: {'DeviceName': 'Test iPhone', 'ProductType': 'iPhone13,2'},
  name: 'Test iPhone',
  productType: 'iPhone13,2',
  productVersion: '18.0.1',
  buildVersion: '22A3370',
  serialNumber: 'F2LXXXXXXX',
  ecid: 0x1AB2C3,
  modelNumber: 'MGJ53',
  regionInfo: 'LL/A',
  activationState: 'Activated',
);

const _phone = ConnectedDevice(
  id: '00008101-000A1C3E0C38001E',
  udid: '00008101-000A1C3E0C38001E',
  mode: DeviceMode.normal,
  connection: DeviceConnection.usb,
  name: 'Test iPhone',
  productType: 'iPhone13,2',
  pairState: PairState.paired,
  info: _info,
);

const _dfu = ConnectedDevice(
  id: 'ecid:1ab2c3',
  ecid: 0x1AB2C3,
  mode: DeviceMode.dfu,
  connection: DeviceConnection.usb,
  productType: 'iPad13,4',
  pairState: PairState.paired,
  recoveryInfo: {'MODE': 'DFU', 'PRODUCT': 'iPad13,4', 'CPID': '0x8103'},
);

Widget _app(
  DevicesState state, {
  DeviceTab tab = DeviceTab.overview,
  RestoreState restore = const RestoreState(),
}) => ProviderScope(
  overrides: [
    appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
    downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
    settingsProvider.overrideWith(_Settings.new),
    deviceToolchainProvider.overrideWithValue(_AllTools()),
    devicesProvider.overrideWith(() => _Devices(state)),
    restoreProvider.overrideWith(() => _Restore(restore)),
    catalogIndexProvider.overrideWithValue(CatalogIndex.empty),
    inventoryProvider.overrideWithValue(
      RepositoryInventory.analyze('/tmp/hk_repo', const [], CatalogIndex.empty),
    ),
    deviceTabProvider.overrideWith(() => ValueController(tab)),
    deviceImageProvider.overrideWith((ref, key) async => null),
    appIconsProvider.overrideWith(_Icons.new),
    deviceSetupDoneProvider.overrideWith((ref, id) async => false),
    deviceBatteryProvider.overrideWith(
      (ref, id) async => const BatteryInfo(
        level: 86,
        cycleCount: 412,
        designCapacity: 2815,
        maxCapacity: 2443,
        temperatureC: 30.5,
        voltage: 4.1,
      ),
    ),
    deviceStorageProvider.overrideWith(
      (ref, id) async => const StorageInfo(
        totalDisk: 128000000000,
        totalData: 110000000000,
        availableData: 32000000000,
      ),
    ),
    deviceAppsProvider.overrideWith(
      (ref, key) async => const [
        InstalledApp(
          bundleId: 'com.example.app',
          name: 'Example',
          version: '1.2',
        ),
      ],
    ),
    deviceDirectoryProvider.overrideWith(
      (ref, key) async => const [
        AfcEntry(name: 'DCIM', path: '/DCIM', isDirectory: true),
        AfcEntry(
          name: 'notes.txt',
          path: '/notes.txt',
          isDirectory: false,
          size: 42,
        ),
      ],
    ),
  ],
  child: MaterialApp(
    theme: HudTheme.dark(),
    home: const Scaffold(body: DevicesScreen()),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pump(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(944, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('empty state', (tester) async {
    await pump(tester, _app(const DevicesState()));
    expect(find.text('Waiting for a device'), findsOneWidget);
  });

  testWidgets('tools missing', (tester) async {
    await pump(tester, _app(const DevicesState(toolsMissing: true)));
    expect(find.text('Device tools not found'), findsOneWidget);
  });

  for (final tab in DeviceTab.values) {
    testWidgets('booted device renders ${tab.name} tab', (tester) async {
      await pump(tester, _app(const DevicesState(devices: [_phone]), tab: tab));
      expect(tester.takeException(), isNull);
      expect(find.text(tab.label), findsWidgets);
    });
  }

  testWidgets('unactivated device offers Activate', (tester) async {
    final fresh = ConnectedDevice(
      id: _phone.id,
      udid: _phone.udid,
      mode: DeviceMode.normal,
      connection: DeviceConnection.usb,
      pairState: PairState.paired,
      info: DeviceInfo(
        raw: const {},
        name: 'iPhone',
        productType: 'iPhone13,2',
        activationState: 'Unactivated',
      ),
    );
    await pump(tester, _app(DevicesState(devices: [fresh])));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Activate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Activation & Setup'), findsOneWidget);
    expect(find.text('Unactivated'), findsWidgets);
    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('In Setup Assistant'), findsOneWidget);
  });

  testWidgets('factory reset requires typing ERASE', (tester) async {
    await pump(tester, _app(const DevicesState(devices: [_phone])));
    final button = find.text('Factory reset');
    await tester.ensureVisible(button);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(button);
    // PulseDot animates forever, so pump fixed frames instead of settling.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Factory reset Test iPhone?'), findsOneWidget);
    NeonButton erase() => tester.widget<NeonButton>(
      find.widgetWithText(NeonButton, 'Erase device'),
    );
    expect(erase().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pump();
    expect(erase().onPressed, isNotNull);
  });

  testWidgets('DFU device offers flashing only', (tester) async {
    await pump(tester, _app(const DevicesState(devices: [_dfu])));
    expect(tester.takeException(), isNull);
    expect(find.text('Flash firmware'), findsOneWidget);
    expect(find.text('Exit Recovery'), findsNothing);
  });

  testWidgets('restore progress view', (tester) async {
    await pump(
      tester,
      _app(
        const DevicesState(devices: [_phone], polling: false),
        tab: DeviceTab.restore,
        restore: RestoreState(
          status: JobStatus.running,
          request: const RestoreRequest(
            ipswPath: '/tmp/fw.ipsw',
            device: _phone,
            erase: true,
            cacheDirectory: '/tmp/cache',
          ),
          step: RestoreStep.uploadFilesystem,
          fraction: 0.4,
          stepsSeen: const [RestoreStep.prepare, RestoreStep.uploadFilesystem],
          startedAt: DateTime(2026),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Erase and restore'), findsOneWidget);
    expect(find.text('Installing iOS'), findsWidgets);
    // Overall progress, not the step's own 40%.
    expect(find.text('34%'), findsOneWidget);
    // The raw log stays hidden until asked for.
    await tester.scrollUntilVisible(
      find.text('Show technical details'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Show technical details'), findsOneWidget);
  });

  testWidgets('failed restore explains what happened', (tester) async {
    await pump(
      tester,
      _app(
        const DevicesState(),
        restore: RestoreState(
          status: JobStatus.failed,
          request: const RestoreRequest(
            ipswPath: '/tmp/fw.ipsw',
            device: _phone,
            erase: false,
            cacheDirectory: '/tmp/cache',
          ),
          step: RestoreStep.detect,
          log: const [
            RestoreLogEvent(
              'ERROR: Unable to get SHSH blobs for this device',
              isError: true,
            ),
          ],
          startedAt: DateTime(2026),
          finishedAt: DateTime(2026),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Restore failed'), findsOneWidget);
    expect(find.text('Apple is not approving this firmware'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
