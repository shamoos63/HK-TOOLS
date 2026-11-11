import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/download_task.dart';
import '../../../domain/entities/ipsw_release.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/download_feedback.dart';
import '../../widgets/hud_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// One physical IPSW payload with every device that shares it.
class FirmwareGroupTile extends ConsumerStatefulWidget {
  const FirmwareGroupTile({
    super.key,
    required this.group,
    this.highlightDevice,
  });

  final IpswGroup group;

  /// Device currently being browsed (listed first in the chips).
  final String? highlightDevice;

  @override
  ConsumerState<FirmwareGroupTile> createState() => _FirmwareGroupTileState();
}

class _FirmwareGroupTileState extends ConsumerState<FirmwareGroupTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final r = g.release;
    final index = ref.watch(catalogIndexProvider);
    final selected = ref.watch(
      selectionProvider.select((s) => s.contains(g.payloadKey)),
    );
    final task = ref.watch(payloadTasksProvider.select((m) => m[g.payloadKey]));

    final ids = [...g.deviceIdentifiers];
    if (widget.highlightDevice != null && ids.remove(widget.highlightDevice)) {
      ids.insert(0, widget.highlightDevice!);
    }
    final names = <String>[];
    for (final id in ids) {
      final n = index.displayName(id);
      if (!names.contains(n)) names.add(n);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ref.read(selectionProvider.notifier).toggle(g.payloadKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? HudColors.cyan.withValues(alpha: 0.08)
                : _hover
                ? HudColors.overlay.withValues(alpha: 0.04)
                : HudColors.overlay.withValues(alpha: 0.015),
            border: Border.all(
              color: selected
                  ? HudColors.cyan.withValues(alpha: 0.5)
                  : HudColors.overlay.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              _HudCheckbox(checked: selected),
              const SizedBox(width: 14),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.platform.label} ${r.version}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.buildId,
                      style: HudTheme.telemetry(
                        size: 11,
                        color: HudColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (g.isShared) ...[
                      Tooltip(
                        message: trf('One payload serves {0} devices:\n{1}', [
                          g.deviceIdentifiers.length,
                          g.deviceIdentifiers
                              .map(index.displayName)
                              .toSet()
                              .join('\n'),
                        ]),
                        child: HudPill(
                          trf('SHARED ×{0}', [g.deviceIdentifiers.length]),
                          color: HudColors.purple,
                          icon: Icons.link_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final n in names.take(3)) _DeviceChip(n),
                          if (names.length > 3)
                            _DeviceChip(
                              trf('+{0} more', [names.length - 3]),
                              muted: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 86,
                child: Text(
                  formatBytes(r.fileSize),
                  textAlign: TextAlign.right,
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 82,
                child: r.signed
                    ? HudPill(
                        tr('SIGNED'),
                        color: HudColors.success,
                        icon: Icons.verified_rounded,
                      )
                    : HudPill(tr('UNSIGNED'), color: HudColors.textMuted),
              ),
              SizedBox(
                width: 84,
                child: Text(
                  r.releaseDate == null ? '' : _date(r.releaseDate!),
                  textAlign: TextAlign.right,
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: _TaskAction(group: g, task: task),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip(this.label, {this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: HudColors.overlay.withValues(alpha: muted ? 0.02 : 0.05),
      border: Border.all(color: HudColors.overlay.withValues(alpha: 0.08)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        color: muted ? HudColors.textMuted : HudColors.textPrimary,
      ),
    ),
  );
}

class _HudCheckbox extends StatelessWidget {
  const _HudCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      color: checked ? HudColors.cyan : Colors.transparent,
      border: Border.all(
        color: checked
            ? HudColors.cyan
            : HudColors.textMuted.withValues(alpha: 0.6),
        width: 1.4,
      ),
      boxShadow: checked
          ? [
              BoxShadow(
                color: HudColors.cyan.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ]
          : null,
    ),
    child: checked
        ? Icon(Icons.check_rounded, size: 14, color: HudColors.background)
        : null,
  );
}

/// Download button, or the live status of the task for this payload.
class _TaskAction extends ConsumerWidget {
  const _TaskAction({required this.group, required this.task});

  final IpswGroup group;
  final DownloadTask? task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    if (t == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: NeonButton(
          label: tr('GET'),
          icon: Icons.download_rounded,
          compact: true,
          variant: NeonVariant.ghost,
          onPressed: () => queueIpswDownloads(context, ref, [group]),
        ),
      );
    }
    final (label, color) = switch (t.status) {
      DownloadStatus.completed
          when t.verification == VerificationState.passed =>
        (tr('VERIFIED'), HudColors.success),
      DownloadStatus.completed => (tr('STORED'), HudColors.success),
      DownloadStatus.queued => (tr('QUEUED'), HudColors.purple),
      DownloadStatus.paused => (tr('PAUSED'), HudColors.warning),
      DownloadStatus.failed => (tr('FAILED'), HudColors.danger),
      DownloadStatus.verifying => (tr('SHA1…'), HudColors.cyan),
      _ => ('${(t.fraction * 100).toStringAsFixed(0)}%', HudColors.cyan),
    };
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => ref.read(sectionProvider.notifier).set(AppSection.queue),
        child: HudPill(label, color: color),
      ),
    );
  }
}
