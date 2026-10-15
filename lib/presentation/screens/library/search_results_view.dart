import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../services/catalog/catalog_index.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'firmware_group_tile.dart';
import 'library_screen.dart';

/// Search results with a version filter, so e.g. "all signed iOS 27.0.1"
/// can be selected without also picking up the 15.8.x builds still signed
/// for older hardware.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A new query starts with every version visible.
    ref.listen(
      searchTextProvider,
      (_, _) => ref.read(versionFacetProvider.notifier).set(const {}),
    );

    final result = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final facets = VersionFacet.of(result.groups);
    final selectedFacets = ref
        .watch(versionFacetProvider)
        .where((k) => facets.any((f) => f.key == k))
        .toSet();
    final groups = selectedFacets.isEmpty
        ? result.groups
        : [
            for (final g in result.groups)
              if (selectedFacets.contains(VersionFacet.keyOf(g))) g,
          ];
    final signed = [
      for (final g in groups)
        if (g.release.signed) g,
    ];
    final signedBytes = signed.fold<int>(0, (s, g) => s + g.release.fileSize);
    final signedTargets = signed.fold<int>(
      0,
      (s, g) => s + g.deviceIdentifiers.length,
    );
    final pendingModel = query.modelNumbers.any(
      (m) => ref.watch(modelLookupProvider(m)).isLoading,
    );

    final headline = selectedFacets.length == 1
        ? facets.firstWhere((f) => f.key == selectedFacets.first).label
        : query.targetsVersion
        ? '${query.platforms.map((p) => p.label).join('/')} ${query.version ?? ''}'
              '${query.build != null ? ' (${query.build!.toUpperCase()})' : ''}'
        : 'Search results';

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline.trim(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${groups.length} payloads'
                      '${selectedFacets.isEmpty ? '' : ' (of ${result.groups.length})'} · '
                      '${signed.length} signed covering $signedTargets device targets (${formatBytes(signedBytes)})',
                      style: HudTheme.telemetry(
                        size: 12,
                        color: HudColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              NeonButton(
                label: 'Select all (${groups.length})',
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: groups.isEmpty
                    ? null
                    : () => ref
                          .read(selectionProvider.notifier)
                          .addAll(groups.map((g) => g.payloadKey)),
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: 'Select signed (${signed.length})',
                icon: Icons.verified_rounded,
                compact: true,
                onPressed: signed.isEmpty
                    ? null
                    : () => ref
                          .read(selectionProvider.notifier)
                          .addAll(signed.map((g) => g.payloadKey)),
              ),
            ],
          ),
          if (facets.length > 1) ...[
            const SizedBox(height: 14),
            _VersionFacetBar(facets: facets, selected: selectedFacets),
          ],
          const SizedBox(height: 14),
          const FirmwareColumnHeader(),
          const SizedBox(height: 6),
          Expanded(
            child: groups.isEmpty
                ? EmptyState(
                    icon: pendingModel
                        ? Icons.travel_explore_rounded
                        : Icons.search_off_rounded,
                    title: pendingModel
                        ? 'Resolving model number…'
                        : 'No matching firmware',
                    message:
                        'Try "iPhone 15 Pro", "Mac14,2", "A2442", "iOS 18.0.1", "22A3354" '
                        'or tags like is:signed platform:macos chip:m-series.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: groups.length,
                    itemBuilder: (_, i) => FirmwareGroupTile(group: groups[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionFacetBar extends ConsumerWidget {
  const _VersionFacetBar({required this.facets, required this.selected});

  final List<VersionFacet> facets;
  final Set<String> selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(versionFacetProvider.notifier);
    final latest = VersionFacet.latestKeys(facets);
    final latestActive =
        selected.isNotEmpty &&
        selected.length == latest.length &&
        selected.containsAll(latest);

    void toggle(String key) {
      final next = {...selected};
      next.contains(key) ? next.remove(key) : next.add(key);
      notifier.set(next);
    }

    return Row(
      children: [
        const HudLabel('Version'),
        const SizedBox(width: 12),
        _FacetChip(
          label: 'All',
          detail: '${facets.fold<int>(0, (s, f) => s + f.payloads)}',
          active: selected.isEmpty,
          onTap: () => notifier.set(const {}),
        ),
        const SizedBox(width: 6),
        _FacetChip(
          label: 'Latest',
          detail: latest.length == 1
              ? facets.first.version
              : '${latest.length} OS',
          icon: Icons.bolt_rounded,
          active: latestActive,
          onTap: () => notifier.set(latestActive ? const {} : latest),
        ),
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: HudColors.glassBorder,
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: facets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final f = facets[i];
                return Tooltip(
                  message:
                      '${f.payloads} payloads · ${f.deviceTargets} device targets · ${formatBytes(f.bytes)}',
                  child: _FacetChip(
                    label: f.label,
                    detail: '${f.payloads}',
                    active: selected.contains(f.key),
                    onTap: () => toggle(f.key),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FacetChip extends StatelessWidget {
  const _FacetChip({
    required this.label,
    required this.detail,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String detail;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? HudColors.cyan : HudColors.textMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? HudColors.cyan.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: active
                  ? HudColors.cyan.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: HudColors.cyan.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? HudColors.textPrimary : HudColors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Text(detail, style: HudTheme.telemetry(size: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
