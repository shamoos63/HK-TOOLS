import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../services/whatsapp/wa_android.dart';
import '../../providers/android_device_providers.dart';
import '../../providers/whatsapp_android_providers.dart';
import '../../providers/whatsapp_providers.dart';
import '../../providers/whatsapp_transfer_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'whatsapp_transfer_card.dart';

/// Guided pull of a WhatsApp backup from a USB-connected Android phone:
/// connect → 64-digit key (read off the phone's screen) → backup → copy →
/// move to the iPhone. Laid out like the iPhone device page: the phone at the
/// top, big numbered steps below.
class WaAndroidSource extends ConsumerWidget {
  const WaAndroidSource({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(waAndroidClientProvider);
    if (!client.hasAdb) return const _InstallAdb();

    final devicesAsync = ref.watch(androidDevicesProvider);
    final flow = ref.watch(waAndroidProvider);
    final ctl = ref.read(waAndroidProvider.notifier);

    final devices = devicesAsync.value ?? const <AndroidDevice>[];
    if (devicesAsync.hasError && devices.isEmpty) {
      return _Banner(
        icon: Icons.error_outline_rounded,
        color: HudColors.danger,
        text: '${devicesAsync.error}',
      );
    }
    if (devices.isEmpty) return const _ConnectAndroid();

    // Keep the selection on a connected phone.
    final selected =
        devices.where((d) => d.serial == flow.serial).firstOrNull ??
        devices.first;
    if (selected.serial != flow.serial) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ctl.selectDevice(selected.serial),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AndroidHero(device: selected, devices: devices, flow: flow),
        const SizedBox(height: 16),
        if (selected.state == AndroidDeviceState.unauthorized)
          const _AllowDebugging()
        else if (selected.state != AndroidDeviceState.ready)
          _Banner(
            icon: Icons.usb_off_rounded,
            color: HudColors.warning,
            text: tr('The phone is offline. Unplug it and plug it back in.'),
          )
        else ...[
          if (flow.status != null || flow.error != null) ...[
            _FlowStatus(flow: flow),
            const SizedBox(height: 12),
          ],
          _Steps(flow: flow),
        ],
      ],
    );
  }
}

// ───────────────────────── not ready yet ─────────────────────────

class _InstallAdb extends StatelessWidget {
  const _InstallAdb();

