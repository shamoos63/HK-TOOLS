import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/presentation/shell/window_chrome.dart';

void main() {
  setUp(() => debugForceWindowChrome = true);
  tearDown(() => debugForceWindowChrome = null);

  testWidgets('window buttons render; header fields keep their input', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: HudTheme.dark(),
        home: Scaffold(
          body: Stack(
            children: [
              WindowDragBackground(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 38, 24, 10),
                  child: TextField(focusNode: focus),
                ),
              ),
              const Positioned(top: 0, right: 0, child: WindowControls()),
            ],
          ),
        ),
      ),
    );

    expect(useCustomWindowChrome, isTrue);
    for (final tip in ['Minimize', 'Maximize', 'Close']) {
      expect(find.byTooltip(tip), findsOneWidget);
    }
    expect(
      tester.getSize(find.byType(WindowControls)),
      const Size(windowControlsWidth, 34),
    );

    // The drag layer sits behind the header: clicks on the field still land.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('no custom chrome when disabled', (tester) async {
    debugForceWindowChrome = false;
    await tester.pumpWidget(
      const MaterialApp(home: WindowDragArea(child: Text('logo'))),
    );
    expect(find.byType(GestureDetector), findsNothing);
  });
}
