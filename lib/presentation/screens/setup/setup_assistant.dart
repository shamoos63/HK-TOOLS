import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../services/setup/dependency_manager.dart';
import '../../providers/core_providers.dart';
import '../../providers/setup_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Shows the setup assistant when something the device features need is
/// missing (called once at startup, and from Settings).
Future<void> showSetupAssistant(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const SetupAssistantDialog(),
);

/// Startup check: opens the assistant if anything installable is missing.
Future<void> runStartupToolCheck(BuildContext context, WidgetRef ref) async {
  if (!ref.read(settingsProvider).checkToolsAtStartup) return;
  final statuses = await ref.read(dependencyStatusProvider.future);
  final needed = statuses.any(
    (s) => !s.installed && (s.dependency.required || s.canInstall),
  );
  if (needed && context.mounted) await showSetupAssistant(context);
}

class SetupAssistantDialog extends ConsumerStatefulWidget {
  const SetupAssistantDialog({super.key});

  @override
  ConsumerState<SetupAssistantDialog> createState() =>
      _SetupAssistantDialogState();
}

class _SetupAssistantDialogState extends ConsumerState<SetupAssistantDialog> {
  Set<Dependency>? _chosen;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dependencyStatusProvider);
    final jobs = ref.watch(setupProvider);
    final busy = jobs.values.any((s) => s is Installing);
    final checkAtStartup = ref.watch(
      settingsProvider.select((s) => s.checkToolsAtStartup),
    );
    final statuses = async.value ?? const <DependencyStatus>[];
    final installable = {
      for (final s in statuses)
        if (!s.installed && s.canInstall) s.dependency,
    };
    // Everything installable is pre-selected: one click installs it all.
    final chosen = (_chosen ?? installable).intersection(installable);
    final allGood = statuses.isNotEmpty && statuses.every((s) => s.installed);

    return AlertDialog(
      // Scrolls as a whole so it fits small windows / high display scaling.
      scrollable: true,
      backgroundColor: HudColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: HudColors.glassBorder),
      ),
      title: Row(
        children: [
          Icon(Icons.build_circle_rounded, color: HudColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Setup assistant'), style: TextStyle(fontSize: 17)),
          ),
          if (async.isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              allGood
                  ? tr('Everything the device features need is installed.')
                  : tr(
                      'HK Tools uses these components to work with iPhones and iPads. Missing ones can be installed for you.',
                    ),
              style: TextStyle(color: HudColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final s in statuses)
              _DependencyRow(
                status: s,
                job: jobs[s.dependency],
                selected: chosen.contains(s.dependency),
                onToggle: busy || !installable.contains(s.dependency)
                    ? null
                    : (v) => setState(() {
                        final next = {...chosen};
                        v ? next.add(s.dependency) : next.remove(s.dependency);
                        _chosen = next;
                      }),
              ),
            const SizedBox(height: 10),
            Text(
              Platform.isWindows
                  ? tr(
                      'Sources: Apple Devices from the Microsoft Store; libimobiledevice tools (github.com/jrjr/libimobiledevice-windows) and ipatool (github.com/majd/ipatool) from GitHub, checked against pinned SHA-256 hashes; pymobiledevice3 with uv (github.com/astral-sh/uv), which brings its own Python 3.12. Installing means you accept each package\'s license.',
                    )
                  : tr(
                      'Installs use Homebrew, and uv for pymobiledevice3 (with its own Python 3.12). Installing means you accept each package\'s license.',
                    ),
              style: TextStyle(
                color: HudColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: checkAtStartup,
              title: Text(
                tr('Check at startup'),
                style: TextStyle(fontSize: 12.5),
              ),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(checkToolsAtStartup: v ?? true)),
            ),
          ],
        ),
      ),
      actions: [
        NeonButton(
          label: tr('Check again'),
          icon: Icons.refresh_rounded,
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: busy
              ? null
              : () {
                  ref.read(setupProvider.notifier).reset();
                  ref.invalidate(dependencyStatusProvider);
                },
        ),
        NeonButton(
          label: allGood ? tr('Done') : tr('Close'),
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        if (installable.isNotEmpty)
          NeonButton(
            label: busy
                ? tr('Installing…')
                : trf('Install selected ({0})', [chosen.length]),
            icon: Icons.download_rounded,
            compact: true,
            onPressed: busy || chosen.isEmpty
                ? null
                : () => ref.read(setupProvider.notifier).installAll(chosen),
          ),
      ],
    );
  }
}

class _DependencyRow extends StatelessWidget {
  const _DependencyRow({
    required this.status,
    required this.job,
    required this.selected,
    required this.onToggle,
  });

  final DependencyStatus status;
  final InstallState? job;
  final bool selected;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final d = status.dependency;
    final (icon, color) = status.installed
        ? (Icons.check_circle_rounded, HudColors.success)
        : d.required
        ? (Icons.error_rounded, HudColors.danger)
        : (Icons.remove_circle_outline_rounded, HudColors.warning);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: HudColors.overlay.withValues(alpha: 0.03),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      d.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    HudPill(
                      d.required ? tr('Required') : tr('Optional'),
                      color: d.required ? HudColors.cyan : HudColors.textMuted,
                      mono: false,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  d.purpose,
                  style: TextStyle(color: HudColors.textMuted, fontSize: 12),
                ),
                if (status.detail != null)
                  Text(
                    status.detail!,
                    style: HudTheme.telemetry(
                      size: 11,
                      color: HudColors.textMuted,
                    ),
                  ),
                if (!status.installed &&
                    !status.canInstall &&
                    status.manualHint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: SelectableText(
                      status.manualHint!,
                      style: TextStyle(
                        color: HudColors.warning,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                switch (job) {
                  Installing(:final status, :final fraction) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fraction == null
                            ? const LinearProgressIndicator(minHeight: 3)
                            : GlowProgressBar(value: fraction, height: 4),
                        const SizedBox(height: 3),
                        Text(status, style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                  InstallDone() => Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      tr('Installed'),
                      style: TextStyle(
                        color: HudColors.success,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  InstallFailed(:final message) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      message,
                      style: TextStyle(color: HudColors.danger, fontSize: 11.5),
                    ),
                  ),
                  null => const SizedBox.shrink(),
                },
              ],
            ),
          ),
          if (!status.installed && status.canInstall)
            Checkbox(
              value: selected,
              onChanged: onToggle == null ? null : (v) => onToggle!(v ?? false),
            ),
        ],
      ),
    );
  }
}
