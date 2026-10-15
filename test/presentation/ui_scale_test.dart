import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/presentation/widgets/ui_scale.dart';

void main() {
  test('effective scale honours the setting and the design minimum', () {
    expect(UiScale.effective(0.9, const Size(1600, 1000)), 0.9);
    expect(UiScale.effective(1.0, const Size(1600, 1000)), 1.0);
    // 960 px wide window: content must still get 1180 logical px.
    expect(
      UiScale.effective(1.0, const Size(960, 800)),
      closeTo(960 / 1180, 1e-9),
    );
    expect(UiScale.effective(1.0, const Size(300, 200)), 0.6);
  });

  testWidgets('child is laid out at window / scale', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? seen;
    Size? mq;
    await tester.pumpWidget(
      UiScale(
        scale: 0.8,
        child: LayoutBuilder(
          builder: (context, c) {
            seen = c.biggest;
            mq = MediaQuery.sizeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final s = UiScale.effective(0.8, const Size(1000, 800));
    expect(seen!.width, closeTo(1000 / s, 0.01));
    expect(mq!.width, closeTo(1000 / s, 0.01));
  });
}
