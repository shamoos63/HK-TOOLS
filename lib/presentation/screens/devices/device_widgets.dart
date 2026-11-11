import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/folder_access.dart';
import '../../widgets/hud_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Glass card with a titled header used by every device tab.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 14, 18, 16),
    this.fill = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Stretch [child] to the remaining height (lists inside a tab).
  final bool fill;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: HudColors.cyan),
            SizedBox(width: 8),
            Expanded(child: HudLabel(title, color: HudColors.textPrimary)),
            ?trailing,
          ],
        ),
        SizedBox(height: 12),
        fill ? Expanded(child: child) : child,
      ],
    ),
  );
}

/// Label/value rows; clicking a value copies it.
class InfoTable extends StatelessWidget {
  const InfoTable(this.rows, {super.key, this.labelWidth = 150});

  final List<(String, String?)> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (label, value) in rows)
        if (value != null && value.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 3.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: HudColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: tr('Click to copy'),
                    child: InkWell(
                      onTap: () => copyText(context, value),
                      child: Text(
                        value,
                        style: HudTheme.telemetry(
                          size: 12.5,
                          color: HudColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

class HudChipTab extends StatelessWidget {
  const HudChipTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(right: 6, bottom: 6),
    child: MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: active
                ? HudColors.cyan.withValues(alpha: 0.12)
                : HudColors.overlay.withValues(alpha: 0.03),
            border: Border.all(
              color: active
                  ? HudColors.cyan.withValues(alpha: 0.5)
                  : HudColors.overlay.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: !enabled
                  ? HudColors.textMuted.withValues(alpha: 0.35)
                  : active
                  ? HudColors.textPrimary
                  : HudColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Inline error with the tool's message and an optional retry.
class DeviceError extends StatelessWidget {
  const DeviceError(this.error, {super.key, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: HudColors.danger),
        SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            '$error',
            style: TextStyle(color: HudColors.textMuted, fontSize: 12.5),
          ),
        ),
        if (onRetry != null)
          NeonButton(
            label: tr('Retry'),
            icon: Icons.refresh_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: onRetry,
          ),
      ],
    ),
  );
}

void copyText(BuildContext context, String value) {
  Clipboard.setData(ClipboardData(text: value));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(trf('Copied {0}', [value])),
      duration: Duration(seconds: 1),
    ),
  );
}

/// Runs a device command and reports the outcome in a snackbar.
Future<bool> runDeviceAction(
  BuildContext context,
  String success,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e is FileSystemException
              ? describeFolderError(e, e.path ?? '')
              : '$e',
        ),
        backgroundColor: HudColors.danger.withValues(alpha: 0.9),
      ),
    );
    return false;
  }
}

/// Confirmation dialog. With [typeToConfirm] the confirm button stays
/// disabled until that exact word is typed (used for destructive actions).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
  bool danger = false,
  String? typeToConfirm,
}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final armed =
            typeToConfirm == null || controller.text.trim() == typeToConfirm;
        return AlertDialog(
          backgroundColor: HudColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: danger
                  ? HudColors.danger.withValues(alpha: 0.5)
                  : HudColors.glassBorder,
            ),
          ),
          title: Text(title, style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: HudColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (typeToConfirm != null) ...[
                  SizedBox(height: 16),
                  Text(
                    trf('Type {0} to confirm', [typeToConfirm]),
                    style: TextStyle(fontSize: 12.5),
                  ),
                  SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: HudTheme.telemetry(color: HudColors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            NeonButton(
              label: tr('Cancel'),
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            NeonButton(
              label: tr(confirmLabel),
              variant: danger ? NeonVariant.danger : NeonVariant.primary,
              compact: true,
              onPressed: armed ? () => Navigator.pop(ctx, true) : null,
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return ok ?? false;
}

/// Single-field text prompt.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'Save',
  bool obscure = false,
  String? hint,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: HudColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: HudColors.glassBorder),
      ),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        NeonButton(
          label: tr('Cancel'),
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: () => Navigator.pop(ctx),
        ),
        NeonButton(
          label: tr(confirmLabel),
          compact: true,
          onPressed: () => Navigator.pop(ctx, controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

/// Shows [path] in Finder / Explorer.
void revealPath(String path) {
  if (Platform.isMacOS) {
    Process.run('open', [if (FileSystemEntity.isFileSync(path)) '-R', path]);
  } else if (Platform.isWindows) {
    Process.run('explorer.exe', [
      if (FileSystemEntity.isFileSync(path)) '/select,',
      path,
    ]);
  } else {
    Process.run('xdg-open', [path]);
  }
}

/// App icon from the shared icon cache, or a lettered tile while it loads /
/// when none exists.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.name,
    this.path,
    this.size = 36,
    Color? color,
  }) : _color = color;

  final String name;
  final String? path;
  final double size;
  final Color? _color;
  Color get color => _color ?? HudColors.cyan;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.225);
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          color: color,
        ),
      ),
    );
    if (path == null) return letter;
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        File(path!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => letter,
      ),
    );
  }
}
