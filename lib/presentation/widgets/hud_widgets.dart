import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/hud_theme.dart';

/// Turns off the GPU-heavy decoration (background glows, live blur behind
/// glass panels) below it: Settings › Interface › Reduced visual effects.
class HudEffects extends InheritedWidget {
  const HudEffects({super.key, required this.reduced, required super.child});

  final bool reduced;

  static bool reducedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HudEffects>()?.reduced ??
      false;

  @override
  bool updateShouldNotify(HudEffects old) => old.reduced != reduced;
}

/// App backdrop: flat graphite with a faint accent wash at the top.
class HudBackground extends StatelessWidget {
  const HudBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = HudEffects.reducedOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HudColors.background,
        gradient: reduced
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    HudColors.cyan.withValues(alpha: 0.05),
                    HudColors.background,
                  ),
                  HudColors.background,
                ],
                stops: const [0, 0.45],
              ),
      ),
      child: child,
    );
  }
}

/// Card surface: solid fill, hairline border, soft shadow.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 14,
    this.glow = false,
    this.borderColor,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Lifts the card a little (focus, hero cards).
  final bool glow;
  final Color? borderColor;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final reduced = HudEffects.reducedOf(context);
    return Container(
      decoration: BoxDecoration(
        color: tint == null
            ? HudColors.surface
            : Color.alphaBlend(
                tint!.withValues(alpha: 0.06),
                HudColors.surface,
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? HudColors.glassBorder),
        boxShadow: reduced
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: glow ? 0.35 : 0.18),
                  blurRadius: glow ? 28 : 12,
                  offset: Offset(0, glow ? 10 : 4),
                ),
              ],
      ),
      // Ink (list tiles, hover highlights) paints on the nearest Material;
      // without this one the opaque card would hide it.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

enum NeonVariant { primary, ghost, danger }

class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = NeonVariant.primary,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NeonVariant variant;
  final bool compact;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = switch (widget.variant) {
      NeonVariant.danger => HudColors.danger,
      _ => HudColors.cyan,
    };
    final primary = widget.variant == NeonVariant.primary;
    final fg = !enabled
        ? HudColors.textMuted
        : primary
        ? Colors.white
        : accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 16,
            vertical: widget.compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: primary && enabled
                ? Color.lerp(accent, Colors.white, _hover ? 0.12 : 0)
                : enabled
                ? accent.withValues(alpha: _hover ? 0.16 : 0.10)
                : HudColors.overlay.withValues(alpha: 0.04),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.compact ? 15 : 17, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: widget.compact ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted label ("SIGNED", "SHARED ×3", status pills).
class HudPill extends StatelessWidget {
  const HudPill(
    this.label, {
    super.key,
    Color? color,
    this.icon,
    this.mono = true,
  }) : _color = color;

  final String label;
  final Color? _color;
  Color get color => _color ?? HudColors.cyan;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Breathing status dot.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, Color? color, this.size = 8, this.active = true})
    : _color = color;

  final Color? _color;
  Color get color => _color ?? HudColors.success;
  final double size;
  final bool active;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = widget.active ? _c.value : 0.0;
        return SizedBox.square(
          dimension: widget.size * 2.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * (1 + 1.4 * t),
                height: widget.size * (1 + 1.4 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gradient progress bar with a glowing leading edge.
class GlowProgressBar extends StatelessWidget {
  const GlowProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    List<Color>? colors,
    this.dimmed = false,
  }) : _colors = colors;

  final double value;
  final double height;
  final List<Color>? _colors;
  List<Color> get colors =>
      _colors ??
      [HudColors.cyan, Color.lerp(HudColors.cyan, Colors.white, 0.3)!];
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (_, v, _) => Container(
        height: height,
        decoration: BoxDecoration(
          color: HudColors.overlay.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(height),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(
                colors: [
                  for (final c in colors)
                    dimmed ? c.withValues(alpha: 0.35) : c,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini area chart for bandwidth history.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, Color? color})
    : _color = color;

  final List<double> values;
  final Color? _color;
  Color get color => _color ?? HudColors.cyan;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparkPainter(values, color), size: Size.infinite);
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = math.max(values.reduce(math.max), 1.0);
    final dx = size.width / (values.length - 1);
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - (values[i] / peak) * (size.height - 4) - 2;
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values;
}

/// Uppercase spaced label used for panel headers.
class HudLabel extends StatelessWidget {
  const HudLabel(this.text, {super.key, Color? color}) : _color = color;

  final String text;
  final Color? _color;
  Color get color => _color ?? HudColors.textMuted;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
  );
}

class HudIconButton extends StatelessWidget {
  const HudIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    Color? color,
  }) : _color = color;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? _color;
  Color get color => _color ?? HudColors.textMuted;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    color: color,
    hoverColor: HudColors.overlay.withValues(alpha: 0.06),
    disabledColor: HudColors.textMuted.withValues(alpha: 0.3),
    visualDensity: VisualDensity.compact,
    splashRadius: 18,
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: HudColors.textMuted.withValues(alpha: 0.6)),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 380,
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: HudColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ],
    ),
  );
}