  @override
  Widget build(BuildContext context) {
    final command = Platform.isWindows
        ? 'winget install Google.PlatformTools'
        : 'brew install --cask android-platform-tools';
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const _PhoneArt(width: 90, height: 150, icon: Icons.build_rounded),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Install the Android tools first'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'HK Tools talks to Android phones with adb, Google\'s free Android platform-tools. Run this once in Terminal, then reopen this tab:',
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: HudColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                _CommandBox(command),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// No phone yet: how to turn on USB debugging, in three illustrated steps.
class _ConnectAndroid extends StatelessWidget {
  const _ConnectAndroid();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(child: _SearchingPhone()),
        const SizedBox(height: 18),
        Text(
          tr('Connect your Android phone'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'USB debugging lets this computer read WhatsApp\'s backup. Turn it on once, then plug the phone in.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: HudColors.textMuted),
        ),
        const SizedBox(height: 22),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GuideCard(
                  number: 1,
                  icon: Icons.developer_mode_rounded,
                  title: tr('Turn on Developer options'),
                  path: [
                    tr('Settings'),
                    tr('About phone'),
                    tr('Software information'),
                  ],
                  text: tr(
                    'Tap "Build number" 7 times. Enter the phone\'s PIN if asked.',
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _GuideCard(
                  number: 2,
                  icon: Icons.bug_report_rounded,
                  title: tr('Turn on USB debugging'),
                  path: [tr('Settings'), tr('Developer options')],
                  text: tr('Switch on "USB debugging".'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _GuideCard(
                  number: 3,
                  icon: Icons.usb_rounded,
                  title: tr('Plug in and allow'),
                  text: tr(
                    'Connect the cable, unlock the phone and tap "Allow" on "Allow USB debugging?". Tick "Always allow from this computer".',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The phone asks "Allow USB debugging?".
class _AllowDebugging extends StatelessWidget {
  const _AllowDebugging();

  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 18,
    tint: HudColors.warning,
    borderColor: HudColors.warning.withValues(alpha: 0.4),
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        // A mock of the phone's prompt, so it's easy to recognise.
        Container(
          width: 230,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HudColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HudColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Allow USB debugging?'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.check_box_rounded,
                    size: 16,
                    color: HudColors.cyan,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('Always allow from this computer'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    tr('Cancel'),
                    style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                  ),
                  const SizedBox(width: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: HudColors.cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: HudColors.cyan, width: 1.5),
                    ),
                    child: Text(
                      tr('Allow'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: HudColors.cyan,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Tap "Allow" on the phone'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Unlock the phone. A prompt like this one is showing: tick "Always allow from this computer" and tap "Allow". If you don\'t see it, unplug the cable and plug it back in.',
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: HudColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────── the phone ─────────────────────────

/// Photo, name, Android version, battery and storage of the selected phone,
/// a switcher when several are connected, and the WhatsApp version to use.
class _AndroidHero extends ConsumerWidget {
  const _AndroidHero({
    required this.device,
    required this.devices,
    required this.flow,
  });

  final AndroidDevice device;
  final List<AndroidDevice> devices;
  final WaAndroidState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = device.state == AndroidDeviceState.ready;
    final details = ready
        ? ref.watch(androidDeviceDetailsProvider(device.serial)).value
        : null;
    final infoAsync = ready
        ? ref.watch(androidDeviceInfoProvider(device.serial))
        : null;
    final info = details?.info ?? infoAsync?.value;
    final ctl = ref.read(waAndroidProvider.notifier);
    final title =
        details?.displayName ??
        (info == null
            ? device.displayName
            : AndroidDeviceDetails(info: info).displayName);
    final subtitle = [
      if (info?.androidVersion != null)
        trf('Android {0}', [info!.androidVersion]),
      if (info?.model != null && !title.contains(info!.model!)) info.model!,
    ].join('  ·  ');

    final (statusColor, statusText) = switch (device.state) {
      AndroidDeviceState.ready => (HudColors.success, tr('Connected over USB')),
      AndroidDeviceState.unauthorized => (
        HudColors.warning,
        tr('Waiting for "Allow USB debugging"'),
      ),
      _ => (HudColors.warning, tr('Offline')),
    };

    return GlassPanel(
      glow: true,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 22, 18),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            height: 190,
            child: _Photo(path: details?.photo),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    PulseDot(color: statusColor, size: 7),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (devices.length > 1)
                      _Switcher(
                        devices: devices,
                        selected: device,
                        enabled: !flow.busy,
                        onSelect: ctl.selectDevice,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: HudColors.textMuted),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (info?.deviceName != null)
                      HudPill(
                        info!.deviceName!,
                        color: HudColors.textMuted,
                        icon: Icons.person_rounded,
                      ),
                    if (info?.securityPatch != null)
                      HudPill(
                        trf('Security patch {0}', [info!.securityPatch]),
                        color: HudColors.textMuted,
                      ),
                    HudPill(
                      device.serial,
                      color: HudColors.textMuted,
                      icon: Icons.tag_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (info?.batteryLevel != null)
                      _Stat(
                        icon: info!.charging == true
                            ? Icons.battery_charging_full_rounded
                            : Icons.battery_std_rounded,
                        value: '${info.batteryLevel}%',
                        caption: [
                          if (info.charging == true) tr('Charging'),
                          if (info.batteryTempC != null)
                            '${info.batteryTempC!.toStringAsFixed(1)} °C',
                        ].join(' · '),
                        fraction: info.batteryLevel! / 100,
                        color: info.batteryLevel! <= 20
                            ? HudColors.danger
                            : HudColors.success,
                      ),
                    if (info?.storageTotal != null)
                      _Stat(
                        icon: Icons.sd_storage_rounded,
                        value: trf('{0} of {1}', [
                          formatBytes(
                            info!.storageTotal! - (info.storageFree ?? 0),
                            decimals: 0,
                          ),
                          formatBytes(info.storageTotal!, decimals: 0),
                        ]),
                        caption: trf('{0} free', [
                          formatBytes(info.storageFree ?? 0, decimals: 1),
                        ]),
                        fraction:
                            1 - (info.storageFree ?? 0) / info.storageTotal!,
                        color: HudColors.cyan,
                      ),
                    _FlavorPicker(flow: flow),
                    if (flow.step != WaAndroidStep.key)
                      NeonButton(
                        label: tr('Start over'),
                        icon: Icons.restart_alt_rounded,
                        variant: NeonVariant.ghost,
                        onPressed: flow.busy ? null : ctl.reset,
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
}

class _Photo extends StatelessWidget {
  const _Photo({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 170,
        height: 170,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              HudColors.success.withValues(alpha: 0.16),
              HudColors.success.withValues(alpha: 0),
            ],
          ),
        ),
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: path == null
            ? const _PhoneArt(
                key: ValueKey('art'),
                width: 82,
                height: 160,
                icon: Icons.android_rounded,
              )
            : Image.file(
                File(path!),
                key: ValueKey(path),
                height: 175,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const _PhoneArt(
                  width: 82,
                  height: 160,
                  icon: Icons.android_rounded,
                ),
              ),
      ),
    ],
  );
}

/// A drawn phone, for when there is no product photo.
class _PhoneArt extends StatelessWidget {
  const _PhoneArt({
    super.key,
    required this.width,
    required this.height,
    required this.icon,
  });

  final double width;
  final double height;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: HudColors.surfaceRaised,
      borderRadius: BorderRadius.circular(width * 0.2),
      border: Border.all(
        color: HudColors.overlay.withValues(alpha: 0.25),
        width: 2.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: HudColors.overlay.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
        ),
        const Spacer(),
        Icon(icon, size: width * 0.38, color: HudColors.success),
        const Spacer(),
      ],
    ),
  );
}

/// A phone outline with soft rings expanding behind it.
class _SearchingPhone extends StatefulWidget {
  const _SearchingPhone();

  @override
  State<_SearchingPhone> createState() => _SearchingPhoneState();
}

class _SearchingPhoneState extends State<_SearchingPhone>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 180,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, child) => CustomPaint(
        painter: _Rings(
          HudEffects.reducedOf(context) ? 0 : _c.value,
          HudColors.success,
        ),
        child: child,
      ),
      child: const Center(
        child: _PhoneArt(width: 68, height: 120, icon: Icons.android_rounded),
      ),
    ),
  );
}

class _Rings extends CustomPainter {
  _Rings(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      maxR * 0.62,
      Paint()..color = color.withValues(alpha: 0.06),
    );
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        maxR * (0.45 + 0.55 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.35 * math.pow(1 - p, 1.5)),
      );
    }
  }

  @override
  bool shouldRepaint(_Rings old) => old.t != t || old.color != color;
}

/// Pick one of several connected phones.
class _Switcher extends StatelessWidget {
  const _Switcher({
    required this.devices,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final List<AndroidDevice> devices;
  final AndroidDevice selected;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: enabled ? '' : tr('Wait for the current step to finish'),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HudColors.overlay.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in devices)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? () => onSelect(d.serial) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: d.serial == selected.serial
                      ? HudColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.android_rounded,
                      size: 14,
                      color: d.state == AndroidDeviceState.ready
                          ? HudColors.success
                          : HudColors.warning,
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        d.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: d.serial == selected.serial
                              ? HudColors.textPrimary
                              : HudColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// WhatsApp or WhatsApp Business.
class _FlavorPicker extends ConsumerWidget {
  const _FlavorPicker({required this.flow});

  final WaAndroidState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(waAndroidProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HudColors.overlay.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in WaFlavor.values)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: flow.busy ? null : () => ctl.setFlavor(f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: flow.flavor == f
                      ? HudColors.success.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      f == WaFlavor.business
                          ? Icons.storefront_rounded
                          : Icons.chat_rounded,
                      size: 15,
                      color: flow.flavor == f
                          ? HudColors.success
                          : HudColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr(f.label),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: flow.flavor == f
                            ? HudColors.textPrimary
                            : HudColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.caption,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String caption;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
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
        if (caption.isNotEmpty)
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: HudColors.textMuted),
          ),
        const SizedBox(height: 8),
        GlowProgressBar(
          value: fraction.clamp(0, 1),
          height: 4,
          colors: [color, color],
        ),
      ],
    ),
  );
}

