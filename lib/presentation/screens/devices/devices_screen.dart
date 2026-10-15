import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'apps_tab.dart';
import 'backup_tab.dart';
import 'console_tab.dart';
import 'contacts_tab.dart';
import 'device_widgets.dart';
import 'files_tab.dart';
import 'gallery_tab.dart';
import 'overview_tab.dart';
import 'restore_tab.dart';
import 'screen_tab.dart';
import 'tools_tab.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(devicesProvider);
    final restoring = ref.watch(restoreProvider.select((s) => s.running));
    final active = ref.watch(activeDeviceProvider);

    if (state.toolsMissing) return const _ToolsMissing();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 270, child: _DeviceList(state: state)),
          const SizedBox(width: 16),
          Expanded(
            child: active != null
                ? _DeviceDetail(device: active)
                : restoring
                ? const RestoreTab(device: null)
                : const GlassPanel(
                    child: EmptyState(
                      icon: Icons.phone_iphone_rounded,
                      title: 'No device connected',
                      message:
                          'Connect an iPhone or iPad with a USB cable. Devices in '
                          'Recovery or DFU mode appear here too, ready to flash.',
                    ),
                  ),
          ),
        ],
      ),
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

class _DeviceList extends ConsumerWidget {
  const _DeviceList({required this.state});

  final DevicesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDeviceProvider);
    final index = ref.watch(catalogIndexProvider);
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PulseDot(
                color: state.polling ? HudColors.success : HudColors.warning,
                size: 6,
                active: state.polling,
              ),
              const SizedBox(width: 6),
              const Expanded(child: HudLabel('Connected devices')),
              Text(
                '${state.devices.length}',
                style: HudTheme.telemetry(size: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.devices.isEmpty
                ? Center(
                    child: Text(
                      state.polling
                          ? 'Waiting for a device…'
                          : 'Detection paused while flashing',
                      style: const TextStyle(
                        color: HudColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final d in state.devices)
                        _DeviceTile(
                          device: d,
                          model: d.productType == null
                              ? null
                              : index.displayName(d.productType!),
                          selected: d.id == active?.id,
                          onTap: () => ref
                              .read(activeDeviceIdProvider.notifier)
                              .set(d.id),
                        ),
                    ],
                  ),
          ),
          if (!state.polling)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Device detection is paused during a firmware restore.',
                style: TextStyle(color: HudColors.warning, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final ConnectedDevice device;
  final String? model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final color = modeColor(d.mode);
    final subtitle = [
      if (model != null && model != d.displayName) model!,
      if (d.info?.productVersion != null) 'iOS ${d.info!.productVersion}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? HudColors.cyan.withValues(alpha: 0.09)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected
                  ? HudColors.cyan.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(deviceIcon(d.productType), size: 28, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        HudPill(d.mode.label, color: color),
                        HudPill(
                          d.connection == DeviceConnection.usb
                              ? 'USB'
                              : 'Wi-Fi',
                          color: HudColors.textMuted,
                          icon: d.connection == DeviceConnection.usb
                              ? Icons.usb_rounded
                              : Icons.wifi_rounded,
                        ),
                        if (d.mode.isBooted && d.pairState != PairState.paired)
                          HudPill(switch (d.pairState) {
                            PairState.pendingTrust => 'Tap Trust',
                            PairState.locked => 'Unlock',
                            PairState.denied => 'Not trusted',
                            _ => 'Not paired',
                          }, color: HudColors.warning),
                      ],
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
        Wrap(
          children: [
            for (final t in DeviceTab.values)
              HudChipTab(
                label: t.label,
                active: t == tab,
                enabled: enabled(t),
                onTap: () => ref.read(deviceTabProvider.notifier).set(t),
              ),
          ],
        ),
        const SizedBox(height: 6),
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
                const Text(
                  'Device tools not found',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The Devices section drives iPhones and iPads through the '
                  'open-source libimobiledevice tools.',
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
                      label: 'Open Settings',
                      icon: Icons.tune_rounded,
                      onPressed: () => ref
                          .read(sectionProvider.notifier)
                          .set(AppSection.settings),
                    ),
                    const SizedBox(width: 10),
                    NeonButton(
                      label: 'Check again',
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
        'Tap "Trust" on the device',
        'A "Trust This Computer?" prompt is showing. Accept it and enter the passcode.',
      ),
      PairState.locked => (
        'Unlock the device',
        'The device is locked with a passcode. Unlock it so it can pair with this computer.',
      ),
      PairState.denied => (
        'This computer is not trusted',
        'Unplug and reconnect the device, then tap "Trust".',
      ),
      _ => (
        'Not paired',
        device.pairError ?? 'Use "Pair" in the Overview tab.',
      ),
    };
    return DeviceCard(
      title: title,
      icon: Icons.lock_outline_rounded,
      child: Text(
        msg,
        style: const TextStyle(color: HudColors.textMuted, fontSize: 13),
      ),
    );
  }
}
