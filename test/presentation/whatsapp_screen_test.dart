import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/device_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/whatsapp_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/whatsapp/whatsapp_screen.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_parser.dart';

void main() {
  Future<void> show(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1180, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HudTheme.dark(),
          home: const Scaffold(body: WhatsAppScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('empty state until a backup is chosen', (tester) async {
    await show(
      tester,
      ProviderContainer(
        overrides: [appSupportDirProvider.overrideWithValue('/tmp/hk_support')],
      ),
    );
    expect(find.text('Decrypt and read WhatsApp chats'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Key file'), findsNothing); // only for encrypted backups
  });

  testWidgets('From iPhone prompts to connect a device when none is paired', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
        downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
        devicesProvider.overrideWith(_NoDevices.new), // no polling timer
      ],
    );
    await show(tester, container);
    container.read(waSourceModeProvider.notifier).set(WaSourceMode.iphone);
    await tester.pump();
    expect(find.textContaining('Connect and trust an iPhone'), findsOneWidget);
    expect(find.text('Read WhatsApp from an iPhone'), findsOneWidget);
  });

  testWidgets('shows chats and messages once inputs are ready', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
        // Override only the async archive; a plain .db path makes inputs ready.
        waArchiveProvider.overrideWith(
          (ref) async => WaParser.parseFile('test/fixtures/wa_msgstore.db'),
        ),
      ],
    );
    await show(tester, container);
    container
        .read(waInputsProvider.notifier)
        .setDb('test/fixtures/wa_msgstore.db');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('2 chats · 4 messages'), findsOneWidget);
    expect(find.text('Family Group'), findsWidgets);
    expect(find.text('Export HTML'), findsOneWidget);

    await tester.tap(find.text('+15551234567').first);
    await tester.pump();
    expect(find.text('Hello from Android'), findsOneWidget);
    expect(find.text('Reply from me'), findsOneWidget);
  });
}

class _NoDevices extends DevicesController {
  @override
  DevicesState build() => const DevicesState();
}
