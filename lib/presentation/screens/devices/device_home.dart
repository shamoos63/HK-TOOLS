import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import 'devices_screen.dart';
import '../../../core/l10n/l10n.dart';

// ───────────────────────── waiting for a device ─────────────────────────

/// What the app opens on when nothing is plugged in: a calm "waiting" state
/// with the three steps to connect, and shortcuts to the offline features.
class WaitingForDevice extends ConsumerWidget {
  const WaitingForDevice({super.key, required this.polling});

  /// `false` while detection is paused (a restore is running).
  final bool polling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(AppSection s) => ref.read(sectionProvider.notifier).set(s);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SearchingAnimation(active: polling),
                  const SizedBox(height: 26),
                  Text(
                    polling
                        ? tr('Waiting for a device')
                        : tr('Device detection is paused'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    polling
                        ? tr(
                            'Connect an iPhone or iPad with a USB cable to get started.',
                          )
                        : tr(
                            'It resumes as soon as the firmware restore finishes.',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: HudColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Step(
                            number: 1,
                            icon: Icons.usb_rounded,
                            title: tr('Plug it in'),
                            text: tr(
                              'Use a USB cable. Devices in Recovery or DFU mode are found too.',
                            ),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: _Step(
                            number: 2,
                            icon: Icons.lock_open_rounded,
                            title: tr('Unlock'),
                            text: tr('Unlock the device with its passcode.'),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: _Step(
                            number: 3,
                            icon: Icons.verified_user_rounded,
                            title: tr('Trust this computer'),
                            text: tr(
                              'Tap "Trust" on the device when asked, then enter the passcode.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('While you wait'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HudColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.system_update_rounded,
                          title: tr('Download firmware'),
                          text: tr('IPSW files for any device'),
                          onTap: () => go(AppSection.library),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.storefront_rounded,
                          title: tr('App Store'),
                          text: tr('Find and save apps as IPA'),
                          onTap: () => go(AppSection.appStore),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.chat_rounded,
                          title: tr('WhatsApp'),
                          text: tr('Chat backups and transfer'),
                          onTap: () => go(AppSection.whatsapp),
                        ),
                      ),
                    ],
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

/// A phone outline with soft rings expanding behind it.
class _SearchingAnimation extends StatefulWidget {
  const _SearchingAnimation({required this.active});

  final bool active;

  @override
  State<_SearchingAnimation> createState() => _SearchingAnimationState();
}

class _SearchingAnimationState extends State<_SearchingAnimation>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_SearchingAnimation old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = HudEffects.reducedOf(context);
    return SizedBox(
      width: 220,
      height: 200,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _RingsPainter(
            t: widget.active && !reduced ? _c.value : 0,
            color: widget.active ? HudColors.cyan : HudColors.warning,
          ),
          child: Center(
            child: Container(
              width: 74,
              height: 124,
              decoration: BoxDecoration(
                color: HudColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: HudColors.overlay.withValues(alpha: 0.22),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 22,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    widget.active ? Icons.cable_rounded : Icons.pause_rounded,
                    size: 26,
                    color: widget.active ? HudColors.cyan : HudColors.warning,
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    // Static halo.
    canvas.drawCircle(
      center,
      maxR * 0.62,
      Paint()..color = color.withValues(alpha: 0.06),
    );
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final r = maxR * (0.45 + 0.55 * p);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.35 * math.pow(1 - p, 1.5)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final int number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: HudColors.cyan.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: HudColors.cyan),
            ),
            const Spacer(),
            Text(
              '$number',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: HudColors.overlay.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: HudColors.textMuted,
          ),
        ),
      ],
    ),
  );
}

class _Shortcut extends StatefulWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  State<_Shortcut> createState() => _ShortcutState();
}

class _ShortcutState extends State<_Shortcut> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderColor: _hover ? HudColors.cyan.withValues(alpha: 0.5) : null,
        child: Row(
          children: [
            Icon(widget.icon, size: 20, color: HudColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: _hover ? HudColors.textPrimary : HudColors.textMuted,
            ),
          ],
        ),
      ),
    ),
  );
}

// ───────────────────────── connected device ─────────────────────────

