import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Live device syslog (`idevicesyslog`).
class ConsoleTab extends ConsumerStatefulWidget {
  const ConsoleTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends ConsumerState<ConsoleTab> {
  final _scroll = ScrollController();
  final _process = TextEditingController();
  String _filter = '';
  bool _quiet = true;
  bool _follow = true;

  @override
  void dispose() {
    _scroll.dispose();
    _process.dispose();
    super.dispose();
  }

  SyslogController get _ctl =>
      ref.read(syslogProvider(widget.device.id).notifier);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syslogProvider(widget.device.id));
    final lower = _filter.toLowerCase();
    final lines = lower.isEmpty
        ? s.lines
        : s.lines.where((l) => l.toLowerCase().contains(lower)).toList();
    if (_follow && lines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    return DeviceCard(
      title: tr('Console'),
      icon: Icons.terminal_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.running)
            Padding(
              padding: EdgeInsets.only(right: 10),
              child: PulseDot(color: HudColors.success, size: 6),
            ),
          NeonButton(
            label: s.running ? tr('Stop') : tr('Start'),
            icon: s.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            variant: s.running ? NeonVariant.danger : NeonVariant.primary,
            compact: true,
            onPressed: () => s.running
                ? _ctl.stop()
                : _ctl.start(quiet: _quiet, process: _process.text.trim()),
          ),
          HudIconButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: tr('Clear'),
            onPressed: _ctl.clear,
          ),
          HudIconButton(
            icon: Icons.save_alt_rounded,
            tooltip: tr('Save log'),
            onPressed: s.lines.isEmpty ? null : () => _save(s.lines),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _filter = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Filter lines'),
                    prefixIcon: Icon(Icons.filter_alt_outlined, size: 16),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _process,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Only process (e.g. SpringBoard)'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: tr('Hide noisy system daemons'),
                child: Row(
                  children: [
                    Text(tr('Quiet'), style: TextStyle(fontSize: 12.5)),
                    Switch(
                      value: _quiet,
                      onChanged: (v) => setState(() => _quiet = v),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: tr('Auto-scroll to newest'),
                child: Row(
                  children: [
                    Text(tr('Follow'), style: TextStyle(fontSize: 12.5)),
                    Switch(
                      value: _follow,
                      onChanged: (v) => setState(() => _follow = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.error != null) DeviceError(s.error!),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: HudColors.overlay.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HudColors.overlay.withValues(alpha: 0.06),
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: lines.isEmpty
                  ? Center(
                      child: Text(
                        s.running
                            ? tr('Waiting for log lines…')
                            : tr('Press Start to stream the device log.'),
                        style: TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: lines.length,
                        itemExtent: 17,
                        itemBuilder: (_, i) => Text(
                          lines[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HudTheme.telemetry(
                            size: 11.5,
                            color: _color(lines[i]),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _color(String l) {
    if (l.contains('<Error>') || l.contains('<Fault>')) return HudColors.danger;
    if (l.contains('<Warning>') || l.contains('<Notice>')) {
      return HudColors.warning;
    }
    return HudColors.textPrimary.withValues(alpha: 0.85);
  }

  Future<void> _save(List<String> lines) async {
    final dir = deviceFolder(
      ref.read(deviceDataDirProvider),
      widget.device,
      tr('Logs'),
    );
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final path = p.join(dir, 'syslog_$stamp.log');
    await runDeviceAction(context, trf('Saved {0}', [path]), () async {
      await Directory(dir).create(recursive: true);
      await File(path).writeAsString(lines.join('\n'));
    });
    revealPath(path);
  }
}
