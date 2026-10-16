import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/presentation/widgets/hud_widgets.dart';

Widget _wrap(bool reduced) => MaterialApp(
  home: HudEffects(
    reduced: reduced,
    child: const HudBackground(
      child: Center(child: GlassPanel(child: Text('panel'))),
    ),
  ),
);

void main() {
  testWidgets('full effects use backdrop blur and glows', (tester) async {
    await tester.pumpWidget(_wrap(false));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('panel'), findsOneWidget);
  });

  testWidgets('reduced effects: solid panel, no blur, no glows', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(true));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('panel'), findsOneWidget);
    // Only the grid painter remains in the backdrop (no radial glows).
    final gradients = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => (c.decoration as BoxDecoration?)?.gradient != null);
    expect(gradients, isEmpty);
  });

  test('defaults: on for Windows only, overridable, persisted', () {
    const s = AppSettings(targetDirectory: '/x', reducedEffects: true);
    expect(s.effectiveReducedEffects, isTrue);
    final back = AppSettings.fromJson(s.toJson(), fallbackTarget: '/x');
    expect(back.reducedEffects, isTrue);
    expect(back.copyWith(reducedEffects: () => null).reducedEffects, isNull);
  });
}
