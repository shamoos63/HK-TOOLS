import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/download_task.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/catalog/catalog_index.dart';
import '../../../services/device/device_toolchain.dart';
import '../../../services/repository/ipsw_manifest_reader.dart';
import '../../../services/repository/repository_inventory.dart';
import '../../../services/restore/restore_runner.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/download_feedback.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import 'restore_progress.dart';
import '../../../core/l10n/l10n.dart';

/// An IPSW that can restore the selected device.
class _Candidate {
  const _Candidate({
    required this.path,
    required this.version,
    required this.build,
    required this.size,
    this.signed,
    this.integrity,
  });

  final String path;
  final String version;
  final String build;
  final int size;

  /// From the IPSW.me catalog; `null` when the build is not in the catalog.
  final bool? signed;
  final Integrity? integrity;
}

/// Flash an IPSW with idevicerestore: pick a compatible firmware from the
/// repository (or any file), choose update vs. erase, and follow the restore.
class RestoreTab extends ConsumerWidget {
  const RestoreTab({super.key, required this.device});

  /// `null` while a restore runs and the device is between modes.
  final ConnectedDevice? device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restore = ref.watch(restoreProvider);
    if (restore.status != JobStatus.idle) {
      return RestoreProgressView(state: restore);
    }
    if (device == null) return const SizedBox.shrink();
    if (!ref.watch(deviceToolchainProvider).has(DeviceTool.idevicerestore)) {
      return const _MissingRestoreTool();
    }
    return _Setup(device: device!);
  }
}

