import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/hud_theme.dart';
import '../../core/l10n/l10n.dart';

/// On Windows the system title bar is hidden and HK Tools draws its own
/// minimize / maximize / close buttons in the header. macOS keeps its native
/// traffic lights (the title bar there is already transparent).
bool get useCustomWindowChrome =>
    debugForceWindowChrome ?? (!kIsWeb && Platform.isWindows);

/// Tests can force the custom chrome on any platform.
@visibleForTesting
bool? debugForceWindowChrome;

/// Width reserved at the top-right of the header for [WindowControls].
const windowControlsWidth = 46.0 * 3;

/// Hides the native title bar. Call before `runApp`.
Future<void> initWindowChrome() async {
  if (!useCustomWindowChrome) return;
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  // Smallest usable window (logical px). window_manager answers
  // WM_GETMINMAXINFO itself, so the limit has to be set here.
  await windowManager.setMinimumSize(const Size(960, 600));
  // Opaque window: nothing from the desktop can show through.
  await windowManager.setBackgroundColor(HudColors.background);
}

Future<void> _toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Drag to move the window, double-click to maximize / restore.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useCustomWindowChrome) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: child,
    );
  }
}

/// Puts a drag area *behind* [child]: empty space moves the window, while
/// text fields and buttons in [child] keep their own clicks and drags.
class WindowDragBackground extends StatelessWidget {
  const WindowDragBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useCustomWindowChrome) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: _toggleMaximize,
          ),
        ),
        child,
      ],
    );
  }
}

/// Minimize, maximize / restore and close, styled for the HUD theme.
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (!useCustomWindowChrome || debugForceWindowChrome != null) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    if (debugForceWindowChrome == null) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowRestore() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ChromeButton(
        tooltip: tr('Minimize'),
        icon: Icons.remove_rounded,
        onPressed: windowManager.minimize,
      ),
      _ChromeButton(
        tooltip: _maximized ? tr('Restore') : tr('Maximize'),
        icon: _maximized
            ? Icons.filter_none_rounded
            : Icons.crop_square_rounded,
        iconSize: _maximized ? 13 : 15,
        onPressed: _toggleMaximize,
      ),
      _ChromeButton(
        tooltip: tr('Close'),
        icon: Icons.close_rounded,
        hoverColor: const Color(0xFFE81123),
        onPressed: windowManager.close,
      ),
    ],
  );
}

class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.iconSize = 16,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final double iconSize;

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final danger = widget.hoverColor != null;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !_hover
                  ? Colors.transparent
                  : danger
                  ? widget.hoverColor
                  : HudColors.cyan.withValues(alpha: 0.12),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hover
                  ? (danger ? Colors.white : HudColors.cyan)
                  : HudColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
