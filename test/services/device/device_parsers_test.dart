import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/utils/plist.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/services/device/device_parsers.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:hk_ipsw_manager/services/restore/restore_runner.dart';

String plist(String body) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
$body
</plist>
''';

void main() {
  group('plist', () {
    test('parses nested values and skips leading tool noise', () {
      final v = parsePlistDict(
        'WARNING: something\n${plist('''
<dict>
  <key>DeviceName</key><string>Hisham's iPhone</string>
  <key>UniqueChipID</key><integer>6447315029016622</integer>
  <key>PasswordProtected</key><true/>
  <key>Ratio</key><real>0.5</real>
  <key>List</key><array><string>a</string><integer>2</integer></array>
  <key>Blob</key><data>AQID</data>
</dict>''')}',
      );
      expect(v.str('DeviceName'), "Hisham's iPhone");
      expect(v.integer('UniqueChipID'), 6447315029016622);
      expect(v.boolean('PasswordProtected'), isTrue);
      expect(v.real('Ratio'), 0.5);
      expect(v['List'], ['a', 2]);
      expect(v['Blob'], [1, 2, 3]);
    });
  });

  group('discovery', () {
    test('udid list accepts plain and annotated lines', () {
      const out =
          '00008101-000A1C3E0C38001E\n'
          'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678 (Network)\n'
          'ERROR: something\n\n';
      expect(DeviceParsers.udids(out), [
        '00008101-000A1C3E0C38001E',
        'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
      ]);
    });

    test('irecovery query', () {
      final q = DeviceParsers.irecoveryQuery(
        'CPID: 0x8101\nCPRV: 0x11\nBDID: 0x0c\n'
        'ECID: 0x1AB2C3D4E5F6\nCPFM: 0x03\nSCEP: 0x01\n'
        'IBFL: 0x3c\nSRTG: iBoot-8419.0.42\nSNON: 0x00\n'
        'MODE: Recovery\nPRODUCT: iPhone13,2\nMODEL: d53gap\n'
        'NAME: iPhone 12\n',
      );
      expect(q['PRODUCT'], 'iPhone13,2');
      expect(DeviceMode.fromIrecovery(q['MODE']), DeviceMode.recovery);
      expect(DeviceMode.fromIrecovery('DFU'), DeviceMode.dfu);
      expect(DeviceParsers.ecid(q['ECID']), 0x1AB2C3D4E5F6);
      expect(DeviceParsers.ecid('6447315029016622'), 6447315029016622);
    });

    test('pair state from lockdown errors', () {
      expect(
        DeviceParsers.pairState(
          'ERROR: Could not connect to lockdownd: Pairing dialog response pending (-19)',
        ),
        PairState.pendingTrust,
      );
      expect(
        DeviceParsers.pairState(
          'Could not connect to lockdownd: Password protected (-17)',
        ),
        PairState.locked,
      );
      expect(
        DeviceParsers.pairState('User denied pairing (-18)'),
        PairState.denied,
      );
    });
  });

  group('device data', () {
    test('device info fields', () {
      final info = DeviceParsers.deviceInfo(
        parsePlistDict(
          plist('''<dict>
  <key>DeviceName</key><string>iPad</string>
  <key>ProductType</key><string>iPad13,4</string>
  <key>ProductVersion</key><string>18.0.1</string>
  <key>BuildVersion</key><string>22A3370</string>
  <key>ModelNumber</key><string>MHQR3</string>
  <key>RegionInfo</key><string>LL/A</string>
</dict>'''),
        ),
      );
      expect(info.productType, 'iPad13,4');
      expect(info.partNumber, 'MHQR3LL/A');
    });

    test('battery merges ioreg units and lockdown level', () {
      final b = DeviceParsers.battery(
        parsePlistDict(
          plist('''<dict><key>IORegistry</key><dict>
  <key>CycleCount</key><integer>412</integer>
  <key>DesignCapacity</key><integer>2815</integer>
  <key>AppleRawMaxCapacity</key><integer>2443</integer>
  <key>NominalChargeCapacity</key><integer>2500</integer>
  <key>CurrentCapacity</key><integer>87</integer>
  <key>Temperature</key><integer>3050</integer>
  <key>Voltage</key><integer>4123</integer>
  <key>InstantAmperage</key><integer>-310</integer>
  <key>IsCharging</key><false/>
</dict></dict>'''),
        ),
        parsePlistDict(
          plist('''<dict>
  <key>BatteryCurrentCapacity</key><integer>86</integer>
  <key>BatteryIsCharging</key><true/>
</dict>'''),
        ),
      );
      expect(b.level, 86);
      expect(b.isCharging, isTrue);
      expect(b.cycleCount, 412);
      // NominalChargeCapacity wins: it is what Settings › Battery shows.
      expect(b.maxCapacity, 2500);
      expect(b.healthPercent!.round(), 89);
      expect(b.temperatureC, closeTo(30.5, 0.001));
      expect(b.voltage, closeTo(4.123, 0.001));
      expect(b.amperage, -310);
    });

    test('battery figures nested in BatteryData (iOS 26 layout)', () {
      final b = DeviceParsers.battery(
        parsePlistDict(
          plist('''<dict><key>IORegistry</key><dict>
  <key>CycleCount</key><integer>633</integer>
  <key>MaxCapacity</key><integer>100</integer>
  <key>CurrentCapacity</key><integer>52</integer>
  <key>Voltage</key><integer>4035</integer>
  <key>IsCharging</key><true/>
  <key>BatteryData</key><dict>
    <key>DesignCapacity</key><integer>4395</integer>
    <key>NominalChargeCapacity</key><integer>3953</integer>
    <key>FullChargeCapacity</key><integer>4029</integer>
    <key>TrueRemainingCapacity</key><integer>2071</integer>
    <key>MaxCapacity</key><integer>100</integer>
  </dict>
