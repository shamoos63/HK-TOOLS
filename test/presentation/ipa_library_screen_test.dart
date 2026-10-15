import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/device_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/ipa_library_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/ipa_library/ipa_library_screen.dart';
import 'package:hk_ipsw_manager/services/appstore/ipa_library.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() =>
      const AppSettings(targetDirectory: '/tmp/fw', ipaDirectory: '/tmp/ipas');
}

class _Library extends IpaLibraryController {
  @override
  Future<List<IpaInfo>> build() async => [
    IpaInfo(
      path: '/tmp/ipas/xvpn_43.3.3.ipa',
      size: 80 << 20,
      modified: DateTime(2026, 10, 1),
      bundleId: 'com.xvpn',
      name: 'X-VPN',
      version: '43.3.3',
      itemId: 1250312807,
    ),
    IpaInfo(
      path: '/tmp/ipas/xvpn_43.2.0.ipa',
      size: 79 << 20,
      modified: DateTime(2026, 9, 1),
      bundleId: 'com.xvpn',
      name: 'X-VPN',
      version: '43.2.0',
    ),
    IpaInfo(
      path: '/tmp/ipas/tg.ipa',
      size: 120 << 20,
      modified: DateTime(2026, 9, 5),
      bundleId: 'ph.telegra.Telegraph',
      name: 'Telegram',
      version: '12.0',
    ),
    IpaInfo(
      path: '/tmp/ipas/broken.ipa',
      size: 10,
      modified: DateTime(2026),
      error: 'Not a ZIP archive',
    ),
  ];
}

class _Devices extends DevicesController {
  @override
  DevicesState build() => const DevicesState();
}

class _Icons extends AppIconsController {
  @override
  Map<String, String> build() => const {};

  @override
  Future<void> ensure(Iterable<String> ids, {ConnectedDevice? device}) async {}
}

void main() {
  testWidgets('groups versions, flags updates and junk files', (tester) async {
    tester.view.physicalSize = const Size(944, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
          downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
          settingsProvider.overrideWith(_Settings.new),
          ipaLibraryProvider.overrideWith(_Library.new),
          devicesProvider.overrideWith(_Devices.new),
          appIconsProvider.overrideWith(_Icons.new),
          libraryListingsProvider.overrideWith(
            (ref) async => const {
              'com.xvpn': StoreListing(
                bundleId: 'com.xvpn',
                trackId: 1250312807,
                version: '43.4.0',
              ),
              'ph.telegra.Telegraph': StoreListing(
                bundleId: 'ph.telegra.Telegraph',
                trackId: 686449807,
                version: '12.0',
              ),
            },
          ),
        ],
        child: MaterialApp(
          theme: HudTheme.dark(),
          home: const Scaffold(body: IpaLibraryScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('X-VPN'), findsOneWidget);
    expect(find.text('v43.3.3 +1 older'), findsOneWidget);
    expect(find.text('Update 43.4.0'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Update all (1)'), findsOneWidget);
    expect(find.text('No device connected'), findsOneWidget);
    expect(
      find.textContaining('1 file(s) in the folder are not readable'),
      findsOneWidget,
    );

    await tester.tap(find.text('Updates 1'));
    await tester.pump();
    expect(find.text('Telegram'), findsNothing);
  });
}
