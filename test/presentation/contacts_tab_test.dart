import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/devices/contacts_tab.dart';
import 'package:hk_ipsw_manager/services/device/contacts_service.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(targetDirectory: '/tmp/fw');
}

const _device = ConnectedDevice(
  id: 'u',
  udid: '00008101-000A1C3E0C38001E',
  mode: DeviceMode.normal,
  connection: DeviceConnection.usb,
  pairState: PairState.paired,
);

void main() {
  testWidgets('lists contacts, shows details and duplicates', (tester) async {
    tester.view.physicalSize = const Size(944, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
          downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
          settingsProvider.overrideWith(_Settings.new),
          contactsSourcesProvider.overrideWith(
            (ref, udid) async => [
              ContactsSource(
                directory: '/tmp/bk/$udid',
                origin: 'HK Tools',
                date: DateTime(2026, 10, 10, 12),
              ),
            ],
          ),
          contactsProvider.overrideWith(
            (ref, dir) async => const [
              Contact(
                id: 1,
                first: 'Hisham',
                last: 'Khateeb',
                organization: 'HK',
                phones: [LabeledValue('Mobile', '+962 79 123 4567')],
                emails: [LabeledValue('Home', 'h@example.com')],
              ),
              Contact(
                id: 2,
                first: 'Sam',
                last: 'Lee',
                phones: [LabeledValue('Mobile', '0791234567')],
              ),
              Contact(id: 3, organization: 'Acme'),
            ],
          ),
        ],
        child: MaterialApp(
          theme: HudTheme.dark(),
          home: const Scaffold(body: ContactsTab(device: _device)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('HK Tools backup · 2026-10-10 12:00'),
      findsOneWidget,
    );
    expect(find.text('All 3'), findsOneWidget);
    expect(find.text('Duplicates 2'), findsOneWidget);

    await tester.tap(find.text('Hisham Khateeb'));
    await tester.pump();
    expect(find.text('h@example.com'), findsWidgets);
    expect(find.text('POSSIBLE DUPLICATES'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pump();
    // The list narrows to Acme; Sam Lee stays visible only in Hisham's
    // "possible duplicates" panel.
    expect(find.text('1 shown'), findsOneWidget);
    expect(find.text('Acme'), findsWidgets);
    expect(find.text('Sam Lee'), findsOneWidget);
  });
}