class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  String? _selected;
  bool _erase = false;
  _Candidate? _custom;

  ConnectedDevice get d => widget.device;
  String? get productType => d.productType ?? d.info?.productType;

  List<_Candidate> _candidates() {
    final type = productType;
    if (type == null) return const [];
    final index = ref.watch(catalogIndexProvider);
    final inv = ref.watch(inventoryProvider);
    final releases = index.groupsForDevice(type);
    bool? signedFor(String build) => releases
        .where((g) => g.release.buildId == build)
        .firstOrNull
        ?.release
        .signed;
    final out = <_Candidate>[
      for (final PhysicalFile f in inv.files)
        if (f.deviceIdentifiers.contains(type) &&
            f.integrity != Integrity.unreadable)
          _Candidate(
            path: f.primary.path,
            version: f.version,
            build: f.buildId,
            size: f.size,
            signed: signedFor(f.buildId),
            integrity: f.integrity,
          ),
    ];
    out.sort((a, b) => CatalogIndex.compareVersions(b.version, a.version));
    final custom = _custom;
    if (custom != null && !out.any((c) => c.path == custom.path)) {
      out.insert(0, custom);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    final selected =
        candidates.where((c) => c.path == _selected).firstOrNull ??
        candidates.where((c) => c.signed == true).firstOrNull;
    final type = productType;
    final current = d.info?.productVersion;
    final downgrade =
        selected != null &&
        current != null &&
        CatalogIndex.compareVersions(selected.version, current) < 0;
    final updateAllowed = d.mode.isBooted || d.mode == DeviceMode.recovery;
    final erase = _erase || !updateAllowed || downgrade;

    return ListView(
      children: [
        DeviceCard(
          title: trf('Firmware for {0}', [d.displayName]),
          icon: Icons.system_update_alt_rounded,
          trailing: NeonButton(
            label: tr('Browse for IPSW…'),
            icon: Icons.folder_open_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _browse,
          ),
          child: type == null
              ? Text(
                  tr('The device model could not be identified.'),
                  style: TextStyle(color: HudColors.warning),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      trf(
                        'IPSW files in your repository that restore {0}{1}. Only firmware Apple is still signing can be installed.',
                        [
                          type,
                          current == null ? '' : ' (currently iOS $current)',
                        ],
                      ),
                      style: TextStyle(
                        color: HudColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (candidates.isEmpty) _NoLocalFirmware(productType: type),
                    for (final c in candidates)
                      _CandidateRow(
                        candidate: c,
                        selected: c.path == selected?.path,
                        onTap: () => setState(() => _selected = c.path),
                      ),
                    if (candidates.isNotEmpty &&
                        !candidates.any((c) => c.signed == true))
                      _NoLocalFirmware(productType: type, hasUnsigned: true),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        DeviceCard(
          title: tr('Restore type'),
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeOption(
                title: tr('Update'),
                subtitle: tr(
                  'Installs the firmware and keeps apps, data and settings.',
                ),
                selected: !erase,
                enabled: updateAllowed && !downgrade,
                onTap: () => setState(() => _erase = false),
              ),
              const SizedBox(height: 8),
              _ModeOption(
                title: tr('Erase and restore'),
                subtitle: tr(
                  'Wipes everything and installs a clean system. Required for downgrades and for devices in DFU mode.',
                ),
                selected: erase,
                danger: true,
                onTap: () => setState(() => _erase = true),
              ),
              if (downgrade)
                Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    tr(
                      'Selected firmware is older than the installed iOS: only an erase restore is possible, and only while Apple still signs it.',
                    ),
                    style: TextStyle(color: HudColors.warning, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Checklist(device: d, erase: erase),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: NeonButton(
            label: erase ? tr('Erase & flash') : tr('Update firmware'),
            icon: Icons.bolt_rounded,
            variant: erase ? NeonVariant.danger : NeonVariant.primary,
            onPressed: selected == null || selected.signed == false
                ? null
                : () => _start(selected, erase),
          ),
        ),
        if (selected?.signed == false)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              tr(
                'Apple no longer signs this build: the restore would fail at the signing step.',
              ),
              textAlign: TextAlign.right,
              style: TextStyle(color: HudColors.danger, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Future<void> _browse() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('Firmware'), extensions: ['ipsw']),
      ],
    );
    if (file == null || !mounted) return;
    try {
      final m = await IpswManifestReader.readFile(file.path);
      final type = productType;
      if (type != null && !m.supportedProductTypes.contains(type)) {
        throw Exception(
          trf('This IPSW is for {0}{1}, not {2}.', [
            m.supportedProductTypes.take(4).join(', '),
            m.supportedProductTypes.length > 4 ? '…' : '',
            type,
          ]),
        );
      }
      final releases = type == null
          ? const []
          : ref.read(catalogIndexProvider).groupsForDevice(type);
      setState(() {
        _custom = _Candidate(
          path: file.path,
          version: m.productVersion,
          build: m.buildVersion,
          size: File(file.path).lengthSync(),
          signed: releases
              .where((g) => g.release.buildId == m.buildVersion)
              .firstOrNull
              ?.release
              .signed,
        );
        _selected = file.path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: HudColors.danger.withValues(alpha: 0.9),
        ),
      );
    }
  }

  Future<void> _start(_Candidate c, bool erase) async {
    final ok = await confirmDialog(
      context,
      title: erase
          ? trf('Erase {0} and install iOS {1}?', [d.displayName, c.version])
          : trf('Update {0} to iOS {1}?', [d.displayName, c.version]),
      message: [
        if (erase)
          tr(
            'ALL DATA ON THE DEVICE WILL BE ERASED. Back it up first (Backup tab).',
          ),
        tr(
          'Keep the cable connected and the computer awake until the restore finishes (usually 10–25 minutes). Unplugging mid-way leaves the device in Recovery mode.',
        ),
        if (erase)
          tr(
            'After an erase, Activation Lock asks for the Apple ID that owns the device.',
          ),
        if (Platform.isWindows)
          tr(
            'Windows: Apple Devices / iTunes must be installed for the Recovery and DFU USB drivers.',
          ),
      ].join('\n\n'),
      confirmLabel: erase ? tr('Erase & flash') : tr('Start update'),
      danger: erase,
      typeToConfirm: erase ? 'ERASE' : null,
    );
    if (!ok || !mounted) return;
    final ctl = ref.read(restoreProvider.notifier);
    await ctl.start(
      RestoreRequest(
        ipswPath: c.path,
        device: d,
        erase: erase,
        cacheDirectory: ctl.cacheDirectory,
        logFile: ctl.newLogFile(),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final _Candidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected ? HudColors.cyan.withValues(alpha: 0.08) : null,
            border: Border.all(
              color: selected
                  ? HudColors.cyan.withValues(alpha: 0.45)
                  : HudColors.overlay.withValues(alpha: 0.06),
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
              SizedBox(
                width: 150,
                child: Text(
                  '${c.version} (${c.build})',
                  style: HudTheme.telemetry(
                    size: 13,
                    color: HudColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  p.basename(c.path),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: HudColors.textMuted, fontSize: 12),
                ),
              ),
              Text(
                formatBytes(c.size, decimals: 1),
                style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
              ),
              const SizedBox(width: 8),
              if (c.integrity == Integrity.verified)
                HudPill(tr('SHA1 ✓'), color: HudColors.success)
              else if (c.integrity == Integrity.mismatch ||
                  c.integrity == Integrity.sizeMismatch)
                HudPill(tr('Corrupt'), color: HudColors.danger),
              const SizedBox(width: 6),
              HudPill(
                switch (c.signed) {
                  true => tr('Signed'),
                  false => tr('Unsigned'),
                  null => tr('Signing unknown'),
                },
                color: switch (c.signed) {
                  true => HudColors.success,
                  false => HudColors.danger,
                  null => HudColors.warning,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoLocalFirmware extends ConsumerWidget {
  const _NoLocalFirmware({required this.productType, this.hasUnsigned = false});

  final String productType;
  final bool hasUnsigned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(catalogIndexProvider).latestSigned(productType);
    if (group == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          tr(
            'No local firmware, and the catalog has no signed build for this device yet.',
          ),
          style: TextStyle(color: HudColors.textMuted, fontSize: 12.5),
        ),
      );
    }
    final task = ref.watch(payloadTasksProvider)[group.payloadKey];
    final r = group.release;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: HudColors.purple.withValues(alpha: 0.08),
        border: Border.all(color: HudColors.purple.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_download_rounded, color: HudColors.purple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUnsigned
                      ? tr('Latest signed firmware is not in your repository')
                      : tr('No firmware for this device in your repository'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${r.platform.label} ${r.version} (${r.buildId}) · ${formatBytes(r.fileSize, decimals: 1)}',
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textMuted,
                  ),
                ),
                if (task != null &&
                    task.status != DownloadStatus.completed) ...[
                  const SizedBox(height: 6),
                  GlowProgressBar(value: task.fraction, height: 4),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (task == null)
            NeonButton(
              label: tr('Download'),
              icon: Icons.download_rounded,
              compact: true,
              onPressed: () => queueIpswDownloads(context, ref, [group]),
            )
          else if (task.status != DownloadStatus.completed)
            NeonButton(
              label: tr('View in Downloads'),
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () =>
                  ref.read(sectionProvider.notifier).set(AppSection.queue),
            ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? HudColors.danger : HudColors.cyan;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? color.withValues(alpha: 0.08) : null,
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : HudColors.overlay.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? color : HudColors.textMuted,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: HudColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checklist extends ConsumerWidget {
  const _Checklist({required this.device, required this.erase});

  final ConnectedDevice device;
  final bool erase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = device.mode.isBooted && device.pairState == PairState.paired
        ? ref.watch(deviceBatteryProvider(device.id)).value
        : null;
    final level = battery?.level;
    Widget item(bool? ok, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ok == null
                ? Icons.info_outline_rounded
                : ok
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 16,
            color: ok == null
                ? HudColors.textMuted
                : ok
                ? HudColors.success
                : HudColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
    return DeviceCard(
      title: tr('Before you start'),
      icon: Icons.checklist_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (level != null)
            item(
              level >= 30,
              trf('Battery at {0}%{1}', [
                level,
                level < 30 ? tr(': charge to 30% or more first') : '',
              ]),
            ),
          if (erase)
            item(
              null,
              tr('Back up the device first: an erase cannot be undone.'),
            ),
          if (erase)
            item(
              null,
              tr(
                'Know the Apple ID password: Activation Lock applies after an erase.',
              ),
            ),
          item(
            null,
            tr(
              'Use a direct USB cable (no hubs) and keep the computer from sleeping.',
            ),
          ),
          item(
            null,
            tr(
              'Free disk space: the restore cache needs about as much space as the IPSW.',
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingRestoreTool extends StatelessWidget {
  const _MissingRestoreTool();

  @override
  Widget build(BuildContext context) => DeviceCard(
    title: tr('idevicerestore not found'),
    icon: Icons.build_circle_outlined,
    child: SelectableText(
      Platform.isWindows
          ? 'Place idevicerestore.exe (with its DLLs) in the device tools folder '
                '(Settings › Device tools), next to the other libimobiledevice tools.'
          : 'Build it from github.com/libimobiledevice/idevicerestore:\n'
                '  brew install libtatsu libzip openssl@3 autoconf automake libtool pkgconf\n'
                '  git clone https://github.com/libimobiledevice/idevicerestore\n'
                '  cd idevicerestore && ./autogen.sh && make && sudo make install\n'
                'or choose its folder in Settings › Device tools.',
      style: HudTheme.telemetry(size: 12, color: HudColors.textPrimary),
    ),
  );
}
