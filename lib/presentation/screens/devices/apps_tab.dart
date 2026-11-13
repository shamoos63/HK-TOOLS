import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import 'files_tab.dart';
import '../../../core/l10n/l10n.dart';

class AppsTab extends ConsumerStatefulWidget {
  const AppsTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends ConsumerState<AppsTab> {
  bool _system = false;
  String _filter = '';
  String? _installing;

  (String, bool) get _key => (widget.device.id, _system);
  ProviderSubscription<AsyncValue<List<InstalledApp>>>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Fetches icons whenever the app list (re)loads.
  void _listen() {
    _sub?.close();
    _sub = ref.listenManual(deviceAppsProvider(_key), (_, next) {
      final apps = next.value;
      if (apps == null) return;
      ref
          .read(appIconsProvider.notifier)
          .ensure(apps.map((a) => a.bundleId), device: widget.device);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deviceAppsProvider(_key));
    final icons = ref.watch(appIconsProvider);
    return DeviceCard(
      title: tr('Applications'),
      icon: Icons.apps_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 170,
            height: 34,
            child: TextField(
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('Filter apps'),
                prefixIcon: Icon(Icons.search_rounded, size: 16),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(tr('System'), style: TextStyle(fontSize: 12.5)),
          Switch(
            value: _system,
            onChanged: (v) {
              setState(() => _system = v);
              _listen();
            },
          ),
          HudIconButton(
            icon: Icons.refresh_rounded,
            tooltip: tr('Reload'),
            onPressed: () => ref.invalidate(deviceAppsProvider(_key)),
          ),
          const SizedBox(width: 6),
          NeonButton(
            label: _installing == null ? 'Install IPA' : tr('Installing…'),
            icon: Icons.add_rounded,
            compact: true,
            onPressed: _installing == null ? _install : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_installing != null) ...[
            Text(
              trf('Installing {0}…', [p.basename(_installing!)]),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => DeviceError(
                e,
                onRetry: () => ref.invalidate(deviceAppsProvider(_key)),
              ),
              data: (apps) {
                final shown = apps
                    .where(
                      (a) =>
                          _filter.isEmpty ||
                          a.displayName.toLowerCase().contains(_filter) ||
                          a.bundleId.toLowerCase().contains(_filter),
                    )
                    .toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: Icons.apps_outage_rounded,
                    title: tr('No apps'),
                  );
                }
                return ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: HudColors.overlay.withValues(alpha: 0.05),
                  ),
                  itemBuilder: (_, i) => _AppRow(
                    app: shown[i],
                    iconPath: icons[shown[i].bundleId],
                    onUninstall: () => _uninstall(shown[i]),
                    onDocuments: shown[i].fileSharing
                        ? () => _documents(shown[i])
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _install() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('iOS app'), extensions: ['ipa', 'ipcc']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _installing = file.path);
    await runDeviceAction(
      context,
      trf('Installed {0}', [p.basename(file.path)]),
      () =>
          ref.read(deviceServiceProvider).installApp(widget.device, file.path),
    );
    if (!mounted) return;
    setState(() => _installing = null);
    ref.invalidate(deviceAppsProvider(_key));
  }

  Future<void> _uninstall(InstalledApp app) async {
    final ok = await confirmDialog(
      context,
      title: trf('Uninstall {0}?', [app.displayName]),
      message: tr('The app and its data are removed from the device.'),
      confirmLabel: tr('Uninstall'),
      danger: true,
    );
    if (!ok || !mounted) return;
    await runDeviceAction(
      context,
      trf('Uninstalled {0}', [app.displayName]),
      () => ref
          .read(deviceServiceProvider)
          .uninstallApp(widget.device, app.bundleId),
    );
    ref.invalidate(deviceAppsProvider(_key));
  }

  void _documents(InstalledApp app) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: HudColors.surfaceRaised,
      insetPadding: const EdgeInsets.all(40),
      child: SizedBox(
        width: 900,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilesTab(device: widget.device, documentsOf: app.bundleId),
        ),
      ),
    ),
  );
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.onUninstall,
    this.iconPath,
    this.onDocuments,
  });

  final InstalledApp app;
  final String? iconPath;
  final VoidCallback onUninstall;
  final VoidCallback? onDocuments;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        AppIcon(
          name: app.displayName,
          path: iconPath,
          color: app.isSystem ? HudColors.purple : HudColors.cyan,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              Text(
                app.bundleId,
                style: HudTheme.telemetry(
                  size: 11.5,
                  color: HudColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            app.version ?? '',
            style: HudTheme.telemetry(size: 12, color: HudColors.textPrimary),
          ),
        ),
        SizedBox(
          width: 90,
          child: Text(
            app.totalSize == 0 ? '' : formatBytes(app.totalSize, decimals: 1),
            textAlign: TextAlign.right,
            style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        HudIconButton(
          icon: Icons.folder_open_rounded,
          tooltip: onDocuments == null
              ? tr('App does not share files')
              : tr('Browse app documents'),
          onPressed: onDocuments,
        ),
        HudIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: app.isSystem ? tr('System app') : tr('Uninstall'),
          color: HudColors.danger,
          onPressed: app.isSystem ? null : onUninstall,
        ),
      ],
    ),
  );
}