/// Top of the device page: product photo, name, model and iOS version,
/// battery and storage at a glance, and the most common actions.
class DeviceHero extends ConsumerWidget {
  const DeviceHero({
    super.key,
    required this.device,
    required this.devices,
    this.compact = false,
  });

  final ConnectedDevice device;

  /// Every attached device; a switcher shows when there is more than one.
  final List<ConnectedDevice> devices;

  /// A slim one-row strip, so a feature below gets the room.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(catalogIndexProvider);
    final info = device.info;
    final type = device.productType ?? info?.productType;
    final model = type == null ? null : index.displayName(type);
    final paired = device.mode.isBooted && device.pairState == PairState.paired;
    final title = info?.name ?? device.name ?? model ?? device.displayName;
    final subtitle = [
      if (model != null && model != title) model,
      if (info?.productVersion != null)
        'iOS ${info!.productVersion}'
            '${info.buildVersion != null ? ' (${info.buildVersion})' : ''}',
    ].join('  ·  ');

    if (compact) {
      return GlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
        child: Row(
          children: [
            DevicePhoto(device: device, width: 96, height: 64),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _ConnectionStatus(device: device),
                      if (subtitle.isNotEmpty)
                        Flexible(
                          child: Text(
                            '   $subtitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: HudColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (devices.length > 1) ...[
              const SizedBox(width: 12),
              _DeviceSwitcher(devices: devices, active: device),
            ],
          ],
        ),
      );
    }

    return GlassPanel(
      glow: true,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 16, 22, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DevicePhoto(device: device, width: 230, height: 196),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _ConnectionStatus(device: device),
                    const Spacer(),
                    if (devices.length > 1)
                      _DeviceSwitcher(devices: devices, active: device),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (paired)
                      HudIconButton(
                        icon: Icons.edit_rounded,
                        tooltip: tr('Rename device'),
                        onPressed: () => _rename(context, ref),
                      ),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: HudColors.textMuted),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (info?.activationState != null)
                      HudPill(
                        info!.activationState!,
                        color: info.activationState == 'Activated'
                            ? HudColors.success
                            : HudColors.warning,
                      ),
                    if (info?.passwordProtected == true)
                      HudPill(
                        tr('Passcode set'),
                        color: HudColors.textMuted,
                        icon: Icons.lock_rounded,
                      ),
                    if (info?.partNumber != null)
                      HudPill(info!.partNumber!, color: HudColors.textMuted),
                    if (type != null && type != model)
                      HudPill(type, color: HudColors.textMuted),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (paired) _BatteryStat(device: device),
                    if (paired) _StorageStat(device: device),
                    _Actions(device: device, productType: type),
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
      title: tr('Rename device'),
      initial: device.displayName,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final ok = await runDeviceAction(
      context,
      trf('Renamed to {0}', [name.trim()]),
      () => ref.read(deviceServiceProvider).rename(device, name.trim()),
    );
    if (ok) await ref.read(devicesProvider.notifier).refresh(device.id);
  }
}

/// Product photo of [device] from the device image CDN, with the generic
/// device icon while it loads or when there is none.
class DevicePhoto extends ConsumerWidget {
  const DevicePhoto({
    super.key,
    required this.device,
    this.width = 200,
    this.height = 170,
  });

