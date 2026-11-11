import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/platform_type.dart';
import '../../../services/repository/repository_inventory.dart';
import '../../providers/core_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/download_feedback.dart';
import '../../widgets/hud_widgets.dart';
import '../library/firmware_group_tile.dart';
import '../library/library_screen.dart';
import '../library/selection_bar.dart';
import '../../../core/l10n/l10n.dart';

enum _Tab { inventory, missing, duplicates }

class RepositoryScreen extends ConsumerStatefulWidget {
  const RepositoryScreen({super.key});

  @override
  ConsumerState<RepositoryScreen> createState() => _RepositoryScreenState();
}

class _RepositoryScreenState extends ConsumerState<RepositoryScreen> {
  _Tab _tab = _Tab.inventory;

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventoryProvider);
    final missingCount = inv.missingLatest().missing.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HealthPanel(),
              SizedBox(height: 14),
              Row(
                children: [
                  _TabButton(
                    label: tr('Inventory'),
                    count: inv.files.length,
                    active: _tab == _Tab.inventory,
                    onTap: () => setState(() => _tab = _Tab.inventory),
                  ),
                  _TabButton(
                    label: tr('Missing firmware'),
                    count: missingCount,
                    color: missingCount > 0 ? HudColors.warning : null,
                    active: _tab == _Tab.missing,
                    onTap: () => setState(() => _tab = _Tab.missing),
                  ),
                  _TabButton(
                    label: tr('Duplicates'),
                    count: inv.duplicates.length,
                    color: inv.duplicates.isNotEmpty ? HudColors.purple : null,
                    active: _tab == _Tab.duplicates,
                    onTap: () => setState(() => _tab = _Tab.duplicates),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Expanded(
                child: switch (_tab) {
                  _Tab.inventory => _InventoryTab(),
                  _Tab.missing => _MissingTab(),
                  _Tab.duplicates => _DuplicatesTab(),
                },
              ),
            ],
          ),
          if (_tab == _Tab.missing)
            Positioned(left: 0, right: 0, bottom: 0, child: SelectionBar()),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Health header
// -----------------------------------------------------------------------------

class _HealthPanel extends ConsumerWidget {
  const _HealthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final inv = ref.watch(inventoryProvider);
    final folder = ref.watch(settingsProvider.select((s) => s.targetDirectory));
    final missing = inv.missingLatest();

    return GlassPanel(
      glow: state.scanning,
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.storage_rounded, color: HudColors.cyan, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder,
                      overflow: TextOverflow.ellipsis,
                      style: HudTheme.telemetry(
                        size: 14,
                        color: HudColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      state.error ??
                          (state.scanning
                              ? trf('Scanning {0}/{1}{2}', [
                                  state.done,
                                  state.total,
                                  state.currentPath == null
                                      ? ''
                                      : ' · ${p.basename(state.currentPath!)}',
                                ])
                              : state.scannedAt == null
                              ? tr('Not scanned yet')
                              : trf('Scanned {0} · {1} paths on disk', [
                                  _time(state.scannedAt!),
                                  inv.pathCount,
                                ])),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: state.error != null
                            ? HudColors.danger
                            : HudColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              NeonButton(
                label: tr('Change folder'),
                icon: Icons.folder_open_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: () async {
                  final picked = await getDirectoryPath(
                    initialDirectory: folder,
                    confirmButtonText: tr('Use folder'),
                  );
                  if (picked != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(targetDirectory: picked));
                  }
                },
              ),
              SizedBox(width: 10),
              NeonButton(
                label: state.scanning ? tr('Scanning…') : tr('Rescan'),
                icon: Icons.radar_rounded,
                compact: true,
                onPressed: state.scanning
                    ? null
                    : ref.read(repositoryProvider.notifier).scan,
              ),
            ],
          ),
          if (state.skipped.isNotEmpty || state.accessDenied) ...[
            SizedBox(height: 12),
            _AccessBanner(
              skipped: state.skipped,
              rootDenied: state.accessDenied,
              folder: folder,
            ),
          ],
          if (state.scanning) ...[
            SizedBox(height: 10),
            GlowProgressBar(
              value: state.total == 0 ? 0 : state.done / state.total,
              height: 3,
            ),
          ],
          SizedBox(height: 14),
          Row(
            children: [
              _Metric(tr('Files'), '${inv.files.length}', HudColors.cyan),
              _Metric(
                tr('On disk'),
                formatBytes(inv.physicalBytes, decimals: 1),
                HudColors.cyan,
              ),
              _Metric(
                tr('Identified'),
                '${inv.identifiedCount}/${inv.files.length}',
                HudColors.textPrimary,
              ),
              _Metric(
                tr('SHA1 verified'),
                '${inv.verifiedCount}',
                HudColors.success,
              ),
              _Metric(
                tr('Issues'),
                '${inv.problemCount}',
                inv.problemCount > 0 ? HudColors.danger : HudColors.textMuted,
              ),
              _Metric(
                tr('Reclaimable'),
                formatBytes(inv.reclaimableBytes, decimals: 1),
                inv.reclaimableBytes > 0
                    ? HudColors.purple
                    : HudColors.textMuted,
              ),
              _Metric(
                tr('Up to date'),
                trf('{0} devices', [missing.upToDate]),
                HudColors.success,
              ),
              _Metric(
                tr('Missing latest'),
                trf('{0} devices', [
                  missing.missing.fold<int>(0, (s, m) => s + m.devices.length),
                ]),
                missing.missing.isEmpty
                    ? HudColors.textMuted
                    : HudColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HudLabel(label),
        SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HudTheme.telemetry(
            size: 16,
            color: color,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(right: 8),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: active ? HudColors.textPrimary : HudColors.textMuted,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '$count',
                style: HudTheme.telemetry(
                  size: 12,
                  color:
                      color ?? (active ? HudColors.cyan : HudColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Inventory
// -----------------------------------------------------------------------------

class _InventoryTab extends ConsumerWidget {
  const _InventoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventoryProvider);
    final state = ref.watch(repositoryProvider);
    final unverified = inv.files
        .where((f) => f.integrity == Integrity.unverified)
        .toList();
    final unverifiedBytes = unverified.fold<int>(0, (s, f) => s + f.size);

    if (inv.files.isEmpty) {
      return GlassPanel(
        child: EmptyState(
          icon: state.scanning ? Icons.radar_rounded : Icons.folder_off_rounded,
          title: state.scanning
              ? tr('Scanning…')
              : tr('No .ipsw files in this folder'),
          message: tr(
            'Downloads land here automatically. You can also point the repository at an existing firmware folder with "Change folder".',
          ),
        ),
      );
    }

    return GlassPanel(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    'Each row is one physical file; hardlinked names are counted as links, not copies.',
                  ),
                  style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                ),
              ),
              NeonButton(
                label: unverified.isEmpty
                    ? (inv.verifiedCount == inv.files.length
                          ? tr('All verified')
                          : tr('Nothing to verify'))
                    : trf('Verify {0} ({1})', [
                        unverified.length,
                        formatBytes(unverifiedBytes, decimals: 1),
                      ]),
                icon: Icons.fingerprint_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: unverified.isEmpty || state.hashing.isNotEmpty
                    ? null
                    : () => ref
                          .read(repositoryProvider.notifier)
                          .verifyAll(unverified),
              ),
            ],
          ),
          SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: inv.files.length,
              itemBuilder: (_, i) => _InventoryRow(file: inv.files[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryRow extends ConsumerWidget {
  const _InventoryRow({required this.file});

  final PhysicalFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = file;
    final hashing = ref.watch(
      repositoryProvider.select((s) => s.hashing[f.identityId]),
    );
    final busy = ref.watch(
      repositoryProvider.select((s) => s.busy.contains(f.identityId)),
    );
    final index = ref.watch(inventoryProvider.select((i) => i.index));
    final names = f.deviceIdentifiers.map(index.displayName).toSet().toList();
    final linksToMake = f.deviceIdentifiers.toSet().length - f.deviceLinkCount;
    final (iLabel, iColor) = switch (f.integrity) {
      Integrity.verified => (tr('SHA1 OK'), HudColors.success),
      Integrity.mismatch => (tr('SHA1 MISMATCH'), HudColors.danger),
      Integrity.sizeMismatch => (tr('SIZE MISMATCH'), HudColors.danger),
      Integrity.unreadable => (tr('UNREADABLE'), HudColors.danger),
      Integrity.unverified => (tr('UNVERIFIED'), HudColors.textMuted),
    };

    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: HudColors.overlay.withValues(alpha: 0.02),
        border: Border.all(
          color:
              f.integrity == Integrity.verified ||
                  f.integrity == Integrity.unverified
              ? HudColors.overlay.withValues(alpha: 0.06)
              : HudColors.danger.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${f.platform?.label ?? "Unknown"} ${f.version}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text(
                  f.buildId,
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.primary.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  f.group == null && f.primary.manifestError != null
                      ? f.primary.manifestError!
                      : names.isEmpty
                      ? tr('Not in IPSW.me catalog')
                      : names.length <= 3
                      ? names.join(' · ')
                      : '${names.take(3).join(' · ')} · +${names.length - 3}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: HudColors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          if (f.links.length > 1) ...[
            Tooltip(
              message: f.links
                  .map(
                    (l) => p.relative(
                      l.path,
                      from: ref.read(settingsProvider).targetDirectory,
                    ),
                  )
                  .join('\n'),
              child: HudPill(
                trf('{0} LINKS', [f.links.length]),
                color: HudColors.purple,
                icon: Icons.link_rounded,
              ),
            ),
            SizedBox(width: 8),
          ],
          HudPill(
            switch (f.method) {
              MatchMethod.manifest => tr('MANIFEST'),
              MatchMethod.fileName => tr('FILENAME'),
              MatchMethod.none => tr('UNMATCHED'),
            },
            color: f.method == MatchMethod.none
                ? HudColors.warning
                : HudColors.textMuted,
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              formatBytes(f.size),
              textAlign: TextAlign.right,
              style: HudTheme.telemetry(size: 12, color: HudColors.textPrimary),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 128,
            child: hashing != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trf('HASHING {0}%', [
                          (hashing * 100).toStringAsFixed(0),
                        ]),
                        style: HudTheme.telemetry(size: 10.5),
                      ),
                      SizedBox(height: 4),
                      GlowProgressBar(value: hashing, height: 3),
                    ],
                  )
                : HudPill(iLabel, color: iColor),
          ),
          HudIconButton(
            icon: Icons.fingerprint_rounded,
            tooltip: f.sha1 == null ? 'Verify SHA1' : 'SHA1 ${f.sha1}',
            color: f.integrity == Integrity.unverified
                ? HudColors.cyan
                : HudColors.textMuted,
            onPressed:
                f.sha1 != null ||
                    hashing != null ||
                    f.group?.release.sha1sum == null
                ? null
                : () => ref.read(repositoryProvider.notifier).verify(f),
          ),
          HudIconButton(
            icon: Icons.account_tree_rounded,
            tooltip: linksToMake > 0
                ? trf(
                    'Create {0} per-device hardlink{1} in "{2}" (no extra space)',
                    [
                      linksToMake,
                      linksToMake == 1 ? '' : 's',
                      deviceLinksFolder,
                    ],
                  )
                : tr('Per-device links in place'),
            color: linksToMake > 0 ? HudColors.purple : HudColors.textMuted,
            onPressed: busy || linksToMake <= 0 || f.deviceIdentifiers.isEmpty
                ? null
                : () => _run(context, () async {
                    final n = await ref
                        .read(repositoryProvider.notifier)
                        .createDeviceLinks(f);
                    return trf('Created {0} device link{1}', [
                      n,
                      n == 1 ? '' : 's',
                    ]);
                  }),
          ),
          HudIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: tr('Reveal'),
            onPressed: () => _reveal(f.primary.path),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Missing firmware
// -----------------------------------------------------------------------------

class _MissingTab extends ConsumerStatefulWidget {
  const _MissingTab();

  @override
  ConsumerState<_MissingTab> createState() => _MissingTabState();
}

class _MissingTabState extends ConsumerState<_MissingTab> {
  Set<PlatformType> _platforms = {PlatformType.iOS};
  bool _onlyOwned = false;

  static const _filters = <(String, Set<PlatformType>)>[
    ('iOS', {PlatformType.iOS}),
    ('iPadOS', {PlatformType.iPadOS}),
    ('macOS', {PlatformType.macOS}),
    ('All', {}),
  ];

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventoryProvider);
    final r = inv.missingLatest(
      platforms: _platforms,
      onlyDevicesInRepository: _onlyOwned,
    );
    final bytes = r.missing.fold<int>(
      0,
      (s, m) => s + m.group.release.fileSize,
    );
    final devices = r.missing.fold<int>(0, (s, m) => s + m.devices.length);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (label, set) in _filters) ...[
                _TabButton(
                  label: trf('Show missing {0}', [tr(label)]),
                  count: inv
                      .missingLatest(
                        platforms: set,
                        onlyDevicesInRepository: _onlyOwned,
                      )
                      .missing
                      .length,
                  active:
                      _platforms.length == set.length &&
                      _platforms.containsAll(set),
                  onTap: () => setState(() => _platforms = set),
                ),
              ],
              const Spacer(),
              Text(
                tr('Only devices in repository'),
                style: TextStyle(fontSize: 12, color: HudColors.textMuted),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _onlyOwned,
                  onChanged: (v) => setState(() => _onlyOwned = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.missing.isEmpty
                      ? trf('{0} devices have their latest signed firmware.', [
                          r.upToDate,
                        ])
                      : trf(
                          '{0} devices lack their latest signed IPSW → {1} unique payloads ({2}). {3} devices up to date.',
                          [
                            devices,
                            r.missing.length,
                            formatBytes(bytes, decimals: 1),
                            r.upToDate,
                          ],
                        ),
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textMuted,
                  ),
                ),
              ),
              NeonButton(
                label: trf('Queue all missing ({0})', [r.missing.length]),
                icon: Icons.download_for_offline_rounded,
                compact: true,
                onPressed: r.missing.isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final tasks = await queueIpswDownloads(
                          context,
                          ref,
                          r.missing.map((m) => m.group),
                        );
                        if (tasks == null) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              trf('Queued {0} payloads ({1})', [
                                tasks.length,
                                formatBytes(bytes, decimals: 1),
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
          const SizedBox(height: 12),
          const FirmwareColumnHeader(),
          const SizedBox(height: 6),
          Expanded(
            child: r.missing.isEmpty
                ? EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: tr('Nothing missing for this filter'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: r.missing.length,
                    itemBuilder: (_, i) =>
                        FirmwareGroupTile(group: r.missing[i].group),
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Duplicates
// -----------------------------------------------------------------------------

class _DuplicatesTab extends ConsumerWidget {
  const _DuplicatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventoryProvider);
    final busy = ref.watch(repositoryProvider.select((s) => s.busy));
    final hashing = ref.watch(repositoryProvider.select((s) => s.hashing));
    final folder = ref.watch(settingsProvider.select((s) => s.targetDirectory));

    if (inv.duplicates.isEmpty) {
      return GlassPanel(
        child: EmptyState(
          icon: Icons.compress_rounded,
          title: tr('No duplicate payloads'),
          message: tr(
            'Every firmware payload is stored once. Per-device names are hardlinks and cost no space.',
          ),
        ),
      );
    }

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trf(
                    '{0} payloads are stored more than once. Merging hashes each copy (SHA1 must match), then replaces extras with hardlinks to one file.',
                    [inv.duplicates.length],
                  ),
                  style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                ),
              ),
              NeonButton(
                label: trf('Reclaim all {0}', [
                  formatBytes(inv.reclaimableBytes, decimals: 1),
                ]),
                icon: Icons.compress_rounded,
                compact: true,
                onPressed: busy.isNotEmpty
                    ? null
                    : () => _run(context, () async {
                        var freed = 0;
                        for (final d in inv.duplicates) {
                          freed += await ref
                              .read(repositoryProvider.notifier)
                              .reclaim(d);
                        }
                        return trf('Reclaimed {0}', [
                          formatBytes(freed, decimals: 1),
                        ]);
                      }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final d in inv.duplicates)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: HudColors.overlay.withValues(alpha: 0.02),
                      border: Border.all(
                        color: HudColors.purple.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trf('{0} {1} ({2}) × {3} copies', [
                                  d.group.release.platform.label,
                                  d.group.release.version,
                                  d.group.release.buildId,
                                  d.files.length,
                                ]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final (i, f) in d.files.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        i == 0
                                            ? Icons.star_rounded
                                            : Icons.content_copy_rounded,
                                        size: 13,
                                        color: i == 0
                                            ? HudColors.cyan
                                            : HudColors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          p.relative(
                                            f.primary.path,
                                            from: folder,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          style: HudTheme.telemetry(
                                            size: 11.5,
                                            color: HudColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (hashing[f.identityId] case final h?)
                                        Text(
                                          trf('SHA1 {0}%', [
                                            (h * 100).toStringAsFixed(0),
                                          ]),
                                          style: HudTheme.telemetry(size: 11),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        HudPill(
                          trf('SAVES {0}', [
                            formatBytes(d.reclaimableBytes, decimals: 1),
                          ]),
                          color: HudColors.purple,
                        ),
                        const SizedBox(width: 10),
                        NeonButton(
                          label: busy.contains(d.group.payloadKey)
                              ? tr('Merging…')
                              : tr('Merge'),
                          variant: NeonVariant.ghost,
                          compact: true,
                          onPressed: busy.isNotEmpty
                              ? null
                              : () => _run(context, () async {
                                  final freed = await ref
                                      .read(repositoryProvider.notifier)
                                      .reclaim(d);
                                  return trf('Reclaimed {0}', [
                                    formatBytes(freed, decimals: 1),
                                  ]);
                                }),
                        ),
                      ],
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

Future<void> _run(
  BuildContext context,
  Future<String> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    messenger.showSnackBar(SnackBar(content: Text(await action())));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('$e'),
        backgroundColor: HudColors.danger.withValues(alpha: 0.9),
      ),
    );
  }
}

void _reveal(String path) {
  if (Platform.isMacOS) {
    Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    Process.run('explorer.exe', ['/select,', path]);
  }
}

/// Explains permission-skipped paths and links to the fix.
class _AccessBanner extends ConsumerWidget {
  const _AccessBanner({
    required this.skipped,
    required this.rootDenied,
    required this.folder,
  });

  final List<String> skipped;
  final bool rootDenied;
  final String folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = rootDenied
        ? tr('Access to this folder was denied, so nothing could be scanned.')
        : trf(
            'Skipped {0} unreadable {1} (no permission). Everything else was scanned.',
            [skipped.length, skipped.length == 1 ? 'location' : 'locations'],
          );
    final hint = Platform.isMacOS
        ? tr(
            'Allow "HK Tools" under System Settings › Privacy & Security › Files & Folders (or Full Disk Access for external / network drives), then Rescan.',
          )
        : tr(
            'Check the folder\'s Properties › Security tab for your account, then Rescan.',
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: HudColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: HudColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: HudColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                ),
                if (!rootDenied) ...[
                  const SizedBox(height: 4),
                  Text(
                    skipped
                            .take(3)
                            .map(
                              (s) => p.isWithin(folder, s)
                                  ? p.relative(s, from: folder)
                                  : s,
                            )
                            .join(' · ') +
                        (skipped.length > 3
                            ? trf(' · +{0} more', [skipped.length - 3])
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudTheme.telemetry(
                      size: 11,
                      color: HudColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (Platform.isMacOS)
            NeonButton(
              label: tr('Open Privacy settings'),
              icon: Icons.privacy_tip_outlined,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => Process.run('open', [
                'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
              ]),
            )
          else
            NeonButton(
              label: tr('Open folder'),
              icon: Icons.folder_open_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => Process.run('explorer.exe', [folder]),
            ),
          const SizedBox(width: 8),
          NeonButton(
            label: tr('Rescan'),
            icon: Icons.refresh_rounded,
            compact: true,
            onPressed: ref.read(repositoryProvider.notifier).scan,
          ),
        ],
      ),
    );
  }
}
