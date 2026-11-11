import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/whatsapp/wa_android.dart';
import '../../providers/device_providers.dart';
import '../../providers/whatsapp_android_providers.dart';
import '../../providers/whatsapp_providers.dart';
import '../../providers/whatsapp_transfer_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Last step of the Android flow: write the chats onto a connected iPhone.
class WaTransferCard extends ConsumerStatefulWidget {
  const WaTransferCard({super.key});

  @override
  ConsumerState<WaTransferCard> createState() => _WaTransferCardState();
}

class _WaTransferCardState extends ConsumerState<WaTransferCard> {
  String? _udid;

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(waArchiveProvider).value;
    final android = ref.watch(waAndroidProvider);
    final flavor = android.flavor;
    final t = ref.watch(waTransferProvider);
    final job = ref.watch(backupJobProvider);
    final iphones = ref
        .watch(devicesProvider)
        .devices
        .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
        .toList();
    final device =
        iphones.where((d) => d.udid == (_udid ?? t.udid)).firstOrNull ??
        iphones.firstOrNull;
    final app = flavor.label;

    Future<void> start() async {
      if (device == null || archive == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(trf('Move chats to {0}?', [device.displayName])),
          content: Text(
            trf(
              'The iPhone is backed up, the Android chats are added to its {0} data, and the backup is restored to it. Only {0}\'s data on the iPhone is replaced; photos, apps and settings aren\'t touched. The iPhone restarts at the end. Keep it unlocked and connected until it does.',
              [app],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Start')),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await ref
          .read(waTransferProvider.notifier)
          .transfer(
            device,
            archive,
            business: flavor == WaFlavor.business,
            mediaRoot: android.mediaDir,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Text(
          trf(
            'Before you start, on the iPhone: install {0}, register it with the same phone number, and send one message. Turn off Find My (Settings → your name → Find My). Only the {1} chats change.',
            [app, app],
          ),
        ),
        const SizedBox(height: 8),
        if (iphones.isEmpty)
          _Text(tr('Connect and trust the iPhone to continue.'))
        else
          Row(
            children: [
              Icon(Icons.phone_iphone_rounded, size: 16, color: HudColors.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in iphones)
                      HudChipTab(
                        label: d.displayName,
                        active: d.udid == device?.udid,
                        enabled: !t.running,
                        onTap: () => setState(() => _udid = d.udid),
                      ),
                  ],
                ),
              ),
              NeonButton(
                label: t.running ? tr('Transferring…') : tr('Move to iPhone'),
                icon: Icons.swap_horiz_rounded,
                compact: true,
                onPressed: t.running || device == null || archive == null
                    ? null
                    : start,
              ),
            ],
          ),
        if (t.phase != WaTransferPhase.idle) ...[
          const SizedBox(height: 10),
          _Progress(state: t, job: job),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state, required this.job});

  final WaTransferState state;
  final JobState job;

  @override
  Widget build(BuildContext context) {
    final r = state.result;
    switch (state.phase) {
      case WaTransferPhase.idle:
        return const SizedBox.shrink();
      case WaTransferPhase.backingUp:
      case WaTransferPhase.restoring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Text(
              state.phase == WaTransferPhase.backingUp
                  ? tr('1/3 Backing up the iPhone…')
                  : trf('3/3 Restoring to the iPhone ({0} messages)…', [
                      r?.messagesAdded ?? 0,
                    ]),
            ),
            const SizedBox(height: 6),
            GlowProgressBar(value: job.progress ?? 0, height: 4),
            if (job.log.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                job.log.last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HudTheme.telemetry(size: 10.5),
              ),
            ],
          ],
        );
      case WaTransferPhase.writing:
        return Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            _Text(tr('2/3 Adding the chats to the iPhone backup…')),
          ],
        );
      case WaTransferPhase.done:
        return Text(
          trf(
            'Done: {0} messages in {1} chats moved, with {2} photos, videos, voice notes and documents and {4} calls{3}. When the iPhone has restarted, open WhatsApp and confirm your number if asked. If the chats don\'t appear, back up WhatsApp to iCloud on the iPhone (Settings → Chats → Chat Backup), reinstall WhatsApp and choose Restore Chat History.',
            [
              r!.messagesAdded,
              r.chatsCreated + r.chatsMerged,
              r.mediaFiles.length,
              r.mediaMissing > 0
                  ? trf(
                      ' ({0} media files weren\'t on the Android phone and show as labels)',
                      [r.mediaMissing],
                    )
                  : '',
              r.callsAdded,
            ],
          ),
          style: TextStyle(color: HudColors.success, fontSize: 12, height: 1.4),
        );
      case WaTransferPhase.failed:
        return Text(
          state.error ?? tr('The transfer failed.'),
          style: TextStyle(color: HudColors.danger, fontSize: 12.5),
        );
    }
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: HudColors.textMuted, fontSize: 12, height: 1.4),
  );
}
