import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'apps_tab.dart';
import 'backup_tab.dart';
import 'console_tab.dart';
import 'contacts_tab.dart';
import 'device_home.dart';
import 'device_widgets.dart';
import 'files_tab.dart';
import 'gallery_tab.dart';
import 'overview_tab.dart';
import 'restore_tab.dart';
import 'screen_tab.dart';
import 'tools_tab.dart';
import '../../../core/l10n/l10n.dart';

/// "My Device": what the app opens on. Waits for a device, then shows it
/// (photo, model, iOS, battery, storage) with everything you can do to it
/// below.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(devicesProvider);
    // Running, or finished and not yet dismissed: the result must stay
    // visible even if the device has not come back.
    final restoring = ref.watch(
      restoreProvider.select((s) => s.status != JobStatus.idle),
    );
    final active = ref.watch(activeDeviceProvider);

    if (state.toolsMissing) return const _ToolsMissing();

    final tab = ref.watch(deviceTabProvider);
    final Widget body;
    if (active != null) {
      body = Padding(
        key: const ValueKey('device'),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: LayoutBuilder(
          builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Full card on Overview; a slim strip on the other features
              // (and in short windows) so their lists get the room.
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: DeviceHero(
                  device: active,
                  devices: state.devices,
                  compact: tab != DeviceTab.overview || c.maxHeight < 620,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _DeviceDetail(device: active)),
            ],
          ),
        ),
      );
    } else if (restoring) {
      // The device drops off the bus while it reboots into restore mode.
      body = const Padding(
        key: ValueKey('restoring'),
        padding: EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: RestoreTab(device: null),
      );
    } else {
      body = WaitingForDevice(
        key: const ValueKey('waiting'),
        polling: state.polling,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      child: body,
    );
  }
}

IconData deviceIcon(String? productType) {
  final t = productType ?? '';
  if (t.startsWith('iPad')) return Icons.tablet_mac_rounded;
  if (t.startsWith('iPhone')) return Icons.phone_iphone_rounded;
  if (t.startsWith('iPod')) return Icons.smartphone_rounded;
  if (t.startsWith('AppleTV')) return Icons.tv_rounded;
  if (t.startsWith('Watch')) return Icons.watch_rounded;
  return Icons.devices_other_rounded;
}

Color modeColor(DeviceMode m) => switch (m) {
  DeviceMode.normal => HudColors.success,
  DeviceMode.recovery => HudColors.warning,
  DeviceMode.dfu => HudColors.purple,
  DeviceMode.restore => HudColors.cyan,
  DeviceMode.unknown => HudColors.textMuted,
};

class _DeviceDetail extends ConsumerWidget {
  const _DeviceDetail({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var tab = ref.watch(deviceTabProvider);
    final usable = device.mode.isBooted && device.pairState == PairState.paired;
    bool enabled(DeviceTab t) => t.lowLevel || usable;
    if (!enabled(tab)) tab = DeviceTab.overview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in DeviceTab.values)
                _FeatureTab(
                  tab: t,
                  active: t == tab,
                  enabled: enabled(t),
                  onTap: () => ref.read(deviceTabProvider.notifier).set(t),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('${device.id}/${tab.name}'),
            child: switch (tab) {
              DeviceTab.overview => OverviewTab(device: device),
              DeviceTab.apps => AppsTab(device: device),
              DeviceTab.files => FilesTab(device: device),
              DeviceTab.gallery => GalleryTab(device: device),
              DeviceTab.contacts => ContactsTab(device: device),
              DeviceTab.screen => ScreenTab(device: device),
              DeviceTab.console => ConsoleTab(device: device),
              DeviceTab.backup => BackupTab(device: device),
              DeviceTab.tools => ToolsTab(device: device),
              DeviceTab.restore => RestoreTab(device: device),
            },
          ),
        ),
      ],
    );
  }
}

