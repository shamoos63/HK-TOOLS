import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Screenshots and a live view built from back-to-back screenshots (works on
/// every iOS version that supports screenshotr, no AirPlay needed).
class ScreenTab extends ConsumerStatefulWidget {
  const ScreenTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends ConsumerState<ScreenTab> {
  Uint8List? _frame;
  bool _live = false;
  bool _busy = false;
  String? _error;
  int _frames = 0;
  final _clock = Stopwatch();
  late final String _tmp = p.join(
    Directory.systemTemp.path,
    'hk_screen_${widget.device.udid ?? widget.device.id}.png',
  );

  @override
  void dispose() {
    _live = false;
    super.dispose();
  }

  Future<bool> _grab() async {
    try {
      await ref.read(deviceServiceProvider).screenshot(widget.device, _tmp);
      final bytes = await File(_tmp).readAsBytes();
      if (!mounted) return false;
      setState(() {
        _frame = bytes;
        _error = null;
        _frames++;
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return false;
    }
  }

  Future<void> _single() async {
    setState(() => _busy = true);
    await _grab();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleLive() async {
    if (_live) {
      setState(() => _live = false);
      return;
    }
    setState(() {
      _live = true;
      _frames = 0;
    });
    _clock
      ..reset()
      ..start();
    while (_live && mounted) {
      if (!await _grab()) break;
    }
    _clock.stop();
    if (mounted) setState(() => _live = false);
  }

  Future<void> _save() async {
    final frame = _frame;
    if (frame == null) return;
    final dir = deviceFolder(
      ref.read(deviceDataDirProvider),
      widget.device,
      'Screenshots',
    );
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final path = p.join(dir, 'Screenshot_$stamp.png');
    await runDeviceAction(context, trf('Saved {0}', [path]), () async {
      await Directory(dir).create(recursive: true);
      await File(path).writeAsBytes(frame);
    });
    revealPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final fps = _live && _clock.elapsedMilliseconds > 0
        ? _frames * 1000 / _clock.elapsedMilliseconds
        : null;
    return DeviceCard(
      title: tr('Screen'),
      icon: Icons.screenshot_monitor_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fps != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                trf('{0} fps', [fps.toStringAsFixed(1)]),
                style: HudTheme.telemetry(size: 12),
              ),
            ),
          NeonButton(
            label: _live ? tr('Stop live') : tr('Live view'),
            icon: _live ? Icons.stop_rounded : Icons.play_arrow_rounded,
            variant: _live ? NeonVariant.danger : NeonVariant.primary,
            compact: true,
            onPressed: _busy ? null : _toggleLive,
          ),
          const SizedBox(width: 8),
          NeonButton(
            label: tr('Screenshot'),
            icon: Icons.camera_alt_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _busy || _live ? null : _single,
          ),
          const SizedBox(width: 8),
          NeonButton(
            label: tr('Save'),
            icon: Icons.save_alt_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _frame == null ? null : _save,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            DeviceError(_error!),
            Text(
              tr(
                'Screenshots need a mounted Developer Disk Image. Mount one from the Tools tab (iOS 16+ also needs Developer Mode enabled).',
              ),
              style: TextStyle(color: HudColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Center(
              child: _frame == null
                  ? EmptyState(
                      icon: Icons.phone_iphone_rounded,
                      title: _busy ? tr('Capturing…') : tr('No capture yet'),
                      message: tr('Take a screenshot or start the live view.'),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: HudColors.glassBorder,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: HudColors.cyan.withValues(alpha: 0.12),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(
                        _frame!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
