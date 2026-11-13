import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/presentation/providers/whatsapp_android_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/whatsapp_backup_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/whatsapp/whatsapp_android_restore_steps.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_android.dart';

void main() {
  Widget host(List<AndroidDevice> devices) => ProviderScope(
    overrides: [
      androidDevicesProvider.overrideWith((ref) => Stream.value(devices)),
      waBackupFlavorsProvider.overrideWith((ref, dir) async => [false, true]),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 900,
            child: WaAndroidRestoreSteps(backupDir: '/x'),
          ),
        ),
      ),
    ),
  );

  testWidgets('walks the steps: app → phone → number → restore', (t) async {
    t.view.physicalSize = const Size(1100, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(const [
        AndroidDevice(
          serial: 'S1',
          state: AndroidDeviceState.ready,
          model: 'SM_A566B',
        ),
      ]),
    );
    await t.pumpAndSettle();
    // Step 1 open: two big app tiles.
    expect(find.text('WhatsApp Business'), findsWidgets);
    await t.tap(find.text('The business app (green "B" icon)'));
    await t.pumpAndSettle();
    // Step 2 is done automatically (one phone connected) → step 3 open.
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), '+961 3 123456');
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    // Step 4: the big restore button.
    expect(find.textContaining('Restore to'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('waits for a phone', (t) async {
    t.view.physicalSize = const Size(1100, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(const []));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('The regular app'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Waiting for the phone…'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
