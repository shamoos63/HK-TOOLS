import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/hud_theme.dart';

/// App backdrop: OLED base, faint telemetry grid and two soft neon glows.
class HudBackground extends StatelessWidget {
  const HudBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: HudColors.background),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned(
            left: -220,
            top: -260,
            child: _Glow(
              color: HudColors.cyan.withValues(alpha: 0.10),
              size: 620,
            ),
          ),
          Positioned(
            right: -260,
            bottom: -300,
            child: _Glow(
              color: HudColors.purple.withValues(alpha: 0.14),
              size: 720,
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HudColors.cyan.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 36.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Frosted glass container with a micro-glow border.
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
  final bool glow;
  final Color? borderColor;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? HudColors.glassBorder;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: border.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border, width: 1),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (tint ?? Colors.white).withValues(alpha: 0.06),
                  (tint ?? Colors.white).withValues(alpha: 0.02),
                ],
              ),
            ),
            child: child,
          ),
        ),
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
        ? HudColors.background
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
            borderRadius: BorderRadius.circular(9),
            gradient: primary && enabled
                ? const LinearGradient(
                    colors: [
                      HudColors.cyan,
                      Color(0xFF4F7BFF),
                      HudColors.purple,
                    ],
                  )
                : null,
            color: primary && enabled
                ? null
                : accent.withValues(alpha: _hover && enabled ? 0.14 : 0.06),
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: primary ? 0 : 0.5)
                  : HudColors.glassBorder,
            ),
            boxShadow: enabled && (_hover || primary)
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: _hover ? 0.45 : 0.22),
                      blurRadius: _hover ? 18 : 10,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
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
                  letterSpacing: 0.3,
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
    this.color = HudColors.cyan,
    this.icon,
    this.mono = true,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
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
            style: mono
                ? HudTheme.telemetry(size: 11, color: color)
                : TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Breathing status dot.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    this.color = HudColors.success,
    this.size = 8,
    this.active = true,
  });

  final Color color;
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
                  boxShadow: [BoxShadow(color: widget.color, blurRadius: 6)],
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
    this.colors = const [HudColors.cyan, HudColors.purple],
    this.dimmed = false,
  });

  final double value;
  final double height;
  final List<Color> colors;
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
          color: Colors.white.withValues(alpha: 0.06),
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
              boxShadow: dimmed
                  ? null
                  : [
                      BoxShadow(
                        color: colors.first.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini area chart for bandwidth history.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = HudColors.cyan,
  });

  final List<double> values;
  final Color color;

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
  const HudLabel(this.text, {super.key, this.color = HudColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
      color: color,
    ),
  );
}

class HudIconButton extends StatelessWidget {
  const HudIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color = HudColors.textMuted,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    color: color,
    hoverColor: HudColors.cyan.withValues(alpha: 0.10),
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
        Icon(icon, size: 44, color: HudColors.cyan.withValues(alpha: 0.5)),
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
              style: const TextStyle(color: HudColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ],
    ),
  );
}
