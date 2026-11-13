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
import '../../core/l10n/l10n.dart';

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
      width: 232,
      decoration: BoxDecoration(
        color: HudColors.sidebar,
        border: BorderDirectional(
          end: BorderSide(color: HudColors.glassBorder),
        ),
      ),
      padding: EdgeInsets.fromLTRB(12, 14 + macTitleBarInset, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Windows: the logo area also moves the window.
          const WindowDragArea(child: _Logo()),
          const SizedBox(height: 22),
          Expanded(
            child: ListView(
              children: [
                for (final g in SectionGroup.values) ...[
                  if (g.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 0, 6),
                      child: Text(
                        g.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: HudColors.textMuted,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 14),
                  for (final s in AppSection.values.where((s) => s.group == g))
                    _NavItem(
                      section: s,
                      selected: s == section,
                      badge: badge(s),
                      onTap: () => ref.read(sectionProvider.notifier).set(s),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
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
        SizedBox(
          width: 38,
          height: 38,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
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
              Text(
                Branding.appName,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: HudColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                trf('Version {0}', [Branding.version]),
                style: TextStyle(fontSize: 11, color: HudColors.textMuted),
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
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 12, color: HudColors.danger),
              SizedBox(width: 6),
              Text(
                trf('Made by {0}', [Branding.author]),
                style: TextStyle(fontSize: 11.5, color: HudColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _TinyLink(
                icon: Icons.send_rounded,
                label: tr('Telegram'),
                url: Branding.telegramUrl,
              ),
              const SizedBox(width: 14),
              _TinyLink(
                icon: Icons.language_rounded,
                label: tr('Website'),
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
              style: TextStyle(fontSize: 11.5, color: HudColors.cyan),
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
        ? HudColors.textPrimary
        : (_hover ? HudColors.textPrimary : HudColors.textMuted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected
                ? HudColors.cyan.withValues(alpha: 0.16)
                : _hover
                ? HudColors.overlay.withValues(alpha: 0.05)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(widget.section.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.section.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (widget.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: HudColors.overlay.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.badge!,
                    style: HudTheme.telemetry(
                      size: 11,
                      color: HudColors.textMuted,
                    ),
                  ),
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
        ? tr('Offline: catalog unavailable')
        : syncing
        ? trf('Indexing {0}/{1} devices', [state!.syncDone, state.syncTotal])
        : lastSync == null
        ? tr('Waiting for first sync')
        : trf('Synced {0}', [_ago(lastSync)]);

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
              Expanded(child: HudLabel(tr('Firmware catalog'))),
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: tr('Force resync'),
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
                : trf('{0} devices · {1} payloads', [
                    state.index.devices.length,
                    state.index.payloadCount,
                  ]),
            style: HudTheme.telemetry(size: 11, color: HudColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: HudColors.textMuted),
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
    if (d.inMinutes < 1) return tr('just now');
    if (d.inHours < 1) return trf('{0}m ago', [d.inMinutes]);
    if (d.inDays < 1) return trf('{0}h ago', [d.inHours]);
    return trf('{0}d ago', [d.inDays]);
  }
}
