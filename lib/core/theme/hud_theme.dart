import 'package:flutter/material.dart';

/// One set of colours for the whole app.
class HudPalette {
  const HudPalette({
    required this.brightness,
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceRaised,
    required this.glassBorder,
    required this.overlay,
    required this.cyan,
    required this.purple,
    required this.textPrimary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Brightness brightness;
  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceRaised;
  final Color glassBorder;

  /// Tint for hover / fill overlays: white on dark, black on light.
  final Color overlay;
  final Color cyan;
  final Color purple;
  final Color textPrimary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;

  static const dark = HudPalette(
    brightness: Brightness.dark,
    background: Color(0xFF202124),
    sidebar: Color(0xFF18191C),
    surface: Color(0xFF292A2E),
    surfaceRaised: Color(0xFF313236),
    glassBorder: Color(0x17FFFFFF),
    overlay: Colors.white,
    cyan: Color(0xFF4C8DFF),
    purple: Color(0xFF9B8CFF),
    textPrimary: Color(0xFFF1F3F6),
    textMuted: Color(0xFF8E96A3),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFF5B94A),
    danger: Color(0xFFFF6369),
  );

  static const light = HudPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F5F7),
    sidebar: Color(0xFFEBEDF0),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    glassBorder: Color(0x1A0B1220),
    overlay: Colors.black,
    cyan: Color(0xFF2468F2),
    purple: Color(0xFF6E56CF),
    textPrimary: Color(0xFF15181D),
    textMuted: Color(0xFF666E7A),
    success: Color(0xFF1A9E5C),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFD93A42),
  );
}

/// Design tokens: a calm graphite (or light grey) palette with one blue
/// accent. `cyan` is the accent and `purple` the secondary accent (names
/// kept from the original theme). The values follow [current], which the
/// app sets from Settings or the system's light/dark mode.
abstract final class HudColors {
  static HudPalette current = HudPalette.dark;

  /// Native translucent sidebar (macOS sidebar material / Windows Mica);
  /// the main panel stays solid.
  static bool translucent = false;

  static bool get isLight => current.brightness == Brightness.light;
  static Color get background => current.background;

  /// Transparent over the native sidebar material when [translucent].
  static Color get sidebar =>
      translucent ? Colors.transparent : current.sidebar;
  static Color get surface => current.surface;
  static Color get surfaceRaised => current.surfaceRaised;
  static Color get glass => current.overlay.withValues(alpha: 0.06);
  static Color get glassBorder => current.glassBorder;
  static Color get overlay => current.overlay;
  static Color get cyan => current.cyan;
  static Color get purple => current.purple;
  static Color get textPrimary => current.textPrimary;
  static Color get textMuted => current.textMuted;
  static Color get success => current.success;
  static Color get warning => current.warning;
  static Color get danger => current.danger;
}

abstract final class HudTheme {
  /// Monospace stack, only for raw values such as hashes and UDIDs.
  static const monoFamily = 'monospace';
  static const monoFallback = ['SF Mono', 'Menlo', 'Cascadia Mono', 'Consolas'];

  /// Numbers and short values (speeds, sizes, versions): the regular UI font
  /// with tabular figures, so columns still line up.
  static TextStyle telemetry({double size = 13, Color? color}) => TextStyle(
    fontSize: size,
    color: color ?? HudColors.cyan,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static ThemeData dark() => build(HudPalette.dark);

  static ThemeData light() => build(HudPalette.light);

  /// Theme for [palette]. Also makes it the [HudColors.current] palette.
  static ThemeData build(HudPalette palette) {
    HudColors.current = palette;
    final isLight = palette.brightness == Brightness.light;
    final scheme = (isLight ? ColorScheme.light : ColorScheme.dark).call(
      primary: HudColors.cyan,
      secondary: HudColors.purple,
      surface: HudColors.surface,
      error: HudColors.danger,
      onPrimary: Colors.white,
      onSurface: HudColors.textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: HudColors.background,
      dividerColor: HudColors.glassBorder,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: HudColors.surfaceRaised,
        contentTextStyle: TextStyle(color: HudColors.textPrimary),
        actionTextColor: HudColors.cyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: HudColors.glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HudColors.overlay.withValues(alpha: 0.04),
        hintStyle: TextStyle(color: HudColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: HudColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: HudColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: HudColors.cyan),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (isLight ? Colors.white : palette.textMuted),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.cyan
              : palette.overlay.withValues(alpha: isLight ? 0.14 : 0.12),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: HudColors.surfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: HudColors.glassBorder),
        ),
        textStyle: TextStyle(color: HudColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          HudColors.overlay.withValues(alpha: 0.18),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(5),
      ),
      popupMenuTheme: PopupMenuThemeData(color: HudColors.surfaceRaised),
      textTheme: (isLight ? ThemeData.light() : ThemeData.dark()).textTheme
          .apply(
            bodyColor: HudColors.textPrimary,
            displayColor: HudColors.textPrimary,
          ),
    );
  }
}