</dict></dict>'''),
        ),
        null,
      );
      expect(b.level, 52);
      expect(b.cycleCount, 633);
      expect(b.designCapacity, 4395);
      expect(b.maxCapacity, 3953);
      expect(b.currentCapacity, 2071);
      expect(b.healthPercent!.round(), 90);
      expect(b.temperatureC, isNull);
    });

    test('storage', () {
      final s = DeviceParsers.storage(
        parsePlistDict(
          plist('''<dict>
  <key>TotalDiskCapacity</key><integer>128000000000</integer>
  <key>TotalDataCapacity</key><integer>110000000000</integer>
  <key>AmountDataAvailable</key><integer>32000000000</integer>
</dict>'''),
        ),
      )!;
      expect(s.used, 96000000000);
      expect(s.usedFraction, closeTo(0.75, 1e-9));
    });

    test('apps sorted by name, system flag', () {
      final apps = DeviceParsers.apps(
        parsePlistXml(
          plist('''<array>
  <dict><key>CFBundleIdentifier</key><string>com.z.app</string>
    <key>CFBundleDisplayName</key><string>Zed</string>
    <key>ApplicationType</key><string>User</string>
    <key>StaticDiskUsage</key><integer>100</integer>
    <key>DynamicDiskUsage</key><integer>50</integer>
    <key>UIFileSharingEnabled</key><true/></dict>
  <dict><key>CFBundleIdentifier</key><string>com.apple.mobilesafari</string>
    <key>CFBundleName</key><string>Safari</string>
    <key>ApplicationType</key><string>System</string></dict>
</array>'''),
        ),
      );
      expect(apps.map((a) => a.displayName), ['Safari', 'Zed']);
      expect(apps.first.isSystem, isTrue);
      expect(apps.last.totalSize, 150);
      expect(apps.last.fileSharing, isTrue);
    });

    test('afc ls -l listing', () {
      const out =
          '\x1B[36mdrwxr-xr-x   4 mobile mobile       128 05 Oct 2026 14:22:11 .\x1B[0m\n'
          'drwxr-xr-x   3 mobile mobile        96 05 Oct 2026 14:22:11 DCIM\n'
          '-rw-r--r--   1 mobile mobile   2483112 01 Sep 2026 09:05:00 IMG 0001.HEIC\n'
          'lrwxrwxrwx   1 mobile mobile        11 01 Sep 2026 09:05:00 link\n';
      final e = DeviceParsers.afcListing(out, '/DCIM');
      expect(e.map((x) => x.name), ['DCIM', 'IMG 0001.HEIC', 'link']);
      expect(e[0].isDirectory, isTrue);
      expect(e[1].size, 2483112);
      expect(e[1].path, '/DCIM/IMG 0001.HEIC');
      expect(e[1].modified, DateTime(2026, 9, 1, 9, 5));
      expect(e[2].isLink, isTrue);
    });
  });

  group('restore', () {
    test('progress, completion and errors', () {
      final p = RestoreOutputParser.parse('progress: 2 0.452000');
      expect(p, isA<RestoreProgressEvent>());
      p as RestoreProgressEvent;
      expect(p.step, RestoreStep.uploadFilesystem);
      expect(p.fraction, closeTo(0.452, 1e-9));

      expect(
        (RestoreOutputParser.parse('DONE') as RestoreFinishedEvent).success,
        isTrue,
      );
      expect(
        (RestoreOutputParser.parse(
          'RESTORE FAILED',
        ) as RestoreFinishedEvent).success,
        isFalse,
      );
      final err = RestoreOutputParser.parse(
        'ERROR: Unable to send TSS request',
      ) as RestoreLogEvent;
      expect(err.isError, isTrue);
      expect(RestoreOutputParser.parse('progress: 99 0.5'), isNull);
    });

    test('args target ECID in hex and never prompt', () {
      const device = ConnectedDevice(
        id: 'u',
        udid: '00008101-000A1C3E0C38001E',
        ecid: 0x1AB2C3D4E5F6,
        mode: DeviceMode.normal,
        connection: DeviceConnection.usb,
      );
      final args = RestoreRunner.buildArgs(
        const RestoreRequest(
          ipswPath: '/fw/iPhone13,2_18.0_22A3354_Restore.ipsw',
          device: device,
          erase: true,
          cacheDirectory: '/cache',
        ),
      );
      expect(args, [
        '-y',
        '-P',
        '-e',
        '-i',
        '0x1ab2c3d4e5f6',
        '-C',
        '/cache',
        '/fw/iPhone13,2_18.0_22A3354_Restore.ipsw',
      ]);

      final update = RestoreRunner.buildArgs(
        const RestoreRequest(
          ipswPath: '/a.ipsw',
          device: ConnectedDevice(
            id: 'u',
            udid: 'abc',
            mode: DeviceMode.normal,
            connection: DeviceConnection.usb,
          ),
          erase: false,
          cacheDirectory: '/c',
        ),
      );
      expect(update, isNot(contains('-e')));
      expect(update, containsAllInOrder(['-u', 'abc']));
    });
  });

  test('tool error message prefers ERROR lines', () {
    const r = ToolResult(
      1,
      'some info\n',
      'ERROR: Could not connect to lockdownd: Password protected (-17)\n',
    );
    expect(
      r.errorMessage,
      'Could not connect to lockdownd: Password protected (-17)',
    );
  });
}
