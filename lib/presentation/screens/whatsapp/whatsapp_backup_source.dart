import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/device/contacts_service.dart';
import '../../providers/device_providers.dart';

import '../../../services/whatsapp/wa_android.dart';
import '../../providers/whatsapp_android_providers.dart';
import '../../providers/whatsapp_android_restore_providers.dart';
import '../../providers/whatsapp_backup_providers.dart';
import '../../providers/whatsapp_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';

/// WhatsApp from an iPhone backup: the connected iPhone (back it up now), or
/// any existing backup made by HK Tools, Finder / iTunes or 3uTools. The
/// chats can be read on this computer and restored to a connected iPhone.
class WaBackupSource extends ConsumerWidget {
  const WaBackupSource({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iphones = ref
        .watch(devicesProvider)
        .devices
        .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
        .toList();
    final device = iphones.firstOrNull;
    final job = ref.watch(backupJobProvider);
    final backingUp = job.status == JobStatus.running;
    final backups = ref.watch(waAllBackupsProvider);
    final selected = ref.watch(waBackupDirProvider);

    Future<void> backup() async {
      if (device == null) return;
      final root = p.join(ref.read(deviceDataDirProvider), 'Backups');
      await ref
          .read(backupJobProvider.notifier)
          .run(
            trf('Backup of {0}', [device.displayName]),
            () => ref
                .read(deviceServiceProvider)
                .startBackup(device, namedBackupDir(root, device)),
          );
      ref.invalidate(waAllBackupsProvider);
    }

    Future<void> chooseFolder() async {
      final dir = await getDirectoryPath(
        confirmButtonText: tr('Use this backup'),
      );
      if (dir == null) return;
      final found = BackupContacts.findBackups(dir, origin: 'Folder');
      if (found.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'No iPhone backup in that folder. Pick the folder that contains Info.plist and Manifest.db, or the folder above it.',
                ),
              ),
            ),
          );
        }
        return;
      }
      final roots = ref.read(waExtraBackupRootsProvider);
      if (!roots.contains(dir)) {
        ref.read(waExtraBackupRootsProvider.notifier).set([...roots, dir]);
      }
      ref.read(waBackupDirProvider.notifier).set(found.first.directory);
    }

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                size: 20,
                color: device == null ? HudColors.textMuted : HudColors.cyan,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  device == null
                      ? tr(
                          'No iPhone connected. You can still open an existing backup.',
                        )
                      : device.displayName,
                  style: TextStyle(
                    fontSize: device == null ? 13 : 15,
                    fontWeight: device == null
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: device == null
                        ? HudColors.textMuted
                        : HudColors.textPrimary,
                  ),
                ),
              ),
              if (device != null)
                NeonButton(
                  label: backingUp ? tr('Backing up…') : tr('Back up now'),
                  icon: Icons.backup_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: backingUp ? null : backup,
                ),
              const SizedBox(width: 8),
              NeonButton(
                label: tr('Choose backup folder…'),
                icon: Icons.folder_open_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: chooseFolder,
              ),
              HudIconButton(
                icon: Icons.refresh_rounded,
                tooltip: tr('Look for backups again'),
                onPressed: () => ref.invalidate(waAllBackupsProvider),
              ),
            ],
          ),
          if (backingUp) ...[
            const SizedBox(height: 8),
            GlowProgressBar(value: job.progress ?? 0, height: 4),
          ],
          const SizedBox(height: 12),
          Text(
            tr(
              'Backups with WhatsApp on this computer (HK Tools, Finder / iTunes, 3uTools):',
            ),
            style: TextStyle(fontSize: 12.5, color: HudColors.textMuted),
          ),
          const SizedBox(height: 8),
          backups.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => DeviceError(e),
            data: (list) => list.isEmpty
                ? Text(
                    tr(
                      'No backup with WhatsApp found. Press "Back up now", or "Choose backup folder…" for an iTunes or 3uTools backup saved somewhere else. Backups must not be encrypted.',
                    ),
                    style: TextStyle(color: HudColors.textMuted, fontSize: 13),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final s in list)
                            _BackupRow(
                              source: s,
                              selected: s.directory == selected,
                              onTap: s.encrypted
                                  ? null
                                  : () => ref
                                        .read(waBackupDirProvider.notifier)
                                        .set(s.directory),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            _RestoreCard(backupDir: selected, iphones: iphones),
            const SizedBox(height: 12),
            _AndroidRestoreCard(backupDir: selected),
          ],
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final ContactsSource source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final origin = tr(s.origin);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? HudColors.cyan.withValues(alpha: 0.14)
                : HudColors.overlay.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? HudColors.cyan.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? HudColors.cyan : HudColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.deviceName ?? p.basename(s.directory),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (s.date != null) _fmt(s.date!),
                        ?s.productType,
                      ].join('  ·  '),
                      style: TextStyle(
                        fontSize: 12,
                        color: HudColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.encrypted)
                HudPill(
                  tr('Encrypted: can\'t be read'),
                  color: HudColors.warning,
                  icon: Icons.lock_rounded,
                ),
              const SizedBox(width: 6),
              HudPill(origin, color: HudColors.textMuted),
              HudIconButton(
                icon: Icons.folder_rounded,
                tooltip: tr('Show in folder'),
                onPressed: () => revealPath(s.directory),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Restore the selected backup's WhatsApp to a connected iPhone.
class _RestoreCard extends ConsumerStatefulWidget {
  const _RestoreCard({required this.backupDir, required this.iphones});

  final String backupDir;
  final List<ConnectedDevice> iphones;

  @override
  ConsumerState<_RestoreCard> createState() => _RestoreCardState();
}

class _RestoreCardState extends ConsumerState<_RestoreCard> {
  String? _udid;
  bool _business = false;

  @override
  Widget build(BuildContext context) {
    final restore = ref.watch(waBackupRestoreProvider);
    final job = ref.watch(backupJobProvider);
    final flavors =
        ref.watch(waBackupFlavorsProvider(widget.backupDir)).value ??
        const <bool>[];
    final iphones = widget.iphones;
    final device =
        iphones.where((d) => d.udid == _udid).firstOrNull ??
        iphones.firstOrNull;
    final business = flavors.contains(_business)
        ? _business
        : (flavors.firstOrNull ?? false);
    final app = business ? tr('WhatsApp Business') : tr('WhatsApp');

    Future<void> start() async {
      if (device == null) return;
      final ok = await confirmDialog(
        context,
        title: trf('Restore {0} to {1}?', [app, device.displayName]),
        message: trf(
          '{0} on {1} is replaced with the chats, media and account from this backup. Only {0} changes: photos, apps and settings stay as they are. The iPhone restarts at the end. Keep it unlocked and connected until it does.',
          [app, device.displayName],
        ),
        confirmLabel: tr('Restore'),
      );
      if (!ok) return;
      await ref
          .read(waBackupRestoreProvider.notifier)
          .restore(device, widget.backupDir, business: business);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: HudColors.overlay.withValues(alpha: 0.04),
        border: Border.all(color: HudColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings_backup_restore_rounded,
                size: 20,
                color: HudColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Restore WhatsApp from this backup to an iPhone'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (flavors.length > 1)
                for (final b in const [false, true])
                  HudChipTab(
                    label: b ? tr('WhatsApp Business') : tr('WhatsApp'),
                    active: business == b,
                    enabled: !restore.running,
                    onTap: () => setState(() => _business = b),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Install WhatsApp on the iPhone first (don\'t register it yet) and turn off Find My. The chats, photos, voice notes and the account come from the backup.',
            ),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: HudColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          if (iphones.isEmpty)
            Text(
              tr('Connect and trust the iPhone to restore to.'),
              style: TextStyle(fontSize: 13, color: HudColors.warning),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final d in iphones)
                  HudChipTab(
                    label: d.displayName,
                    active: d.udid == device?.udid,
                    enabled: !restore.running,
                    onTap: () => setState(() => _udid = d.udid),
                  ),
                NeonButton(
                  label: restore.running
                      ? tr('Restoring…')
                      : trf('Restore to {0}', [device!.displayName]),
                  icon: Icons.restore_rounded,
                  onPressed: restore.running ? null : start,
                ),
              ],
            ),
          if (restore.running) ...[
            const SizedBox(height: 10),
            Text(
              restore.phase == WaRestorePhase.preparing
                  ? trf('1/2 Taking {0} out of the backup…', [app])
                  : tr('2/2 Restoring to the iPhone…'),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            GlowProgressBar(
              value: restore.phase == WaRestorePhase.restoring
                  ? (job.progress ?? 0)
                  : 0.05,
              height: 4,
            ),
          ],
          if (restore.phase == WaRestorePhase.done) ...[
            const SizedBox(height: 10),
            Text(
              trf(
                'Done. When the iPhone has restarted, open {0} and confirm your phone number. The chats from the backup are there.',
                [app],
              ),
              style: TextStyle(fontSize: 12.5, color: HudColors.success),
            ),
          ],
          if (restore.phase == WaRestorePhase.failed) ...[
            const SizedBox(height: 10),
            SelectableText(
              restore.error ?? tr('The restore failed.'),
              style: TextStyle(fontSize: 12.5, color: HudColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// iPhone backup → Android phone. The Android side (key + the phone's own
/// backup) is prepared in the "From Android" steps; this card merges the
/// iPhone chats into it and puts it back on the phone.
class _AndroidRestoreCard extends ConsumerWidget {
  const _AndroidRestoreCard({required this.backupDir});

  final String backupDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(waAndroidProvider);
    final restore = ref.watch(waAndroidRestoreProvider);
    final flavors =
        ref.watch(waBackupFlavorsProvider(backupDir)).value ?? const <bool>[];
    final devices = ref.watch(androidDevicesProvider).value ?? const [];
    final phone = devices.where((d) => d.serial == flow.serial).firstOrNull;
    final business = flow.flavor == WaFlavor.business;
    final app = business ? tr('WhatsApp Business') : tr('WhatsApp');
    final ready =
        flow.step == WaAndroidStep.done &&
        flow.keyHex != null &&
        phone?.state == AndroidDeviceState.ready;
    final hasFlavor = flavors.isEmpty || flavors.contains(business);

    Future<void> start() async {
      final ok = await confirmDialog(
        context,
        title: trf('Restore {0} to {1}?', [app, phone!.displayName]),
        message: trf(
          'The chats and media from this iPhone backup are added to the Android backup made a moment ago, and it is put back on {1}. {0} on the phone is then reset and asks to restore: enter the 64-digit key. Messages that arrived on the phone after that backup are not kept.',
          [app, phone.displayName],
        ),
        confirmLabel: tr('Restore'),
      );
      if (!ok) return;
      await ref
          .read(waAndroidRestoreProvider.notifier)
          .restore(iphoneBackupDir: backupDir);
    }

    final muted = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: HudColors.textMuted,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: HudColors.overlay.withValues(alpha: 0.04),
        border: Border.all(color: HudColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.android_rounded, size: 20, color: HudColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Restore WhatsApp from this backup to an Android phone'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!ready) ...[
            Text(
              tr(
                'First prepare the Android phone: install WhatsApp and register it with your number, then in "From Android" read the 64-digit key and copy the phone\'s backup (photos from the Android phone don\'t need to be copied). Then come back here.',
              ),
              style: muted,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: NeonButton(
                label: tr('Prepare the Android phone'),
                icon: Icons.android_rounded,
                variant: NeonVariant.ghost,
                onPressed: () => ref
                    .read(waSourceModeProvider.notifier)
                    .set(WaSourceMode.android),
              ),
            ),
          ] else ...[
            Text(
              trf('Ready: {0} on {1}, with its 64-digit key.', [
                app,
                phone!.displayName,
              ]),
              style: muted,
            ),
            if (!hasFlavor) ...[
              const SizedBox(height: 6),
              Text(
                trf(
                  'This backup has no {0}. Pick the other app in "From Android".',
                  [app],
                ),
                style: TextStyle(fontSize: 12.5, color: HudColors.warning),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: NeonButton(
                label: restore.running
                    ? tr('Restoring…')
                    : trf('Restore to {0}', [phone.displayName]),
                icon: Icons.restore_rounded,
                onPressed: restore.running || !hasFlavor ? null : start,
              ),
            ),
          ],
          if (restore.running) ...[
            const SizedBox(height: 10),
            Text(switch (restore.phase) {
              WaAndroidRestorePhase.preparing => tr(
                '1/3 Adding the iPhone chats to the Android backup…',
              ),
              WaAndroidRestorePhase.pushing => tr(
                '2/3 Copying the backup and media to the phone…',
              ),
              _ => trf('3/3 Resetting {0} on the phone…', [app]),
            }, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 6),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (restore.phase == WaAndroidRestorePhase.done) ...[
            const SizedBox(height: 10),
            Text(
              trf(
                'Done: {0} messages and {1} photos, videos and voice notes added. {2} is open on the phone: agree, confirm your number, tap Restore when it finds the backup, and enter this key:',
                [
                  restore.result?.messagesAdded ?? 0,
                  restore.result?.mediaFiles.length ?? 0,
                  app,
                ],
              ),
              style: TextStyle(fontSize: 12.5, color: HudColors.success),
            ),
            if (restore.keyHex != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      [
                        for (var i = 0; i < restore.keyHex!.length; i += 4)
                          restore.keyHex!.substring(i, i + 4),
                      ].join(' '),
                      style: HudTheme.telemetry(
                        size: 12,
                        color: HudColors.textPrimary,
                      ),
                    ),
                  ),
                  HudIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: tr('Copy key'),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: restore.keyHex!)),
                  ),
                ],
              ),
            ],
          ],
          if (restore.phase == WaAndroidRestorePhase.failed) ...[
            const SizedBox(height: 10),
            SelectableText(
              restore.error ?? tr('The restore failed.'),
              style: TextStyle(fontSize: 12.5, color: HudColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}
