import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../core/utils/plist.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/device/contacts_service.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// A finished `idevicebackup2` backup: `<root>/<udid>/Info.plist`.
class _BackupEntry {
  _BackupEntry(this.dir, this.info);

  final Directory dir;
  final Map<String, Object?> info;

  String get udid => p.basename(dir.path);
  String get name =>
      info.str('Device Name') ?? info.str('Display Name') ?? udid;
  String? get version => info.str('Product Version');
  String? get product => info.str('Product Type');

  /// From Manifest.plist; encrypted backups need their password to restore.
  bool get encrypted {
    try {
      final m = File(p.join(dir.path, 'Manifest.plist'));
      if (!m.existsSync()) return false;
      final v = parsePlistBytes(m.readAsBytesSync());
      return v is Map<String, Object?> && v.boolean('IsEncrypted') == true;
    } on Object {
      return false;
    }
  }

  DateTime? get date {
    final v = info['Last Backup Date'];
    return v is DateTime ? v.toLocal() : null;
  }
}

final _backupsProvider = FutureProvider.autoDispose
    .family<List<_BackupEntry>, String>((ref, root) async {
      if (!Directory(root).existsSync()) return const [];
      final out = <_BackupEntry>[];
      // `<root>/<udid>` (older backups) and `<root>/<name date>/<udid>`.
      for (final s in BackupContacts.findBackups(root, origin: '', depth: 2)) {
        final d = Directory(s.directory);
        final info = File(p.join(d.path, 'Info.plist'));
        try {
          out.add(_BackupEntry(d, parsePlistDict(await info.readAsString())));
        } on Object {
          out.add(_BackupEntry(d, const {}));
        }
      }
      out.sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );
      return out;
    });

final _encryptionProvider = FutureProvider.autoDispose.family<bool?, String>((
  ref,
  id,
) async {
  final d = ref.read(devicesProvider).byId(id);
  return d == null
      ? null
      : ref.read(deviceServiceProvider).backupWillEncrypt(d);
});

class BackupTab extends ConsumerWidget {
  const BackupTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = p.join(ref.watch(deviceDataDirProvider), 'Backups');
    final job = ref.watch(backupJobProvider);
    final running = job.status == JobStatus.running;
    final encrypted = ref.watch(_encryptionProvider(device.id)).value;
    final backups = ref.watch(_backupsProvider(root));
    final svc = ref.read(deviceServiceProvider);
    final jobs = ref.read(backupJobProvider.notifier);

    Future<void> backup({required bool full}) async {
      await jobs.run(
        full
            ? trf('Full backup of {0}', [device.displayName])
            : trf('Backup of {0}', [device.displayName]),
        () => svc.startBackup(device, namedBackupDir(root, device), full: full),
      );
      ref.invalidate(_backupsProvider(root));
    }

