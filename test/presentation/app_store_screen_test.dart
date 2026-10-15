import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/presentation/providers/app_store_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/device_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/appstore/app_store_screen.dart';
import 'package:hk_ipsw_manager/services/appstore/app_store_service.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(targetDirectory: '/tmp/hk_repo');
}

class _Account extends StoreAccountController {
  _Account(this.account);

  final StoreAccount? account;

  @override
  Future<StoreAccount?> build() async => account;
}

class _Devices extends DevicesController {
  @override
  DevicesState build() => const DevicesState();
}

class _Downloads extends StoreDownloadsController {
  @override
  List<StoreDownload> build() => const [
    StoreDownload(
      id: '1',
      app: StoreApp(id: 1, bundleId: 'com.x', name: 'X App'),
      platform: StorePlatform.iphone,
      fraction: 0.4,
      detail: '4/10 MB',
    ),
    StoreDownload(
      id: '2',
      app: StoreApp(id: 2, bundleId: 'com.y', name: 'Y App'),
      platform: StorePlatform.iphone,
      status: StoreJobStatus.failed,
      error: 'Paid apps must be bought first',
    ),
  ];
}

Widget _app({StoreAccount? account, bool missing = false}) => ProviderScope(
  overrides: [
    appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
    downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
    settingsProvider.overrideWith(_Settings.new),
    appStoreToolMissingProvider.overrideWithValue(missing),
    storeAccountProvider.overrideWith(() => _Account(account)),
    devicesProvider.overrideWith(_Devices.new),
    storeDownloadsProvider.overrideWith(_Downloads.new),
  ],
  child: MaterialApp(
    theme: HudTheme.dark(),
    home: const Scaffold(body: AppStoreScreen()),
  ),
);

void main() {
  Future<void> pump(WidgetTester tester, Widget app) async {
    // Content area at the minimum window size (window minus sidebar).
    tester.view.physicalSize = const Size(944, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('signed out shows sign-in', (tester) async {
    await pump(tester, _app());
    expect(find.text('Sign in with Apple ID'), findsOneWidget);
    await tester.tap(find.text('Sign in with Apple ID'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to the App Store'), findsOneWidget);
    expect(find.textContaining('not stored'), findsOneWidget);
  });

  testWidgets('signed in shows search and downloads', (tester) async {
    await pump(
      tester,
      _app(
        account: const StoreAccount(email: 'h@example.com', name: 'Hisham'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Hisham'), findsOneWidget);
    expect(find.text('Search for an app'), findsOneWidget);
    expect(find.text('X App'), findsOneWidget);
    expect(find.text('4/10 MB'), findsOneWidget);
  });

  testWidgets('tool missing', (tester) async {
    await pump(tester, _app(missing: true));
    expect(find.text('ipatool not found'), findsOneWidget);
  });
}