IconData _tabIcon(DeviceTab t) => switch (t) {
  DeviceTab.overview => Icons.info_outline_rounded,
  DeviceTab.apps => Icons.apps_rounded,
  DeviceTab.files => Icons.folder_rounded,
  DeviceTab.gallery => Icons.photo_library_rounded,
  DeviceTab.contacts => Icons.contacts_rounded,
  DeviceTab.screen => Icons.screenshot_monitor_rounded,
  DeviceTab.console => Icons.subject_rounded,
  DeviceTab.backup => Icons.backup_rounded,
  DeviceTab.tools => Icons.handyman_rounded,
  DeviceTab.restore => Icons.system_update_rounded,
};

/// One feature in the strip under the device: icon above a short label.
class _FeatureTab extends StatefulWidget {
  const _FeatureTab({
    required this.tab,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final DeviceTab tab;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_FeatureTab> createState() => _FeatureTabState();
}

class _FeatureTabState extends State<_FeatureTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = !widget.enabled
        ? HudColors.textMuted.withValues(alpha: 0.35)
        : active
        ? HudColors.cyan
        : _hover
        ? HudColors.textPrimary
        : HudColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: widget.enabled ? '' : tr('Needs a trusted, unlocked device'),
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 92,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: active
                    ? HudColors.cyan.withValues(alpha: 0.14)
                    : _hover && widget.enabled
                    ? HudColors.overlay.withValues(alpha: 0.05)
                    : HudColors.surface,
                border: Border.all(
                  color: active
                      ? HudColors.cyan.withValues(alpha: 0.45)
                      : HudColors.glassBorder,
                ),
              ),
              child: Column(
                children: [
                  Icon(_tabIcon(widget.tab), size: 20, color: color),
                  const SizedBox(height: 5),
                  Text(
                    widget.tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? HudColors.textPrimary : color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolsMissing extends ConsumerWidget {
  const _ToolsMissing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = Platform.isWindows
        ? 'Install Apple Devices (Microsoft Store) or iTunes for the USB driver, '
              'then put the libimobiledevice + idevicerestore Windows binaries '
              '(idevice_id.exe, ideviceinfo.exe, … and their DLLs) in a "tools" '
              'folder next to hk_tools.exe, or pick their folder in Settings.'
        : 'Install them with Homebrew:\n'
              '  brew install libimobiledevice ideviceinstaller libirecovery\n'
              'idevicerestore is not in Homebrew; build it from '
              'github.com/libimobiledevice/idevicerestore, or pick a folder that '
              'contains it in Settings.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: GlassPanel(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cable_rounded,
                  size: 44,
                  color: HudColors.cyan.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 14),
                Text(
                  tr('Device tools not found'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'The Devices section drives iPhones and iPads through the open-source libimobiledevice tools.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HudColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  install,
                  textAlign: TextAlign.center,
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeonButton(
                      label: tr('Open Settings'),
                      icon: Icons.tune_rounded,
                      onPressed: () => ref
                          .read(sectionProvider.notifier)
                          .set(AppSection.settings),
                    ),
                    const SizedBox(width: 10),
                    NeonButton(
                      label: tr('Check again'),
                      icon: Icons.refresh_rounded,
                      variant: NeonVariant.ghost,
                      onPressed: () => ref.invalidate(deviceToolchainProvider),
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

/// Shown on tabs that need a trusted device.
class TrustHint extends StatelessWidget {
  const TrustHint({super.key, required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context) {
    final (title, msg) = switch (device.pairState) {
      PairState.pendingTrust => (
        tr('Tap "Trust" on the device'),
        tr(
          'A "Trust This Computer?" prompt is showing. Accept it and enter the passcode.',
        ),
      ),
      PairState.locked => (
        tr('Unlock the device'),
        tr(
          'The device is locked with a passcode. Unlock it so it can pair with this computer.',
        ),
      ),
      PairState.denied => (
        tr('This computer is not trusted'),
        tr('Unplug and reconnect the device, then tap "Trust".'),
      ),
      _ => (
        tr('Not paired'),
        device.pairError ?? tr('Use "Pair" in the Overview tab.'),
      ),
    };
    return DeviceCard(
      title: title,
      icon: Icons.lock_outline_rounded,
      child: Text(
        msg,
        style: TextStyle(color: HudColors.textMuted, fontSize: 13),
      ),
    );
  }
}
