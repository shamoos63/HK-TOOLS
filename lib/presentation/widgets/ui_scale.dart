import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Scales the whole interface by [scale] (Settings › Interface size), and
/// further when the window is smaller than the layout's design minimum, so
/// nothing overflows on small or high-DPI screens.
///
/// The child is laid out at `window / scale` logical pixels and drawn scaled
/// back to the window: text stays sharp because Flutter rasterizes after the
/// transform, and hit-testing follows the transform.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  /// Content size the screens are designed and tested for (sidebar + panes).
  static const designMinimum = Size(1180, 700);

  static double effective(double scale, Size window) => math.max(
    0.6,
    math.min(
      scale,
      math.min(
        window.width / designMinimum.width,
        window.height / designMinimum.height,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final window = c.biggest;
      final s = effective(scale, window);
      if ((s - 1).abs() < 0.001) return child;
      final size = Size(window.width / s, window.height / s);
      final mq = MediaQuery.of(context);
      return FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: mq.copyWith(
              size: size,
              padding: mq.padding / s,
              viewPadding: mq.viewPadding / s,
              viewInsets: mq.viewInsets / s,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
