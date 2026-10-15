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
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HealthPanel(),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TabButton(
                    label: 'Inventory',
                    count: inv.files.length,
                    active: _tab == _Tab.inventory,
                    onTap: () => setState(() => _tab = _Tab.inventory),
                  ),
                  _TabButton(
                    label: 'Missing firmware',
                    count: missingCount,
                    color: missingCount > 0 ? HudColors.warning : null,
                    active: _tab == _Tab.missing,
                    onTap: () => setState(() => _tab = _Tab.missing),
                  ),
                  _TabButton(
                    label: 'Duplicates',
                    count: inv.duplicates.length,
                    color: inv.duplicates.isNotEmpty ? HudColors.purple : null,
                    active: _tab == _Tab.duplicates,
                    onTap: () => setState(() => _tab = _Tab.duplicates),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_tab) {
                  _Tab.inventory => const _InventoryTab(),
                  _Tab.missing => const _MissingTab(),
                  _Tab.duplicates => const _DuplicatesTab(),
                },
              ),
            ],
          ),
          if (_tab == _Tab.missing)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SelectionBar(),
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storage_rounded,
                color: HudColors.cyan,
                size: 22,
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 3),
                    Text(
                      state.error ??
                          (state.scanning
                              ? 'Scanning ${state.done}/${state.total}'
                                    '${state.currentPath == null ? '' : ' · ${p.basename(state.currentPath!)}'}'
                              : state.scannedAt == null
                              ? 'Not scanned yet'
                              : 'Scanned ${_time(state.scannedAt!)} · ${inv.pathCount} paths on disk'),
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
                label: 'Change folder',
                icon: Icons.folder_open_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: () async {
                  final picked = await getDirectoryPath(
                    initialDirectory: folder,
                    confirmButtonText: 'Use folder',
                  );
                  if (picked != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(targetDirectory: picked));
                  }
                },
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: state.scanning ? 'Scanning…' : 'Rescan',
                icon: Icons.radar_rounded,
                compact: true,
                onPressed: state.scanning
                    ? null
                    : ref.read(repositoryProvider.notifier).scan,
              ),
            ],
          ),
          if (state.skipped.isNotEmpty || state.accessDenied) ...[
            const SizedBox(height: 12),
            _AccessBanner(
              skipped: state.skipped,
              rootDenied: state.accessDenied,
              folder: folder,
            ),
          ],
          if (state.scanning) ...[
            const SizedBox(height: 10),
            GlowProgressBar(
              value: state.total == 0 ? 0 : state.done / state.total,
              height: 3,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric('Files', '${inv.files.length}', HudColors.cyan),
              _Metric(
                'On disk',
                formatBytes(inv.physicalBytes, decimals: 1),
                HudColors.cyan,
              ),
              _Metric(
                'Identified',
                '${inv.identifiedCount}/${inv.files.length}',
                HudColors.textPrimary,
              ),
              _Metric(
                'SHA1 verified',
                '${inv.verifiedCount}',
                HudColors.success,
              ),
              _Metric(
                'Issues',
                '${inv.problemCount}',
                inv.problemCount > 0 ? HudColors.danger : HudColors.textMuted,
              ),
              _Metric(
                'Reclaimable',
                formatBytes(inv.reclaimableBytes, decimals: 1),
                inv.reclaimableBytes > 0
                    ? HudColors.purple
                    : HudColors.textMuted,
              ),
              _Metric(
                'Up to date',
                '${missing.upToDate} devices',
                HudColors.success,
              ),
              _Metric(
                'Missing latest',
                '${missing.missing.fold<int>(0, (s, m) => s + m.devices.length)} devices',
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
        const SizedBox(height: 4),
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
    padding: const EdgeInsets.only(right: 8),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: active
                ? HudColors.cyan.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: active
                  ? HudColors.cyan.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
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
              const SizedBox(width: 8),
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
          title: state.scanning ? 'Scanning…' : 'No .ipsw files in this folder',
          message:
              'Downloads land here automatically. You can also point the repository at an '
              'existing firmware folder with "Change folder".',
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
                  'Each row is one physical file; hardlinked names are counted as links, not copies.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: HudColors.textMuted,
                  ),
                ),
              ),
              NeonButton(
                label: unverified.isEmpty
                    ? (inv.verifiedCount == inv.files.length
                          ? 'All verified'
                          : 'Nothing to verify')
                    : 'Verify ${unverified.length} (${formatBytes(unverifiedBytes, decimals: 1)})',
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
          const SizedBox(height: 10),
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
      Integrity.verified => ('SHA1 OK', HudColors.success),
      Integrity.mismatch => ('SHA1 MISMATCH', HudColors.danger),
      Integrity.sizeMismatch => ('SIZE MISMATCH', HudColors.danger),
      Integrity.unreadable => ('UNREADABLE', HudColors.danger),
      Integrity.unverified => ('UNVERIFIED', HudColors.textMuted),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color:
              f.integrity == Integrity.verified ||
                  f.integrity == Integrity.unverified
              ? Colors.white.withValues(alpha: 0.06)
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
                  '${f.platform?.label ?? 'Unknown'} ${f.version}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
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
                const SizedBox(height: 3),
                Text(
                  f.group == null && f.primary.manifestError != null
                      ? f.primary.manifestError!
                      : names.isEmpty
                      ? 'Not in IPSW.me catalog'
                      : names.length <= 3
                      ? names.join(' · ')
                      : '${names.take(3).join(' · ')} · +${names.length - 3}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
                '${f.links.length} LINKS',
                color: HudColors.purple,
                icon: Icons.link_rounded,
              ),
            ),
            const SizedBox(width: 8),
          ],
          HudPill(
            switch (f.method) {
              MatchMethod.manifest => 'MANIFEST',
              MatchMethod.fileName => 'FILENAME',
              MatchMethod.none => 'UNMATCHED',
            },
            color: f.method == MatchMethod.none
                ? HudColors.warning
                : HudColors.textMuted,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              formatBytes(f.size),
              textAlign: TextAlign.right,
              style: HudTheme.telemetry(size: 12, color: HudColors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 128,
            child: hashing != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HASHING ${(hashing * 100).toStringAsFixed(0)}%',
                        style: HudTheme.telemetry(size: 10.5),
                      ),
                      const SizedBox(height: 4),
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
                ? 'Create $linksToMake per-device hardlink${linksToMake == 1 ? '' : 's'} in "$deviceLinksFolder" (no extra space)'
                : 'Per-device links in place',
            color: linksToMake > 0 ? HudColors.purple : HudColors.textMuted,
            onPressed: busy || linksToMake <= 0 || f.deviceIdentifiers.isEmpty
                ? null
                : () => _run(context, () async {
                    final n = await ref
                        .read(repositoryProvider.notifier)
                        .createDeviceLinks(f);
                    return 'Created $n device link${n == 1 ? '' : 's'}';
                  }),
          ),
          HudIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: 'Reveal',
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
                  label: 'Show missing $label',
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
              const Text(
                'Only devices in repository',
                style: TextStyle(fontSize: 12, color: HudColors.textMuted),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _onlyOwned,
                  onChanged: (v) => setState(() => _onlyOwned = v),
                  activeThumbColor: HudColors.cyan,
                  activeTrackColor: HudColors.cyan.withValues(alpha: 0.3),
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
                      ? '${r.upToDate} devices have their latest signed firmware.'
                      : '$devices devices lack their latest signed IPSW → ${r.missing.length} unique '
                            'payloads (${formatBytes(bytes, decimals: 1)}). ${r.upToDate} devices up to date.',
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textMuted,
                  ),
                ),
              ),
              NeonButton(
                label: 'Queue all missing (${r.missing.length})',
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
                              'Queued ${tasks.length} payloads (${formatBytes(bytes, decimals: 1)})',
                            ),
                            action: SnackBarAction(
                              label: 'VIEW',
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
                ? const EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'Nothing missing for this filter',
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
      return const GlassPanel(
        child: EmptyState(
          icon: Icons.compress_rounded,
          title: 'No duplicate payloads',
          message: 'Every firmware payload is stored once. Per-device names are hardlinks and cost no space.',
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
                  '${inv.duplicates.length} payloads are stored more than once. Merging hashes each copy '
                  '(SHA1 must match), then replaces extras with hardlinks to one file.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: HudColors.textMuted,
                  ),
                ),
              ),
              NeonButton(
                label:
                    'Reclaim all ${formatBytes(inv.reclaimableBytes, decimals: 1)}',
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
                        return 'Reclaimed ${formatBytes(freed, decimals: 1)}';
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
                      color: Colors.white.withValues(alpha: 0.02),
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
                                '${d.group.release.platform.label} ${d.group.release.version} '
                                '(${d.group.release.buildId}) × ${d.files.length} copies',
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
                                          'SHA1 ${(h * 100).toStringAsFixed(0)}%',
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
                          'SAVES ${formatBytes(d.reclaimableBytes, decimals: 1)}',
                          color: HudColors.purple,
                        ),
                        const SizedBox(width: 10),
                        NeonButton(
                          label: busy.contains(d.group.payloadKey)
                              ? 'Merging…'
                              : 'Merge',
                          variant: NeonVariant.ghost,
                          compact: true,
                          onPressed: busy.isNotEmpty
                              ? null
                              : () => _run(context, () async {
                                  final freed = await ref
                                      .read(repositoryProvider.notifier)
                                      .reclaim(d);
                                  return 'Reclaimed ${formatBytes(freed, decimals: 1)}';
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
        ? 'Access to this folder was denied, so nothing could be scanned.'
        : 'Skipped ${skipped.length} unreadable '
              '${skipped.length == 1 ? 'location' : 'locations'} '
              '(no permission). Everything else was scanned.';
    final hint = Platform.isMacOS
        ? 'Allow "HK Tools" under System Settings › Privacy & Security › '
              'Files & Folders (or Full Disk Access for external / network drives), then Rescan.'
        : 'Check the folder\'s Properties › Security tab for your account, then Rescan.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: HudColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: HudColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: HudColors.warning,
            size: 20,
          ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: HudColors.textMuted,
                  ),
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
                            ? ' · +${skipped.length - 3} more'
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
              label: 'Open Privacy settings',
              icon: Icons.privacy_tip_outlined,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => Process.run('open', [
                'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
              ]),
            )
          else
            NeonButton(
              label: 'Open folder',
              icon: Icons.folder_open_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => Process.run('explorer.exe', [folder]),
            ),
          const SizedBox(width: 8),
          NeonButton(
            label: 'Rescan',
            icon: Icons.refresh_rounded,
            compact: true,
            onPressed: ref.read(repositoryProvider.notifier).scan,
          ),
        ],
      ),
    );
  }
}
