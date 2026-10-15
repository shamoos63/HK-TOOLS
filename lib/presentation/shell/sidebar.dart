import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/branding.dart';
import '../../core/theme/hud_theme.dart';
import '../../domain/entities/download_task.dart';
import '../providers/catalog_providers.dart';
import '../providers/device_providers.dart';
import '../providers/download_providers.dart';
import '../providers/ipa_library_providers.dart';
import '../providers/ui_providers.dart';
import '../widgets/hud_widgets.dart';
import 'window_chrome.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final index = ref.watch(catalogIndexProvider);
    final tasks = ref.watch(downloadTasksProvider).value ?? const [];
    final running = tasks
        .where((t) => t.status.isActive || t.status == DownloadStatus.queued)
        .length;
    final devices = ref.watch(devicesProvider.select((s) => s.devices.length));
    final libraryUpdates = ref.watch(libraryUpdateCountProvider);
    String? badge(AppSection s) => switch (s) {
      AppSection.library =>
        index.signedPayloadCount > 0 ? '${index.signedPayloadCount}' : null,
      AppSection.queue => running > 0 ? '$running' : null,
      AppSection.devices => devices > 0 ? '$devices' : null,
      AppSection.ipaLibrary => libraryUpdates > 0 ? '↑$libraryUpdates' : null,
      _ => null,
    };

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(right: BorderSide(color: HudColors.glassBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Windows: the logo area also moves the window.
          const WindowDragArea(child: _Logo()),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 8),
            child: HudLabel('Navigation'),
          ),
          for (final s in AppSection.values)
            _NavItem(
              section: s,
              selected: s == section,
              badge: badge(s),
              onTap: () => ref.read(sectionProvider.notifier).set(s),
            ),
          const Spacer(),
          const _CatalogStatus(),
          const _Credit(),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: HudColors.cyan.withValues(alpha: 0.30),
                blurRadius: 18,
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              Branding.logoMark,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'HK ',
                      style: TextStyle(color: HudColors.cyan),
                    ),
                    TextSpan(
                      text: 'Tools',
                      style: TextStyle(
                        color: HudColors.textPrimary.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'v${Branding.version} // FIRMWARE OPS',
                style: HudTheme.telemetry(size: 10, color: HudColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Author credit pinned to the bottom of the sidebar.
class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, size: 12, color: HudColors.purple),
              SizedBox(width: 6),
              Text(
                'Made by ${Branding.author}',
                style: TextStyle(fontSize: 11.5, color: HudColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _TinyLink(
                icon: Icons.send_rounded,
                label: 'Telegram',
                url: Branding.telegramUrl,
              ),
              const SizedBox(width: 14),
              _TinyLink(
                icon: Icons.language_rounded,
                label: 'Website',
                url: Branding.websiteUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyLink extends StatelessWidget {
  const _TinyLink({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: url.toString(),
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => Branding.open(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: HudColors.cyan),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: HudColors.cyan),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected
        ? HudColors.cyan
        : (_hover ? HudColors.textPrimary : HudColors.textMuted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? HudColors.cyan.withValues(alpha: 0.09)
                : _hover
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? HudColors.cyan.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: HudColors.cyan.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: selected ? HudColors.cyan : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: selected
                      ? [const BoxShadow(color: HudColors.cyan, blurRadius: 8)]
                      : null,
                ),
              ),
              Icon(widget.section.icon, size: 19, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.section.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (widget.badge != null)
                Text(
                  widget.badge!,
                  style: HudTheme.telemetry(size: 11, color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogStatus extends ConsumerWidget {
  const _CatalogStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final state = catalog.value;
    final syncing = state?.syncing ?? false;
    final lastSync = state?.lastSync;
    final subtitle = catalog.hasError && state == null
        ? 'Offline: catalog unavailable'
        : syncing
        ? 'Indexing ${state!.syncDone}/${state.syncTotal} devices'
        : lastSync == null
        ? 'Waiting for first sync'
        : 'Synced ${_ago(lastSync)}';

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseDot(
                color: catalog.hasError && state == null
                    ? HudColors.danger
                    : syncing
                    ? HudColors.warning
                    : HudColors.success,
                size: 6,
                active: syncing,
              ),
              const SizedBox(width: 4),
              const Expanded(child: HudLabel('IPSW.me catalog')),
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Force resync',
                  iconSize: 15,
                  color: HudColors.textMuted,
                  onPressed: syncing
                      ? null
                      : () => catalog.hasError && state == null
                            ? ref.invalidate(catalogProvider)
                            : ref
                                  .read(catalogProvider.notifier)
                                  .sync(force: true),
                  icon: const Icon(Icons.sync_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state == null
                ? '—'
                : '${state.index.devices.length} devices · ${state.index.payloadCount} payloads',
            style: HudTheme.telemetry(size: 11, color: HudColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: HudColors.textMuted),
          ),
          if (syncing) ...[
            const SizedBox(height: 8),
            GlowProgressBar(value: state!.syncFraction, height: 3),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