// ───────────────────────── the steps ─────────────────────────

class _Steps extends ConsumerStatefulWidget {
  const _Steps({required this.flow});

  final WaAndroidState flow;

  @override
  ConsumerState<_Steps> createState() => _StepsState();
}

class _StepsState extends ConsumerState<_Steps> {
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final ctl = ref.read(waAndroidProvider.notifier);
    final app = tr(flow.flavor.label);
    final pulled =
        flow.step == WaAndroidStep.done || flow.step == WaAndroidStep.pulling;
    final archiveReady =
        flow.step == WaAndroidStep.done &&
        ref.watch(waArchiveProvider).value != null;
    final moved = ref.watch(waTransferProvider).phase == WaTransferPhase.done;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BigStep(
          number: 1,
          icon: Icons.key_rounded,
          title: tr('Show the 64-digit backup key on the phone'),
          state: flow.keyHex != null
              ? _State.done
              : flow.step == WaAndroidStep.key
              ? _State.active
              : _State.pending,
          summary: flow.keyHex == null ? null : tr('Key captured'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Lead(
                trf(
                  'On the phone, open {0} and follow this path. Leave the key on the screen with the phone unlocked, then press "Read key".',
                  [app],
                ),
              ),
              const SizedBox(height: 10),
              _PathChips([
                app,
                tr('Settings'),
                tr('Chats'),
                tr('Chat backup'),
                tr('End-to-end encrypted backup'),
                tr('Turn on'),
                tr('Use 64-digit encryption key instead'),
                tr('Generate your 64-digit key'),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  NeonButton(
                    label: trf('Open {0} on phone', [app]),
                    icon: Icons.open_in_new_rounded,
                    variant: NeonVariant.ghost,
                    onPressed: flow.busy ? null : ctl.openWhatsApp,
                  ),
                  NeonButton(
                    label: tr('Read key'),
                    icon: Icons.qr_code_scanner_rounded,
                    onPressed: flow.busy ? null : ctl.readKey,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr('or type the key you already have'),
                style: TextStyle(fontSize: 12, color: HudColors.textMuted),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _manual,
                onSubmitted: _submitManual,
                textDirection: TextDirection.ltr,
                style: HudTheme.telemetry(
                  size: 12.5,
                  color: HudColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0123 4567 89ab …',
                  hintTextDirection: TextDirection.ltr,
                  suffixIcon: IconButton(
                    tooltip: tr('Use this key'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    onPressed: () => _submitManual(_manual.text),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (flow.keyHex != null) ...[
          const SizedBox(height: 8),
          _KeyView(keyHex: flow.keyHex!),
        ],
        const SizedBox(height: 12),
        _BigStep(
          number: 2,
          icon: Icons.backup_rounded,
          title: tr('Create the backup'),
          state: pulled
              ? _State.done
              : flow.step == WaAndroidStep.backup
              ? _State.active
              : _State.pending,
          summary: flow.backup == null
              ? null
              : '${flow.backup!.fileName} · ${formatBytes(flow.backup!.size)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Lead(
                flow.keySetAt != null
                    ? tr(
                        'On the phone tap Continue → Create to finish setting up the encrypted backup, then tap "Back up". Google Drive is not needed. The new backup is picked up automatically.',
                      )
                    : tr(
                        'Make sure the phone has a backup made with this key, then press the button.',
                      ),
              ),
              const SizedBox(height: 10),
              _PathChips([
                app,
                tr('Settings'),
                tr('Chats'),
                tr('Chat backup'),
                tr('Back up'),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (flow.busy && flow.step == WaAndroidStep.backup)
                    NeonButton(
                      label: tr('Stop waiting'),
                      icon: Icons.stop_rounded,
                      variant: NeonVariant.ghost,
                      onPressed: ctl.cancelWait,
                    )
                  else
                    NeonButton(
                      label: flow.keySetAt != null
                          ? tr('Wait for backup and copy it')
                          : tr('Copy backup from phone'),
                      icon: Icons.download_rounded,
                      onPressed: flow.busy || flow.step != WaAndroidStep.backup
                          ? null
                          : ctl.waitAndPull,
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: flow.busy
                        ? null
                        : () => ctl.setIncludeMedia(!flow.includeMedia),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: flow.includeMedia,
                          onChanged: flow.busy
                              ? null
                              : (v) => ctl.setIncludeMedia(v ?? true),
                        ),
                        Text(
                          tr('Include photos, videos and voice notes'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _BigStep(
          number: 3,
          icon: Icons.lock_open_rounded,
          title: tr('Decrypt and read on this computer'),
          state: flow.step == WaAndroidStep.done
              ? _State.done
              : flow.step == WaAndroidStep.pulling
              ? _State.active
              : _State.pending,
          summary: flow.step == WaAndroidStep.done
              ? tr('Copied. The chats are listed below.')
              : null,
          child: flow.mediaProgress != null
              ? GlowProgressBar(value: flow.mediaProgress!, height: 6)
              : _Lead(tr('Copying and decrypting the backup…')),
        ),
        const SizedBox(height: 12),
        _BigStep(
          number: 4,
          icon: Icons.phone_iphone_rounded,
          title: tr('Move the chats to the iPhone'),
          state: moved
              ? _State.done
              : archiveReady
              ? _State.active
              : _State.pending,
          child: const WaTransferCard(),
        ),
      ],
    );
  }

  void _submitManual(String text) {
    final ok = ref.read(waAndroidProvider.notifier).setKeyManually(text);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(tr('The key must be 64 characters (0-9 and a-f).')),
        ),
      );
    }
  }
}

enum _State { pending, active, done }

/// One numbered step. Only the current step is expanded.
class _BigStep extends StatelessWidget {
  const _BigStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.state,
    required this.child,
    this.summary,
  });

  final int number;
  final IconData icon;
  final String title;
  final _State state;
  final Widget child;

  /// One line shown under a finished step.
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final active = state == _State.active;
    final done = state == _State.done;
    final color = done
        ? HudColors.success
        : active
        ? HudColors.cyan
        : HudColors.textMuted;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: state == _State.pending ? 0.55 : 1,
      child: GlassPanel(
        radius: 16,
        borderColor: active ? HudColors.cyan.withValues(alpha: 0.45) : null,
        padding: EdgeInsets.fromLTRB(18, 16, 18, active ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(
                      alpha: done || active ? 0.16 : 0.08,
                    ),
                  ),
                  child: done
                      ? Icon(Icons.check_rounded, size: 20, color: color)
                      : Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!active && summary != null)
                        Text(
                          summary!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: HudColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(icon, size: 22, color: color),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: child,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A menu path on the phone, as a row of chips joined by arrows.
class _PathChips extends StatelessWidget {
  const _PathChips(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0)
            Icon(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: HudColors.textMuted,
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: i == items.length - 1
                  ? HudColors.cyan.withValues(alpha: 0.14)
                  : HudColors.overlay.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: i == items.length - 1
                    ? HudColors.cyan
                    : HudColors.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
    this.path = const [],
  });

  final int number;
  final IconData icon;
  final String title;
  final String text;
  final List<String> path;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HudColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: HudColors.success),
            ),
            const Spacer(),
            Text(
              '$number',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: HudColors.overlay.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        if (path.isNotEmpty) ...[const SizedBox(height: 10), _PathChips(path)],
        const SizedBox(height: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: HudColors.textMuted,
          ),
        ),
      ],
    ),
  );
}