  final ConnectedDevice device;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = deviceImageKey(device);
    final path = key == null ? null : ref.watch(deviceImageProvider(key)).value;
    final placeholder = Icon(
      deviceIcon(device.productType),
      size: height * 0.5,
      color: HudColors.textMuted.withValues(alpha: 0.5),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft spotlight behind the device.
          Container(
            width: height * 0.95,
            height: height * 0.95,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  HudColors.cyan.withValues(alpha: 0.16),
                  HudColors.cyan.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: path == null
                ? KeyedSubtree(key: const ValueKey('icon'), child: placeholder)
                : Image.file(
                    File(path),
                    key: ValueKey(path),
                    width: width,
                    height: height,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (device) {
      _ when device.mode.isLowLevel => (
        modeColor(device.mode),
        trf('In {0} mode', [device.mode.label]),
      ),
      _ when device.pairState == PairState.paired => (
        HudColors.success,
        device.connection == DeviceConnection.usb
            ? tr('Connected over USB')
            : tr('Connected over Wi-Fi'),
      ),
      _ when device.pairState == PairState.pendingTrust => (
        HudColors.warning,
        tr('Tap "Trust" on the device'),
      ),
      _ when device.pairState == PairState.locked => (
        HudColors.warning,
        tr('Unlock the device to continue'),
      ),
      _ when device.pairState == PairState.denied => (
        HudColors.danger,
        tr('This computer is not trusted'),
      ),
      _ => (HudColors.warning, tr('Connecting…')),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulseDot(color: color, size: 7),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _DeviceSwitcher extends ConsumerWidget {
  const _DeviceSwitcher({required this.devices, required this.active});

  final List<ConnectedDevice> devices;
  final ConnectedDevice active;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: HudColors.overlay.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in devices)
          Tooltip(
            message: d.displayName,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => ref.read(activeDeviceIdProvider.notifier).set(d.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: d.id == active.id
                      ? HudColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      deviceIcon(d.productType),
                      size: 14,
                      color: modeColor(d.mode),
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        d.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: d.id == active.id
                              ? HudColors.textPrimary
                              : HudColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Compact stat tile: icon, value, caption and a thin bar.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.caption,
    this.fraction,
    Color? color,
  }) : _color = color;

  final IconData icon;
  final String value;
  final String caption;
  final double? fraction;
  final Color? _color;
  Color get color => _color ?? HudColors.cyan;

  @override
  Widget build(BuildContext context) => Container(
    width: 210,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
    decoration: BoxDecoration(
      color: HudColors.overlay.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: HudTheme.telemetry(
                    size: 14,
                    color: HudColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: HudColors.textMuted),
        ),
        const SizedBox(height: 8),
        GlowProgressBar(
          value: fraction ?? 0,
          height: 4,
          colors: [color, color],
          dimmed: fraction == null,
        ),
      ],
    ),
  );
}

class _BatteryStat extends ConsumerWidget {
  const _BatteryStat({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(deviceBatteryProvider(device.id)).value;
    final level = b?.level;
    final health = b?.healthPercent;
    final color = level == null
        ? HudColors.textMuted
        : level <= 20
        ? HudColors.danger
        : HudColors.success;
    return _Stat(
      icon: b?.isCharging == true
          ? Icons.battery_charging_full_rounded
          : Icons.battery_std_rounded,
      value: level == null ? tr('Battery') : '$level%',
      caption: [
        if (b?.isCharging == true) tr('Charging'),
        if (health != null) trf('Health {0}%', [health.clamp(0, 100).round()]),
        if (b == null) tr('Reading…'),
      ].join(' · '),
      fraction: level == null ? null : level / 100,
      color: color,
    );
  }
}

class _StorageStat extends ConsumerWidget {
  const _StorageStat({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deviceStorageProvider(device.id));
    final s = async.value;
    return _Stat(
      icon: Icons.sd_storage_rounded,
      value: s == null
          ? tr('Storage')
          : '${formatBytes(s.used, decimals: 0)} of ${formatBytes(s.totalDisk, decimals: 0)}',
      caption: s == null
          ? (async.isLoading ? tr('Reading…') : tr('Not reported'))
          : '${formatBytes(s.availableData, decimals: 1)} free',
      fraction: s?.usedFraction,
      color: HudColors.cyan,
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.device, required this.productType});

  final ConnectedDevice device;
  final String? productType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = device.mode.isBooted && device.pairState == PairState.paired;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (productType != null)
          NeonButton(
            label: tr('Get firmware'),
            icon: Icons.system_update_rounded,
            onPressed: () {
              ref.read(searchTextProvider.notifier).set(productType!);
              ref.read(sectionProvider.notifier).set(AppSection.library);
            },
          ),
        if (paired)
          NeonButton(
            label: tr('Back up'),
            icon: Icons.backup_rounded,
            variant: NeonVariant.ghost,
            onPressed: () =>
                ref.read(deviceTabProvider.notifier).set(DeviceTab.backup),
          ),
        NeonButton(
          label: device.mode.isLowLevel
              ? tr('Restore')
              : tr('Update / restore'),
          icon: Icons.restore_rounded,
          variant: NeonVariant.ghost,
          onPressed: () =>
              ref.read(deviceTabProvider.notifier).set(DeviceTab.restore),
        ),
      ],
    );
  }
}
