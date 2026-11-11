import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/download_feedback.dart';
import '../../widgets/hud_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Floating bar summarising ticked payloads, with dedupe savings.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(selectionProvider);
    final index = ref.watch(catalogIndexProvider);
    final groups = [for (final k in keys) ?index.groupFor(k)];
    final total = groups.fold<int>(0, (s, g) => s + g.release.fileSize);
    final devices = groups.fold<int>(
      0,
      (s, g) => s + g.deviceIdentifiers.length,
    );
    final saved = groups.fold<int>(
      0,
      (s, g) => s + g.release.fileSize * (g.deviceIdentifiers.length - 1),
    );

    return AnimatedSlide(
      offset: groups.isEmpty ? const Offset(0, 1.6) : Offset.zero,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: groups.isEmpty ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: GlassPanel(
          glow: true,
          tint: HudColors.cyan,
          borderColor: HudColors.cyan.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.checklist_rounded, color: HudColors.cyan, size: 20),
              const SizedBox(width: 12),
              Text(
                trf('{0} payload{1}', [
                  groups.length,
                  groups.length == 1 ? '' : 's',
                ]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 14),
              Text(formatBytes(total), style: HudTheme.telemetry(size: 13)),
              const SizedBox(width: 14),
              Text(
                trf('{0} device targets', [devices]),
                style: TextStyle(color: HudColors.textMuted, fontSize: 12),
              ),
              if (saved > 0) ...[
                const SizedBox(width: 14),
                HudPill(
                  trf('DEDUPE SAVES {0}', [formatBytes(saved, decimals: 1)]),
                  color: HudColors.purple,
                  icon: Icons.compress_rounded,
                ),
              ],
              const Spacer(),
              NeonButton(
                label: tr('Clear'),
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: ref.read(selectionProvider.notifier).clear,
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: trf('Queue {0}', [groups.length]),
                icon: Icons.download_for_offline_rounded,
                onPressed: groups.isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final tasks = await queueIpswDownloads(
                          context,
                          ref,
                          groups,
                        );
                        if (tasks == null) return;
                        ref.read(selectionProvider.notifier).clear();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              trf('Queued {0} payload{1}', [
                                tasks.length,
                                tasks.length == 1 ? '' : 's',
                              ]),
                            ),
                            action: SnackBarAction(
                              label: tr('VIEW'),
                              onPressed: () => ref
                                  .read(sectionProvider.notifier)
                                  .set(AppSection.queue),
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
