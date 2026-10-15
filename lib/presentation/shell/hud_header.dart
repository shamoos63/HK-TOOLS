import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hud_theme.dart';
import '../../core/utils/byte_format.dart';
import '../providers/catalog_providers.dart';
import '../providers/download_providers.dart';
import '../providers/ui_providers.dart';
import '../widgets/hud_widgets.dart';
import 'window_chrome.dart';

/// Universal search with filter tags + live telemetry badges.
/// Sections where the firmware search bar is hidden.
const hideSearchIn = {AppSection.devices, AppSection.appStore};

class HudHeader extends ConsumerStatefulWidget {
  const HudHeader({super.key, required this.searchFocus});

  final FocusNode searchFocus;

  @override
  ConsumerState<HudHeader> createState() => _HudHeaderState();
}

class _HudHeaderState extends ConsumerState<HudHeader> {
  late final _controller = TextEditingController(
    text: ref.read(searchTextProvider),
  );

  static const _tags = [
    'is:signed',
    'platform:ios',
    'platform:ipados',
    'platform:macos',
    'chip:m-series',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setText(String text) {
    ref.read(searchTextProvider.notifier).set(text);
    if (text.isNotEmpty && ref.read(sectionProvider) != AppSection.library) {
      ref.read(sectionProvider.notifier).set(AppSection.library);
    }
  }

  void _toggleTag(String tag) {
    final tokens = _controller.text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    tokens.contains(tag) ? tokens.remove(tag) : tokens.add(tag);
    final text = tokens.join(' ');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _setText(text);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the field in sync if search is cleared elsewhere.
    ref.listen(searchTextProvider, (_, next) {
      if (next != _controller.text) _controller.text = next;
    });
    final text = ref.watch(searchTextProvider);
    final activeTokens = text.split(RegExp(r'\s+')).toSet();
    // The firmware search only applies to catalog sections.
    final section = ref.watch(sectionProvider);
    final showSearch = !hideSearchIn.contains(section);

    return Padding(
      // Leave room for the window buttons in the top-right corner (Windows).
      padding: EdgeInsets.fromLTRB(24, useCustomWindowChrome ? 38 : 18, 24, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!showSearch) const Spacer(),
          if (showSearch)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassPanel(
                    padding: EdgeInsets.zero,
                    radius: 12,
                    glow: widget.searchFocus.hasFocus,
                    child: TextField(
                      controller: _controller,
                      focusNode: widget.searchFocus,
                      onChanged: _setText,
                      style: const TextStyle(fontSize: 14),
                      cursorColor: HudColors.cyan,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: HudColors.cyan,
                          size: 20,
                        ),
                        hintText: 'Search devices, models, versions, builds — "iPhone 15 Pro", "A2442", "iOS 18.0.1", "22A3354"',
                        hintStyle: TextStyle(
                          color: HudColors.textMuted.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                        suffixIcon: text.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    Theme.of(context).platform ==
                                            TargetPlatform.macOS
                                        ? '⌘F'
                                        : 'Ctrl+F',
                                    style: HudTheme.telemetry(
                                      size: 11,
                                      color: HudColors.textMuted,
                                    ),
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: HudColors.textMuted,
                                onPressed: () {
                                  _controller.clear();
                                  _setText('');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final tag in _tags)
                        _TagChip(
                          tag: tag,
                          active: activeTokens.contains(tag),
                          onTap: () => _toggleTag(tag),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (showSearch) const SizedBox(width: 18),
          const _TelemetryBadges(),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.active,
    required this.onTap,
  });

  final String tag;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? HudColors.cyan : HudColors.textMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active
                ? HudColors.cyan.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: color.withValues(alpha: active ? 0.6 : 0.25),
            ),
          ),
          child: Text(tag, style: HudTheme.telemetry(size: 11, color: color)),
        ),
      ),
    );
  }
}

class _TelemetryBadges extends ConsumerWidget {
  const _TelemetryBadges();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(hudTelemetryProvider).value;
    final index = ref.watch(catalogIndexProvider);
    final syncing = ref.watch(
      catalogProvider.select((s) => s.value?.syncing ?? false),
    );
    final speed = telemetry?.bytesPerSecond ?? 0;

    return Row(
      children: [
        _Badge(
          label: 'Throughput',
          value: formatRate(speed),
          icon: Icons.south_rounded,
          color: speed > 0 ? HudColors.cyan : HudColors.textMuted,
        ),
        const SizedBox(width: 10),
        _Badge(
          label: 'Queue',
          value: '${telemetry?.active ?? 0} ▸ ${telemetry?.queued ?? 0}',
          icon: Icons.layers_rounded,
          color: HudColors.purple,
          onTap: () => ref.read(sectionProvider.notifier).set(AppSection.queue),
        ),
        const SizedBox(width: 10),
        _Badge(
          label: 'Apple signing',
          value: syncing ? 'SCANNING' : '${index.signedPayloadCount} LIVE',
          leading: PulseDot(
            color: syncing ? HudColors.warning : HudColors.success,
            size: 7,
          ),
          color: syncing ? HudColors.warning : HudColors.success,
          onTap: () {
            ref.read(searchTextProvider.notifier).set('is:signed');
            ref.read(sectionProvider.notifier).set(AppSection.library);
          },
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.leading,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          radius: 12,
          borderColor: color.withValues(alpha: 0.35),
          child: SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HudLabel(label),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ?leading,
                    if (icon != null) Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: HudTheme.telemetry(
                          size: 14,
                          color: color,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