    return ListView(
      children: [
        DeviceCard(
          title: trf('Back up {0}', [device.displayName]),
          icon: Icons.backup_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Full local backup in the iTunes / Finder format: photos, messages, app data, settings and Health (when encrypted). Saved to:',
                ),
                style: TextStyle(color: HudColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  Directory(root).createSync(recursive: true);
                  revealPath(root);
                },
                child: Text(root, style: HudTheme.telemetry(size: 12)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HudPill(
                    encrypted == null
                        ? tr('Encryption: unknown')
                        : encrypted
                        ? tr('Encrypted backups')
                        : tr('Not encrypted'),
                    color: encrypted == true
                        ? HudColors.success
                        : HudColors.warning,
                    icon: encrypted == true
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                  ),
                  if (encrypted != null)
                    NeonButton(
                      label: encrypted
                          ? tr('Turn off encryption')
                          : tr('Encrypt backups'),
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: running
                          ? null
                          : () => _toggleEncryption(
                              context,
                              ref,
                              root,
                              !encrypted,
                            ),
                    ),
                  NeonButton(
                    label: tr('Back up now'),
                    icon: Icons.backup_rounded,
                    compact: true,
                    onPressed: running ? null : () => backup(full: false),
                  ),
                  NeonButton(
                    label: tr('Full backup'),
                    variant: NeonVariant.ghost,
                    compact: true,
                    onPressed: running ? null : () => backup(full: true),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (job.status != JobStatus.idle) ...[
          const SizedBox(height: 14),
          _JobCard(job: job, onCancel: running ? jobs.cancel : null),
        ],
        const SizedBox(height: 14),
        DeviceCard(
          title: tr('Backups on this computer'),
          icon: Icons.inventory_2_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HudIconButton(
                icon: Icons.folder_open_rounded,
                tooltip: tr('Restore from another folder…'),
                onPressed: running
                    ? null
                    : () => _restoreFromFolder(context, ref),
              ),
              HudIconButton(
                icon: Icons.refresh_rounded,
                tooltip: tr('Reload'),
                onPressed: () => ref.invalidate(_backupsProvider(root)),
              ),
            ],
          ),
          child: backups.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => DeviceError(e),
            data: (list) => list.isEmpty
                ? Text(
                    tr('No backups yet.'),
                    style: TextStyle(color: HudColors.textMuted, fontSize: 13),
                  )
                : Column(
                    children: [
                      for (final b in list)
                        _BackupRow(
                          entry: b,
                          isThisDevice: b.udid == device.udid,
                          onReveal: () => revealPath(b.dir.path),
                          onDelete: running
                              ? null
                              : () => _delete(context, ref, root, b),
                          onRestore: running
                              ? null
                              : () => _restore(
                                  context,
                                  ref,
                                  p.dirname(b.dir.path),
                                  b.udid,
                                  b.name,
                                ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleEncryption(
    BuildContext context,
    WidgetRef ref,
    String root,
    bool enable,
  ) async {
    final pw = await promptText(
      context,
      title: enable
          ? tr('Choose a backup password')
          : tr('Current backup password'),
      confirmLabel: enable ? tr('Encrypt') : tr('Turn off'),
      obscure: true,
      hint: enable
          ? tr('Needed to restore these backups. Do not lose it.')
          : null,
    );
    if (pw == null || pw.isEmpty || !context.mounted) return;
    await runDeviceAction(
      context,
      enable
          ? tr('Backup encryption enabled')
          : tr('Backup encryption disabled'),
      () => ref
          .read(deviceServiceProvider)
          .backupEncryption(device, root, enable: enable, password: pw),
    );
    ref.invalidate(_encryptionProvider(device.id));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String root,
    _BackupEntry b,
  ) async {
    final size = await _folderSize(b.dir);
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: trf('Delete the backup of {0}?', [b.name]),
      message: trf(
        '{0} at {1} will be permanently deleted from this computer. The device itself is not affected.',
        [formatBytes(size, decimals: 1), b.dir.path],
      ),
      confirmLabel: tr('Delete backup'),
      danger: true,
      typeToConfirm: 'DELETE',
    );
    if (!ok || !context.mounted) return;
    await runDeviceAction(
      context,
      trf('Backup of {0} deleted', [b.name]),
      () async {
        await b.dir.delete(recursive: true);
        // Remove the "<device name> <date>" folder around it too.
        final parent = b.dir.parent;
        if (p.normalize(parent.path) != p.normalize(root) &&
            parent.existsSync() &&
            parent.listSync().isEmpty) {
          await parent.delete();
        }
      },
    );
    ref.invalidate(_backupsProvider(root));
  }

  static Future<int> _folderSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } on FileSystemException {
      // Partial size is fine for the confirmation text.
    }
    return total;
  }

  Future<void> _restoreFromFolder(BuildContext context, WidgetRef ref) async {
    final dir = await getDirectoryPath(
      confirmButtonText: tr('Use this backup'),
    );
    if (dir == null || !context.mounted) return;
    if (!File(p.join(dir, 'Info.plist')).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Pick the backup folder that contains Info.plist.')),
        ),
      );
      return;
    }
    await _restore(
      context,
      ref,
      p.dirname(dir),
      p.basename(dir),
      p.basename(dir),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    String root,
    String sourceUdid,
    String name,
  ) async {
    final ok = await confirmDialog(
      context,
      title: trf('Restore "{0}" to {1}?', [name, device.displayName]),
      message: trf(
        'All current data on {0} is replaced with the backup. Turn off Find My on the device first. The device reboots when done.',
        [device.displayName],
      ),
      confirmLabel: tr('Restore backup'),
      danger: true,
      typeToConfirm: 'RESTORE',
    );
    if (!ok || !context.mounted) return;
    final pw = await promptText(
      context,
      title: tr('Backup password (leave empty if not encrypted)'),
      confirmLabel: tr('Start'),
      obscure: true,
    );
    if (pw == null) return;
    await ref
        .read(backupJobProvider.notifier)
        .run(
          trf('Restoring backup to {0}', [device.displayName]),
          () => ref
              .read(deviceServiceProvider)
              .startBackupRestore(
                device,
                root,
                sourceUdid: sourceUdid,
                password: pw.isEmpty ? null : pw,
              ),
        );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.entry,
    required this.isThisDevice,
    required this.onReveal,
    this.onRestore,
    this.onDelete,
  });

  final _BackupEntry entry;
  final bool isThisDevice;
  final VoidCallback onReveal;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final d = entry.date;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: isThisDevice ? HudColors.cyan : HudColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    ?entry.product,
                    if (entry.version != null) 'iOS ${entry.version}',
                    if (d != null)
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                    if (entry.encrypted) 'encrypted',
                  ].join(' · '),
                  style: HudTheme.telemetry(
                    size: 11.5,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isThisDevice) HudPill(tr('This device'), color: HudColors.cyan),
          const SizedBox(width: 8),
          HudIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: tr('Show in folder'),
            onPressed: onReveal,
          ),
          NeonButton(
            label: tr('Restore'),
            icon: Icons.settings_backup_restore_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: onRestore,
          ),
          const SizedBox(width: 4),
          HudIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: tr('Delete this backup'),
            color: HudColors.danger,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, this.onCancel});

  final JobState job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      JobStatus.succeeded => HudColors.success,
      JobStatus.failed => HudColors.danger,
      _ => HudColors.cyan,
    };
    return DeviceCard(
      title: job.title,
      icon: switch (job.status) {
        JobStatus.succeeded => Icons.check_circle_rounded,
        JobStatus.failed => Icons.error_rounded,
        _ => Icons.sync_rounded,
      },
      trailing: onCancel == null
          ? HudPill(
              job.status == JobStatus.succeeded ? 'Completed' : tr('Failed'),
              color: color,
            )
          : NeonButton(
              label: tr('Cancel'),
              variant: NeonVariant.danger,
              compact: true,
              onPressed: onCancel,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (job.status == JobStatus.running)
            GlowProgressBar(value: job.progress ?? 0, height: 5)
          else
            GlowProgressBar(value: 1, height: 5, colors: [color, color]),
          const SizedBox(height: 10),
          Container(
            height: 160,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HudColors.overlay.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              reverse: true,
              children: [
                for (final l in job.log.reversed.take(200))
                  Text(
                    l,
                    style: HudTheme.telemetry(
                      size: 11,
                      color: HudColors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
