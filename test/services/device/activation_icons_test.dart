import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/utils/plist.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/services/device/app_icon_service.dart';
import 'package:hk_ipsw_manager/services/device/device_service.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:hk_ipsw_manager/services/device/setup_assistant.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('setup failures', () {
    test('terminal prompts are explained', () {
      expect(
        describeSetupFailure(
          'Exception: NoConsoleScreenBufferError: No Windows console found.',
          command: 'activation',
        ),
        contains('Activation Lock is on'),
      );
      expect(
        describeSetupFailure('EOFError', command: 'profile'),
        contains('asked for input'),
      );
      expect(
        describeSetupFailure('ERROR something else', command: 'apps'),
        isNull,
      );
    });
  });

  group('setup assistant config', () {
    test('kept groups are not skipped; plist round-trips', () {
      final skip = skipPanes(keep: {SetupPaneGroup.wifi});
      expect(skip, contains('Welcome'));
      expect(skip, contains('AppleID'));
      expect(skip, isNot(contains('WiFi')));
      final cfg = parsePlistDict(cloudConfigurationPlist(skip));
      expect(cfg['IsSupervised'], isFalse);
      expect(cfg['CloudConfigurationUIComplete'], isTrue);
      expect(cfg['SkipSetup'], skip);
    });

    test('activation lock is explained, never bypassed', () {
      expect(
        friendlySetupError(
          'MobileActivationException: Device is iCloud locked',
        ),
        contains('owner\'s Apple ID'),
      );
      expect(
        friendlySetupError('CloudConfigurationAlreadyPresentError'),
        contains('Erase'),
      );
    });
  });

  group('app icons', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('hk_icons_'));
    tearDown(() => dir.delete(recursive: true));

    test('batched lookup, resized artwork, device fallback', () async {
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        if (req.url.host == 'itunes.apple.com') {
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'bundleId': 'net.whatsapp.WhatsApp',
                  'artworkUrl512': 'https://is1-ssl.mzstatic.com/image/thumb/x/AppIcon.png/512x512bb.jpg',
                },
              ],
            }),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      });
      final svc = AppIconService(cacheDir: dir.path, client: client);
      final got = <String, String>{};
      final deviceAsked = <String>[];
      final left = await svc.resolve(
        ['net.whatsapp.WhatsApp', 'com.apple.mobilesafari'],
        onIcon: (id, path) => got[id] = path,
        countries: ['us'],
        fromDevice: (id, out) async {
          deviceAsked.add(id);
          await File(out).writeAsBytes([9]);
        },
      );
      expect(left, isEmpty);
      expect(
        got.keys,
        containsAll(['net.whatsapp.WhatsApp', 'com.apple.mobilesafari']),
      );
      expect(deviceAsked, ['com.apple.mobilesafari']);
      expect(
        requests.first.queryParameters['bundleId'],
        'net.whatsapp.WhatsApp,com.apple.mobilesafari',
      );
      expect(requests[1].path, endsWith('/256x256bb.png'));
      expect(svc.cached('net.whatsapp.WhatsApp'), isNotNull);
    });
  });

  group('pymobiledevice3 commands', () {
    late Directory dir;
    const device = ConnectedDevice(
      id: 'u',
      udid: '00008101-000A1C3E0C38001E',
      mode: DeviceMode.normal,
      connection: DeviceConnection.usb,
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hk_pmd3_');
      final f = File(p.join(dir.path, 'pymobiledevice3'));
      await f.writeAsString(r'''#!/bin/sh
echo "$@" >> "$(dirname "$0")/calls.txt"
case "$1 $2" in
  "activation activate")
    [ -f "$(dirname "$0")/locked" ] && { echo "2026 host pymobiledevice3 ERROR Device is iCloud locked" >&2; exit 1; }
    [ -f "$(dirname "$0")/prompt" ] && { echo "Activation Lock"; echo "Exception: NoConsoleScreenBufferError: No Windows console found. Are you running cmd.exe?" >&2; exit 1; }
    exit 0 ;;
  "profile cloud-configuration") cp "$3" "$(dirname "$0")/applied.plist" ;;
esac
''');
      await Process.run('chmod', ['+x', f.path]);
    });
    tearDown(() => dir.delete(recursive: true));

    test('activate and skip setup pass the udid and the plist', () async {
      final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
      await svc.activate(device);
      await svc.skipSetup(device, skipPanes(keep: const {}));
      final calls = File(p.join(dir.path, 'calls.txt')).readAsLinesSync();
      expect(calls.first, 'activation activate --now --udid ${device.udid}');
      expect(calls.last, startsWith('profile cloud-configuration '));
      final applied = parsePlistDict(
        File(p.join(dir.path, 'applied.plist')).readAsStringSync(),
      );
      expect(applied['SkipSetup'], contains('Passcode'));
    });

    test('factory reset keeps or drops the data plan', () async {
      final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
      await svc.factoryReset(device);
      await svc.factoryReset(device, preserveDataPlan: false);
      final calls = File(p.join(dir.path, 'calls.txt')).readAsLinesSync();
      expect(
        calls[0],
        'profile erase-device --preserve-data-plan --udid ${device.udid}',
      );
      expect(
        calls[1],
        startsWith('profile erase-device --no-preserve-data-plan'),
      );
    });

    test('Apple ID prompt during activation means Activation Lock', () async {
      // What Windows shows when pymobiledevice3 tries to ask for the owner's
      // Apple ID without a console.
      File(p.join(dir.path, 'prompt')).writeAsStringSync('');
      final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
      expect(
        () => svc.activate(device),
        throwsA(predicate((e) => '$e'.contains('Activation Lock is on'))),
      );
    });

    test('activation lock surfaces a clear message', () async {
      File(p.join(dir.path, 'locked')).writeAsStringSync('');
      final svc = DeviceService(DeviceToolchain(customDirectory: dir.path));
      expect(
        () => svc.activate(device),
        throwsA(predicate((e) => '$e'.contains('Activation Lock is on'))),
      );
    });
  }, skip: Platform.isWindows ? 'shell-script fakes' : false);
}
