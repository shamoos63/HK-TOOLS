import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/device.dart';
import '../../../domain/entities/platform_type.dart';
import '../../../services/catalog/catalog_index.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'firmware_group_tile.dart';
import 'search_results_view.dart';
import 'selection_bar.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final searching = ref.watch(searchTextProvider).trim().isNotEmpty;

    if (catalog.value == null) {
      return catalog.hasError
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Catalog unavailable',
              message:
                  'Could not reach api.ipsw.me and no cached catalog exists yet.\n${catalog.error}',
            )
          : const Center(
              child: CircularProgressIndicator(
                color: HudColors.cyan,
                strokeWidth: 2,
              ),
            );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 0,
            child: searching ? const SearchResultsView() : const _BrowseView(),
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: SelectionBar()),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Browse: category tabs → device list → device firmware
// -----------------------------------------------------------------------------

class _BrowseView extends ConsumerWidget {
  const _BrowseView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(catalogIndexProvider);
    final category = ref.watch(libraryCategoryProvider);
    final devices = index.devicesIn(category);
    var selectedId = ref.watch(selectedDeviceProvider);
    if (selectedId == null || !devices.any((d) => d.identifier == selectedId)) {
      selectedId = devices.isEmpty ? null : devices.first.identifier;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: GlassPanel(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryTabs(index: index),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: devices.length,
                    itemExtent: 58,
                    itemBuilder: (_, i) => _DeviceRow(
                      device: devices[i],
                      selected: devices[i].identifier == selectedId,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: selectedId == null
              ? const GlassPanel(
                  child: EmptyState(
                    icon: Icons.devices_other_rounded,
                    title: 'No devices in this category',
                  ),
                )
              : _DeviceDetail(identifier: selectedId),
        ),
      ],
    );
  }
}

class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs({required this.index});

  final CatalogIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(libraryCategoryProvider);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          for (final c in LibraryCategory.values)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  ref.read(libraryCategoryProvider.notifier).set(c);
                  ref.read(selectedDeviceProvider.notifier).set(null);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: c == current
                          ? LinearGradient(
                              colors: [
                                HudColors.cyan.withValues(alpha: 0.22),
                                HudColors.purple.withValues(alpha: 0.22),
                              ],
                            )
                          : null,
                      border: Border.all(
                        color: c == current
                            ? HudColors.cyan.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          c.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: c == current
                                ? HudColors.textPrimary
                                : HudColors.textMuted,
                          ),
                        ),
                        Text(
                          '${index.devicesIn(c).length}',
                          style: HudTheme.telemetry(
                            size: 10,
                            color: c == current
                                ? HudColors.cyan
                                : HudColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({required this.device, required this.selected});

  final Device device;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(catalogIndexProvider);
    final latest = index.latestSigned(device.identifier);
    final loaded = index.hasFirmwares(device.identifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          onTap: () =>
              ref.read(selectedDeviceProvider.notifier).set(device.identifier),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: selected ? HudColors.cyan.withValues(alpha: 0.10) : null,
              border: Border.all(
                color: selected
                    ? HudColors.cyan.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(device),
                  size: 20,
                  color: selected ? HudColors.cyan : HudColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.identifier,
                        style: HudTheme.telemetry(
                          size: 10.5,
                          color: HudColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (latest != null)
                  Text(
                    latest.release.version,
                    style: HudTheme.telemetry(
                      size: 11,
                      color: HudColors.success,
                    ),
                  )
                else if (!loaded)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: HudColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(Device d) => switch (d.platform) {
  PlatformType.iOS =>
    d.identifier.startsWith('iPod')
        ? Icons.music_note_rounded
        : Icons.phone_iphone_rounded,
  PlatformType.iPadOS => Icons.tablet_mac_rounded,
  PlatformType.macOS => Icons.laptop_mac_rounded,
  PlatformType.tvOS => Icons.tv_rounded,
  PlatformType.watchOS => Icons.watch_rounded,
  PlatformType.audioOS => Icons.speaker_rounded,
  PlatformType.visionOS => Icons.vrpano_rounded,
  PlatformType.other => Icons.memory_rounded,
};

class _DeviceDetail extends ConsumerWidget {
  const _DeviceDetail({required this.identifier});

  final String identifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(catalogIndexProvider);
    final device = index.device(identifier)!;
    final signedOnly = ref.watch(signedOnlyProvider);
    final groups = index.groupsForDevice(identifier, signedOnly: signedOnly);
    final signed = index.groupsForDevice(identifier, signedOnly: true);
    final boards = device.boards;

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_iconFor(device), size: 34, color: HudColors.cyan),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        HudPill(device.identifier),
                        HudPill(device.platform.label, color: HudColors.purple),
                        for (final b in boards.take(3))
                          HudPill(b.boardConfig, color: HudColors.textMuted),
                        if (boards.isNotEmpty && boards.first.platform != null)
                          HudPill(
                            CatalogIndex.isAppleSilicon(device)
                                ? 'APPLE SILICON · ${boards.first.platform!.toUpperCase()}'
                                : boards.first.platform!.toUpperCase(),
                            color: HudColors.textMuted,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _Toggle(
                label: 'Signed only',
                value: signedOnly,
                onChanged: (v) => ref.read(signedOnlyProvider.notifier).set(v),
              ),
              const SizedBox(width: 12),
              NeonButton(
                label: 'Select signed (${signed.length})',
                icon: Icons.select_all_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: signed.isEmpty
                    ? null
                    : () => ref
                          .read(selectionProvider.notifier)
                          .addAll(signed.map((g) => g.payloadKey)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const FirmwareColumnHeader(),
          const SizedBox(height: 6),
          Expanded(
            child: !index.hasFirmwares(identifier)
                ? const EmptyState(
                    icon: Icons.downloading_rounded,
                    title: 'Indexing firmware…',
                    message: 'This device is still being fetched from IPSW.me.',
                  )
                : groups.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No IPSW files for this device',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: groups.length,
                    itemBuilder: (_, i) => FirmwareGroupTile(
                      group: groups[i],
                      highlightDevice: identifier,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class FirmwareColumnHeader extends StatelessWidget {
  const FirmwareColumnHeader({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        SizedBox(width: 32),
        SizedBox(width: 150, child: HudLabel('Release')),
        Expanded(child: HudLabel('Shared by')),
        SizedBox(
          width: 98,
          child: Align(
            alignment: Alignment.centerRight,
            child: HudLabel('Size'),
          ),
        ),
        SizedBox(width: 14),
        SizedBox(width: 82, child: HudLabel('Signing')),
        SizedBox(
          width: 84,
          child: Align(
            alignment: Alignment.centerRight,
            child: HudLabel('Released'),
          ),
        ),
        SizedBox(width: 102),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: HudColors.textMuted),
      ),
      const SizedBox(width: 4),
      Transform.scale(
        scale: 0.75,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: HudColors.cyan,
          activeTrackColor: HudColors.cyan.withValues(alpha: 0.3),
        ),
      ),
    ],
  );
}
