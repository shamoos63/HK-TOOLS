import 'package:flutter/material.dart';

/// Cyber-HUD design tokens.
abstract final class HudColors {
  static const background = Color(0xFF0B0F19);
  static const surface = Color(0xFF121829);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x3300F0FF);
  static const cyan = Color(0xFF00F0FF);
  static const purple = Color(0xFF7000FF);
  static const textPrimary = Color(0xFFE6F7FF);
  static const textMuted = Color(0xFF7A8BA8);
  static const success = Color(0xFF00FFA3);
  static const warning = Color(0xFFFFC400);
  static const danger = Color(0xFFFF3D71);
}

abstract final class HudTheme {
  /// Monospace stack for telemetry (speeds, sizes, hashes).
  static const monoFamily = 'monospace';
  static const monoFallback = ['Cascadia Mono', 'Consolas', 'SF Mono', 'Menlo'];

  static TextStyle telemetry({
    double size = 13,
    Color color = HudColors.cyan,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: size,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: HudColors.cyan,
      secondary: HudColors.purple,
      surface: HudColors.surface,
      error: HudColors.danger,
      onPrimary: HudColors.background,
      onSurface: HudColors.textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HudColors.background,
      dividerColor: HudColors.glassBorder,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: HudColors.surface,
        contentTextStyle: const TextStyle(color: HudColors.textPrimary),
        actionTextColor: HudColors.cyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: HudColors.glassBorder),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: HudColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: HudColors.glassBorder),
        ),
        textStyle: const TextStyle(color: HudColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          HudColors.cyan.withValues(alpha: 0.25),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(5),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: HudColors.surface),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: HudColors.textPrimary,
        displayColor: HudColors.textPrimary,
      ),
    );
  }
}
