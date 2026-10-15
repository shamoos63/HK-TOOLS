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
    if (restore.status != JobStatus.idle) return _Progress(state: restore);
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
          title: 'Firmware for ${d.displayName}',
          icon: Icons.system_update_alt_rounded,
          trailing: NeonButton(
            label: 'Browse for IPSW…',
            icon: Icons.folder_open_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _browse,
          ),
          child: type == null
              ? const Text(
                  'The device model could not be identified.',
                  style: TextStyle(color: HudColors.warning),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'IPSW files in your repository that restore $type'
                      '${current == null ? '' : ' (currently iOS $current)'}. '
                      'Only firmware Apple is still signing can be installed.',
                      style: const TextStyle(
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
          title: 'Restore type',
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeOption(
                title: 'Update',
                subtitle:
                    'Installs the firmware and keeps apps, data and settings.',
                selected: !erase,
                enabled: updateAllowed && !downgrade,
                onTap: () => setState(() => _erase = false),
              ),
              const SizedBox(height: 8),
              _ModeOption(
                title: 'Erase and restore',
                subtitle:
                    'Wipes everything and installs a clean system. Required for downgrades '
                    'and for devices in DFU mode.',
                selected: erase,
                danger: true,
                onTap: () => setState(() => _erase = true),
              ),
              if (downgrade)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Selected firmware is older than the installed iOS: only an erase '
                    'restore is possible, and only while Apple still signs it.',
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
            label: erase ? 'Erase & flash' : 'Update firmware',
            icon: Icons.bolt_rounded,
            variant: erase ? NeonVariant.danger : NeonVariant.primary,
            onPressed: selected == null || selected.signed == false
                ? null
                : () => _start(selected, erase),
          ),
        ),
        if (selected?.signed == false)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Apple no longer signs this build: the restore would fail at the signing step.',
              textAlign: TextAlign.right,
              style: TextStyle(color: HudColors.danger, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Future<void> _browse() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Firmware', extensions: ['ipsw']),
      ],
    );
    if (file == null || !mounted) return;
    try {
      final m = await IpswManifestReader.readFile(file.path);
      final type = productType;
      if (type != null && !m.supportedProductTypes.contains(type)) {
        throw Exception(
          'This IPSW is for ${m.supportedProductTypes.take(4).join(', ')}'
          '${m.supportedProductTypes.length > 4 ? '…' : ''}, not $type.',
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
          ? 'Erase ${d.displayName} and install iOS ${c.version}?'
          : 'Update ${d.displayName} to iOS ${c.version}?',
      message: [
        if (erase) 'ALL DATA ON THE DEVICE WILL BE ERASED. Back it up first (Backup tab).',
        'Keep the cable connected and the computer awake until the restore finishes '
            '(usually 10–25 minutes). Unplugging mid-way leaves the device in Recovery mode.',
        if (erase) 'After an erase, Activation Lock asks for the Apple ID that owns the device.',
        if (Platform.isWindows) 'Windows: Apple Devices / iTunes must be installed for the Recovery and DFU USB drivers.',
      ].join('\n\n'),
      confirmLabel: erase ? 'Erase & flash' : 'Start update',
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
                  : Colors.white.withValues(alpha: 0.06),
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
                  style: const TextStyle(
                    color: HudColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                formatBytes(c.size, decimals: 1),
                style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
              ),
              const SizedBox(width: 8),
              if (c.integrity == Integrity.verified)
                const HudPill('SHA1 ✓', color: HudColors.success)
              else if (c.integrity == Integrity.mismatch ||
                  c.integrity == Integrity.sizeMismatch)
                const HudPill('Corrupt', color: HudColors.danger),
              const SizedBox(width: 6),
              HudPill(
                switch (c.signed) {
                  true => 'Signed',
                  false => 'Unsigned',
                  null => 'Signing unknown',
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No local firmware, and the catalog has no signed build for this device yet.',
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
          const Icon(Icons.cloud_download_rounded, color: HudColors.purple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUnsigned
                      ? 'Latest signed firmware is not in your repository'
                      : 'No firmware for this device in your repository',
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
              label: 'Download',
              icon: Icons.download_rounded,
              compact: true,
              onPressed: () => queueIpswDownloads(context, ref, [group]),
            )
          else if (task.status != DownloadStatus.completed)
            NeonButton(
              label: 'View in Downloads',
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
                  : Colors.white.withValues(alpha: 0.07),
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
                      style: const TextStyle(
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
      title: 'Before you start',
      icon: Icons.checklist_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (level != null)
            item(
              level >= 30,
              'Battery at $level%${level < 30 ? ': charge to 30% or more first' : ''}',
            ),
          if (erase)
            item(null, 'Back up the device first: an erase cannot be undone.'),
          if (erase)
            item(
              null,
              'Know the Apple ID password: Activation Lock applies after an erase.',
            ),
          item(
            null,
            'Use a direct USB cable (no hubs) and keep the computer from sleeping.',
          ),
          item(
            null,
            'Free disk space: the restore cache needs about as much space as the IPSW.',
          ),
        ],
      ),
    );
  }
}

class _Progress extends ConsumerWidget {
  const _Progress({required this.state});

  final RestoreState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(restoreProvider.notifier);
    final req = state.request!;
    final color = switch (state.status) {
      JobStatus.succeeded => HudColors.success,
      JobStatus.failed => HudColors.danger,
      _ => HudColors.cyan,
    };
    final elapsed = (state.finishedAt ?? DateTime.now()).difference(
      state.startedAt ?? DateTime.now(),
    );
    return ListView(
      children: [
        GlassPanel(
          glow: state.running,
          borderColor: color.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (state.running)
                    PulseDot(color: color)
                  else
                    Icon(
                      state.status == JobStatus.succeeded
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: color,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      switch (state.status) {
                        JobStatus.succeeded => 'Restore complete',
                        JobStatus.failed => 'Restore failed',
                        _ =>
                          req.erase
                              ? 'Erasing and flashing firmware…'
                              : 'Updating firmware…',
                      },
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: HudTheme.telemetry(size: 14, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${req.device.displayName} · ${p.basename(req.ipswPath)}',
                style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
              ),
              const SizedBox(height: 14),
              if (state.running) ...[
                Row(
                  children: [
                    Text(
                      state.step?.label ?? 'Starting…',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      '${(state.fraction * 100).toStringAsFixed(0)}%',
                      style: HudTheme.telemetry(size: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GlowProgressBar(value: state.fraction, height: 6),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in RestoreStep.values)
                    if (state.stepsSeen.contains(s))
                      HudPill(
                        s.label,
                        color: s == state.step && state.running
                            ? HudColors.cyan
                            : HudColors.success,
                        icon: s == state.step && state.running
                            ? Icons.sync_rounded
                            : Icons.check_rounded,
                        mono: false,
                      ),
                ],
              ),
              const SizedBox(height: 14),
              if (state.running)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Do not disconnect the device. Device detection is paused until the restore ends.',
                        style: TextStyle(
                          color: HudColors.warning,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    NeonButton(
                      label: 'Abort',
                      variant: NeonVariant.danger,
                      compact: true,
                      onPressed: () async {
                        if (await confirmDialog(
                          context,
                          title: 'Abort the restore?',
                          message:
                              'Stopping now can leave the device in Recovery mode with no working '
                              'system. It will then need another restore.',
                          confirmLabel: 'Abort',
                          danger: true,
                          typeToConfirm: 'ABORT',
                        )) {
                          ctl.abort();
                        }
                      },
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.status == JobStatus.succeeded
                            ? 'The device is rebooting. Finish setup on the device.'
                            : 'Check the log below. A device left in Recovery mode can be restored again.',
                        style: const TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (req.logFile != null)
                      NeonButton(
                        label: 'Open log file',
                        variant: NeonVariant.ghost,
                        compact: true,
                        onPressed: () => revealPath(req.logFile!),
                      ),
                    const SizedBox(width: 8),
                    NeonButton(
                      label: 'Done',
                      compact: true,
                      onPressed: ctl.reset,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DeviceCard(
          title: 'idevicerestore output',
          icon: Icons.terminal_rounded,
          child: Container(
            height: 320,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectionArea(
              child: ListView(
                reverse: true,
                children: [
                  for (final l in state.log.reversed)
                    Text(
                      l.line,
                      style: HudTheme.telemetry(
                        size: 11.5,
                        color: l.isError
                            ? HudColors.danger
                            : HudColors.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MissingRestoreTool extends StatelessWidget {
  const _MissingRestoreTool();

  @override
  Widget build(BuildContext context) => DeviceCard(
    title: 'idevicerestore not found',
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
