import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/device/device_toolchain.dart';
import '../../../services/device/setup_assistant.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import 'devices_screen.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = device.mode.isBooted && device.pairState == PairState.paired;
    return ListView(
      children: [
        _Header(device: device),
        const SizedBox(height: 14),
        if (device.mode.isBooted && !paired) ...[
          TrustHint(device: device),
          const SizedBox(height: 14),
        ],
        if (device.mode.isLowLevel) ...[
          _LowLevelCard(device: device),
          const SizedBox(height: 14),
        ],
        if (paired)
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 900;
              final left = [
                _IdentityCard(device: device),
                const SizedBox(height: 14),
                _ActivationCard(device: device),
                const SizedBox(height: 14),
                _ActionsCard(device: device),
              ];
              final right = [
                _BatteryCard(device: device),
                const SizedBox(height: 14),
                _StorageCard(device: device),
              ];
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: left)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(children: right)),
                      ],
                    )
                  : Column(
                      children: [...right, const SizedBox(height: 14), ...left],
                    );
            },
          ),
        if (device.mode.isBooted && !paired) _ActionsCard(device: device),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(catalogIndexProvider);
    final info = device.info;
    final model = device.productType == null
        ? null
        : index.displayName(device.productType!);
    final color = modeColor(device.mode);
    return GlassPanel(
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(deviceIcon(device.productType), size: 34, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (device.mode.isBooted &&
                        device.pairState == PairState.paired)
                      HudIconButton(
                        icon: Icons.edit_rounded,
                        tooltip: 'Rename device',
                        onPressed: () => _rename(context, ref),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    ?model,
                    ?device.productType,
                    if (info?.productVersion != null)
                      'iOS ${info!.productVersion} (${info.buildVersion ?? '?'})',
                  ].join('  ·  '),
                  style: HudTheme.telemetry(
                    size: 12.5,
                    color: HudColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    HudPill('${device.mode.label} mode', color: color),
                    if (info?.partNumber != null)
                      HudPill(info!.partNumber!, color: HudColors.purple),
                    if (info?.activationState != null)
                      HudPill(
                        info!.activationState!,
                        color: info.activationState == 'Activated'
                            ? HudColors.success
                            : HudColors.warning,
                      ),
                    if (info?.passwordProtected == true)
                      const HudPill(
                        'Passcode',
                        color: HudColors.textMuted,
                        icon: Icons.lock_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptText(
      context,
      title: 'Rename device',
      initial: device.displayName,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final ok = await runDeviceAction(
      context,
      'Renamed to ${name.trim()}',
      () => ref.read(deviceServiceProvider).rename(device, name.trim()),
    );
    if (ok) await ref.read(devicesProvider.notifier).refresh(device.id);
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context) {
    final i = device.info!;
    return DeviceCard(
      title: 'Identity',
      icon: Icons.fingerprint_rounded,
      child: InfoTable([
        ('Identifier', i.productType),
        ('Hardware model', i.hardwareModel),
        ('Serial number', i.serialNumber),
        ('UDID', device.udid),
        ('ECID', device.ecidHex),
        ('IMEI', i.imei),
        ('Phone number', i.phoneNumber),
        ('Wi-Fi address', i.wifiAddress),
        ('Bluetooth', i.bluetoothAddress),
        ('Baseband', i.basebandVersion),
        ('CPU architecture', i.cpuArchitecture),
        ('Region', i.regionInfo),
      ]),
    );
  }
}

class _BatteryCard extends ConsumerWidget {
  const _BatteryCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deviceBatteryProvider(device.id));
    return DeviceCard(
      title: 'Battery',
      icon: Icons.battery_charging_full_rounded,
      trailing: HudIconButton(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onPressed: () => ref.invalidate(deviceBatteryProvider(device.id)),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => DeviceError(e),
        data: (b) {
          final health = b.healthPercent;
          final healthColor = health == null
              ? HudColors.textMuted
              : health >= 85
              ? HudColors.success
              : health >= 75
              ? HudColors.warning
              : HudColors.danger;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Gauge(
                    label: 'Charge',
                    value: b.level == null ? null : b.level! / 100,
                    text: b.level == null ? '—' : '${b.level}%',
                    color: HudColors.cyan,
                  ),
                  const SizedBox(width: 18),
                  _Gauge(
                    label: 'Health',
                    value: health == null ? null : (health / 100).clamp(0, 1),
                    text: health == null
                        ? '—'
                        : '${health.toStringAsFixed(0)}%',
                    color: healthColor,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (b.isCharging == true)
                          const HudPill(
                            'Charging',
                            color: HudColors.success,
                            icon: Icons.bolt_rounded,
                          ),
                        if (b.fullyCharged == true)
                          const HudPill('Full', color: HudColors.success),
                        if (b.externalConnected == true)
                          const HudPill(
                            'Power connected',
                            color: HudColors.cyan,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InfoTable([
                ('Cycle count', b.cycleCount?.toString()),
                (
                  'Design capacity',
                  b.designCapacity == null ? null : '${b.designCapacity} mAh',
                ),
                (
                  'Full charge capacity',
                  b.maxCapacity == null ? null : '${b.maxCapacity} mAh',
                ),
                (
                  'Current charge',
                  b.currentCapacity == null ? null : '${b.currentCapacity} mAh',
                ),
                (
                  'Temperature',
                  b.temperatureC == null
                      ? null
                      : '${b.temperatureC!.toStringAsFixed(1)} °C',
                ),
                (
                  'Voltage',
                  b.voltage == null
                      ? null
                      : '${b.voltage!.toStringAsFixed(3)} V',
                ),
                ('Current', b.amperage == null ? null : '${b.amperage} mA'),
                ('Battery serial', b.serial),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
  });

  final String label;
  final double? value;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        width: 74,
        height: 74,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: value ?? 0,
              strokeWidth: 5,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
            ),
            Center(
              child: Text(
                text,
                style: HudTheme.telemetry(size: 15, color: color),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      HudLabel(label),
    ],
  );
}

class _StorageCard extends ConsumerWidget {
  const _StorageCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deviceStorageProvider(device.id));
    return DeviceCard(
      title: 'Storage',
      icon: Icons.sd_storage_rounded,
      child: async.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => DeviceError(e),
        data: (s) => s == null
            ? const Text(
                'Not reported',
                style: TextStyle(color: HudColors.textMuted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${formatBytes(s.used, decimals: 1)} used',
                        style: HudTheme.telemetry(color: HudColors.textPrimary),
                      ),
                      const Spacer(),
                      Text(
                        '${formatBytes(s.availableData, decimals: 1)} free of ${formatBytes(s.totalDisk, decimals: 0)}',
                        style: HudTheme.telemetry(
                          size: 12,
                          color: HudColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GlowProgressBar(value: s.usedFraction, height: 6),
                ],
              ),
      ),
    );
  }
}

class _ActionsCard extends ConsumerWidget {
  const _ActionsCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(deviceServiceProvider);
    final paired = device.pairState == PairState.paired;
    return DeviceCard(
      title: 'Actions',
      icon: Icons.power_settings_new_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!paired)
            NeonButton(
              label: 'Pair',
              icon: Icons.link_rounded,
              compact: true,
              onPressed: () async {
                await runDeviceAction(
                  context,
                  'Paired with this computer',
                  () => svc.pair(device),
                );
                await ref.read(devicesProvider.notifier).refresh(device.id);
              },
            ),
          if (paired) ...[
            NeonButton(
              label: 'Restart',
              icon: Icons.restart_alt_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => runDeviceAction(
                context,
                'Restarting ${device.displayName}',
                () => svc.restart(device),
              ),
            ),
            NeonButton(
              label: 'Shut down',
              icon: Icons.power_settings_new_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () async {
                if (await confirmDialog(
                      context,
                      title: 'Shut down ${device.displayName}?',
                      message: 'The device powers off and disconnects.',
                      confirmLabel: 'Shut down',
                    ) &&
                    context.mounted) {
                  await runDeviceAction(
                    context,
                    'Shutting down',
                    () => svc.shutdown(device),
                  );
                }
              },
            ),
            NeonButton(
              label: 'Sleep',
              icon: Icons.bedtime_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () => runDeviceAction(
                context,
                'Device is going to sleep',
                () => svc.sleep(device),
              ),
            ),
            NeonButton(
              label: 'Enter Recovery',
              icon: Icons.healing_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () async {
                if (await confirmDialog(
                      context,
                      title: 'Enter Recovery mode?',
                      message:
                          'The device reboots into Recovery mode. Nothing is erased; '
                          'use "Exit Recovery" to boot back into iOS.',
                      confirmLabel: 'Enter Recovery',
                    ) &&
                    context.mounted) {
                  await runDeviceAction(
                    context,
                    'Rebooting into Recovery mode',
                    () => svc.enterRecovery(device),
                  );
                }
              },
            ),
            NeonButton(
              label: 'Factory reset',
              icon: Icons.delete_forever_rounded,
              variant: NeonVariant.danger,
              compact: true,
              onPressed: () => _factoryReset(context, ref),
            ),
            NeonButton(
              label: 'Unpair',
              icon: Icons.link_off_rounded,
              variant: NeonVariant.danger,
              compact: true,
              onPressed: () async {
                if (await confirmDialog(
                      context,
                      title: 'Unpair this computer?',
                      message: 'The device forgets this computer. It will ask to "Trust" again next time.',
                      confirmLabel: 'Unpair',
                      danger: true,
                    ) &&
                    context.mounted) {
                  await runDeviceAction(
                    context,
                    'Unpaired',
                    () => svc.unpair(device),
                  );
                  await ref.read(devicesProvider.notifier).refresh(device.id);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _factoryReset(BuildContext context, WidgetRef ref) async {
    if (!ref.read(deviceToolchainProvider).has(DeviceTool.pymobiledevice3)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Factory reset needs pymobiledevice3: pip install pymobiledevice3',
          ),
        ),
      );
      return;
    }
    final keepPlan = await showDialog<bool>(
      context: context,
      builder: (_) => _FactoryResetDialog(device: device),
    );
    if (keepPlan == null || !context.mounted) return;
    await runDeviceAction(
      context,
      '${device.displayName} is erasing and will restart into Setup Assistant',
      () => ref
          .read(deviceServiceProvider)
          .factoryReset(device, preserveDataPlan: keepPlan),
    );
  }
}

class _LowLevelCard extends ConsumerWidget {
  const _LowLevelCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = device.recoveryInfo;
    return DeviceCard(
      title: '${device.mode.label} mode',
      icon: Icons.memory_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            device.mode == DeviceMode.dfu
                ? 'The device is in DFU mode. Restore a signed IPSW to bring it back.'
                : 'The device is in Recovery mode. Restore a signed IPSW, or exit '
                      'Recovery to boot the existing iOS installation.',
            style: const TextStyle(color: HudColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          InfoTable([
            for (final k in const [
              'PRODUCT', 'MODEL', 'NAME', 'ECID', 'CPID', 'CPRV', 'BDID', //
              'CPFM', 'SCEP', 'IBFL', 'SRTG', 'SRNM', 'IMEI', 'MODE',
            ])
              (k, q[k]),
          ], labelWidth: 90),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              NeonButton(
                label: 'Flash firmware',
                icon: Icons.system_update_alt_rounded,
                compact: true,
                onPressed: () =>
                    ref.read(deviceTabProvider.notifier).set(DeviceTab.restore),
              ),
              if (device.mode == DeviceMode.recovery)
                NeonButton(
                  label: 'Exit Recovery',
                  icon: Icons.exit_to_app_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: () => runDeviceAction(
                    context,
                    'Rebooting into iOS',
                    () => ref.read(deviceServiceProvider).exitRecovery(device),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivationCard extends ConsumerStatefulWidget {
  const _ActivationCard({required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<_ActivationCard> createState() => _ActivationCardState();
}

class _ActivationCardState extends ConsumerState<_ActivationCard> {
  String? _busy;

  ConnectedDevice get d => widget.device;

  @override
  Widget build(BuildContext context) {
    final hasTool = ref
        .watch(deviceToolchainProvider)
        .has(DeviceTool.pymobiledevice3);
    final state = d.info?.activationState ?? 'Unknown';
    final activated = state == 'Activated' || state == 'FactoryActivated';
    final setupDone = ref.watch(deviceSetupDoneProvider(d.id)).value;
    return DeviceCard(
      title: 'Activation & Setup',
      icon: Icons.verified_user_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              HudPill(
                state,
                color: activated ? HudColors.success : HudColors.warning,
                icon: activated
                    ? Icons.check_rounded
                    : Icons.lock_clock_rounded,
              ),
              HudPill(
                switch (setupDone) {
                  true => 'Setup complete',
                  false => 'In Setup Assistant',
                  null => 'Setup state unknown',
                },
                color: setupDone == false
                    ? HudColors.warning
                    : HudColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            !activated
                ? 'Activate contacts Apple\'s activation server, like Finder or iTunes. '
                      'If Activation Lock is on, the owner\'s Apple ID is required on the device.'
                : setupDone == false
                ? 'Skip Setup jumps past the Setup Assistant screens you choose, '
                      'the same way Apple Configurator prepares devices.'
                : 'This device is activated and set up.',
            style: const TextStyle(color: HudColors.textMuted, fontSize: 12.5),
          ),
          if (!hasTool) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Requires pymobiledevice3:  pip install pymobiledevice3',
              style: HudTheme.telemetry(size: 12, color: HudColors.warning),
            ),
          ],
          if (_busy != null) ...[
            const SizedBox(height: 10),
            Text(_busy!, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NeonButton(
                label: 'Activate',
                icon: Icons.verified_rounded,
                compact: true,
                onPressed: hasTool && !activated && _busy == null
                    ? _activate
                    : null,
              ),
              NeonButton(
                label: 'Skip Setup',
                icon: Icons.fast_forward_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed:
                    hasTool && activated && setupDone != true && _busy == null
                    ? _skipSetup
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _activate() async {
    setState(() => _busy = 'Activating with Apple…');
    final ok = await runDeviceAction(
      context,
      '${d.displayName} is activated',
      () => ref.read(deviceServiceProvider).activate(d),
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) {
      await ref.read(devicesProvider.notifier).refresh(d.id);
      ref.invalidate(deviceSetupDoneProvider(d.id));
    }
  }

  Future<void> _skipSetup() async {
    final choice = await showDialog<(Set<SetupPaneGroup>, bool)>(
      context: context,
      builder: (_) => const _SkipSetupDialog(),
    );
    if (choice == null || !mounted) return;
    final (keep, restart) = choice;
    setState(() => _busy = 'Applying setup configuration…');
    final svc = ref.read(deviceServiceProvider);
    final ok = await runDeviceAction(
      context,
      restart
          ? 'Configuration applied; restarting ${d.displayName}'
          : 'Configuration applied. Restart the device to apply it.',
      () async {
        await svc.skipSetup(d, skipPanes(keep: keep));
        if (restart) await svc.restart(d);
      },
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) ref.invalidate(deviceSetupDoneProvider(d.id));
  }
}

class _SkipSetupDialog extends StatefulWidget {
  const _SkipSetupDialog();

  @override
  State<_SkipSetupDialog> createState() => _SkipSetupDialogState();
}

class _SkipSetupDialogState extends State<_SkipSetupDialog> {
  final Set<SetupPaneGroup> _keep = {
    SetupPaneGroup.languageRegion,
    SetupPaneGroup.wifi,
  };
  bool _restart = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: HudColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: HudColors.glassBorder),
    ),
    title: const Text('Skip Setup Assistant', style: TextStyle(fontSize: 17)),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome, terms, Siri, Screen Time, analytics, appearance and the other '
            'promotional screens are always skipped. Tick the screens you still want to see:',
            style: TextStyle(
              color: HudColors.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final g in SetupPaneGroup.values)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _keep.contains(g),
              title: Text(
                'Show ${g.label}',
                style: const TextStyle(fontSize: 13),
              ),
              onChanged: (v) =>
                  setState(() => v == true ? _keep.add(g) : _keep.remove(g)),
            ),
          const Divider(),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _restart,
            title: const Text(
              'Restart the device to apply',
              style: TextStyle(fontSize: 13),
            ),
            onChanged: (v) => setState(() => _restart = v ?? true),
          ),
          const SizedBox(height: 6),
          const Text(
            'Works while the device is on the Setup Assistant after an erase or restore. '
            'A device that already has a configuration must be erased first.',
            style: TextStyle(
              color: HudColors.textMuted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
    actions: [
      NeonButton(
        label: 'Cancel',
        variant: NeonVariant.ghost,
        compact: true,
        onPressed: () => Navigator.pop(context),
      ),
      NeonButton(
        label: 'Skip Setup',
        compact: true,
        onPressed: () => Navigator.pop(context, (_keep, _restart)),
      ),
    ],
  );
}

/// Confirms "Erase All Content and Settings". Pops with whether to keep the
/// eSIM / data plan, or `null` when cancelled.
class _FactoryResetDialog extends StatefulWidget {
  const _FactoryResetDialog({required this.device});

  final ConnectedDevice device;

  @override
  State<_FactoryResetDialog> createState() => _FactoryResetDialogState();
}

class _FactoryResetDialogState extends State<_FactoryResetDialog> {
  final _confirm = TextEditingController();
  bool _keepPlan = true;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = _confirm.text.trim() == 'ERASE';
    return AlertDialog(
      backgroundColor: HudColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: HudColors.danger.withValues(alpha: 0.5)),
      ),
      title: Text(
        'Factory reset ${widget.device.displayName}?',
        style: const TextStyle(fontSize: 17),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Erases all content and settings: apps, photos, messages, accounts and '
              'passcode. The device restarts into Setup Assistant on its current iOS '
              'version.\n\n'
              'Back it up first (Backup tab). If Find My is on, Activation Lock stays '
              'on after the erase and the owner\'s Apple ID will be needed to activate it.',
              style: TextStyle(
                color: HudColors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _keepPlan,
              title: const Text(
                'Keep eSIM / cellular plan',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (v) => setState(() => _keepPlan = v ?? true),
            ),
            const SizedBox(height: 8),
            const Text(
              'Type ERASE to confirm',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _confirm,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: HudTheme.telemetry(color: HudColors.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        NeonButton(
          label: 'Cancel',
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: () => Navigator.pop(context),
        ),
        NeonButton(
          label: 'Erase device',
          variant: NeonVariant.danger,
          compact: true,
          onPressed: armed ? () => Navigator.pop(context, _keepPlan) : null,
        ),
      ],
    );
  }
}