/// What the flow is doing right now, or what went wrong.
class _FlowStatus extends StatelessWidget {
  const _FlowStatus({required this.flow});

  final WaAndroidState flow;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (flow.status != null)
        _Banner(
          icon: null,
          color: HudColors.cyan,
          text: flow.status!,
          progress: flow.mediaProgress,
        ),
      if (flow.status != null && flow.error != null) const SizedBox(height: 8),
      if (flow.error != null)
        _Banner(
          icon: Icons.error_outline_rounded,
          color: HudColors.danger,
          text: flow.error!,
        ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.progress,
  });

  /// `null` = a spinner.
  final IconData? icon;
  final Color color;
  final String text;
  final double? progress;

  @override
  Widget build(BuildContext context) => GlassPanel(
    tint: color,
    borderColor: color.withValues(alpha: 0.35),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon == null)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
            ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 10),
          GlowProgressBar(value: progress!, height: 4, colors: [color, color]),
        ],
      ],
    ),
  );
}

class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: HudColors.textPrimary.withValues(alpha: 0.85),
      fontSize: 13.5,
      height: 1.5,
    ),
  );
}

class _CommandBox extends StatelessWidget {
  const _CommandBox(this.command);

  final String command;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
    decoration: BoxDecoration(
      color: HudColors.overlay.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: HudColors.glassBorder),
    ),
    child: Row(
      children: [
        Expanded(
          child: SelectableText(
            command,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: HudTheme.monoFamily,
              fontFamilyFallback: HudTheme.monoFallback,
              fontSize: 13,
              color: HudColors.textPrimary,
            ),
          ),
        ),
        HudIconButton(
          icon: Icons.copy_rounded,
          tooltip: tr('Copy'),
          onPressed: () => Clipboard.setData(ClipboardData(text: command)),
        ),
      ],
    ),
  );
}

/// The captured key in groups of four, with a copy button: the user needs it
/// again to restore this backup on any phone.
class _KeyView extends StatelessWidget {
  const _KeyView({required this.keyHex});

  final String keyHex;

  @override
  Widget build(BuildContext context) {
    final grouped = [
      for (var i = 0; i < keyHex.length; i += 4) keyHex.substring(i, i + 4),
    ].join(' ');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: HudColors.success.withValues(alpha: 0.06),
        border: Border.all(color: HudColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.key_rounded, size: 18, color: HudColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              grouped,
              textDirection: TextDirection.ltr,
              style: HudTheme.telemetry(size: 13, color: HudColors.textPrimary),
            ),
          ),
          HudIconButton(
            icon: Icons.copy_rounded,
            tooltip: tr(
              'Copy key (keep it safe: WhatsApp needs it to restore)',
            ),
            onPressed: () => Clipboard.setData(ClipboardData(text: keyHex)),
          ),
        ],
      ),
    );
  }
}
