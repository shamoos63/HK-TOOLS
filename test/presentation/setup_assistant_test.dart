import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/providers/setup_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/setup/setup_assistant.dart';
import 'package:hk_ipsw_manager/presentation/widgets/hud_widgets.dart';
import 'package:hk_ipsw_manager/services/setup/dependency_manager.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(targetDirectory: '/tmp/fw');
}

void main() {
  testWidgets('lists missing items, pre-selects installable ones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          dependencyStatusProvider.overrideWith(
            (ref) async => const [
              DependencyStatus(
                dependency: Dependency.appleDeviceSupport,
                installed: false,
                detail: 'Not installed',
                canInstall: true,
              ),
              DependencyStatus(
                dependency: Dependency.deviceTools,
                installed: true,
                detail: r'C:\Users\x\AppData\Local\HK Tools\tools',
              ),
              DependencyStatus(
                dependency: Dependency.recoveryTools,
                installed: false,
                manualHint: 'Build them with the included workflow.',
              ),
              DependencyStatus(
                dependency: Dependency.ipatool,
                installed: false,
                canInstall: true,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: HudTheme.dark(),
          home: const Scaffold(body: SetupAssistantDialog()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('Apple device drivers'), findsOneWidget);
    expect(find.text('Build them with the included workflow.'), findsOneWidget);
    final install = tester.widget<NeonButton>(
      find.widgetWithText(NeonButton, 'Install selected (2)'),
    );
    expect(install.onPressed, isNotNull);

    // Unticking one updates the count.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Install selected (1)'), findsOneWidget);
  });
}
