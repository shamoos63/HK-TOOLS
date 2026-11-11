import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

final _ddiProvider = FutureProvider.autoDispose.family<(int, bool?), String>((
  ref,
  id,
) async {
  final d = ref.read(devicesProvider).byId(id)!;
  final svc = ref.read(deviceServiceProvider);
  final mounted = await svc.mountedImageCount(d).catchError((_) => -1);
  final devMode = await svc.developerModeEnabled(d).catchError((_) => null);
  return (mounted, devMode);
});

class ToolsTab extends ConsumerWidget {
  ToolsTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    children: [
      LayoutBuilder(
        builder: (context, c) {
          final a = _LocationCard(device: device);
          final b = _DeveloperCard(device: device);
          return c.maxWidth > 900
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    SizedBox(width: 14),
                    Expanded(child: b),
                  ],
                )
              : Column(children: [a, SizedBox(height: 14), b]);
        },
      ),
      SizedBox(height: 14),
      _CrashCard(device: device),
      SizedBox(height: 14),
      _GestaltCard(device: device),
      SizedBox(height: 14),
      _LockdownCard(device: device),
    ],
  );
}

class _LocationCard extends ConsumerStatefulWidget {
  _LocationCard({required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends ConsumerState<_LocationCard> {
  final _lat = TextEditingController();
  final _lon = TextEditingController();

  static const _presets = {
    'Dubai': (25.197197, 55.274376),
    'Riyadh': (24.713552, 46.675296),
    'Amman': (31.953949, 35.910635),
    'London': (51.507351, -0.127758),
    'New York': (40.758896, -73.985130),
    'Cupertino': (37.334606, -122.009102),
    'Tokyo': (35.689487, 139.691711),
  };

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(deviceServiceProvider);
    return DeviceCard(
      title: tr('Virtual location'),
      icon: Icons.location_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Overrides the GPS position reported to every app until reset or reboot. Needs a mounted Developer Disk Image.',
            ),
            style: TextStyle(color: HudColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field(_lat, tr('Latitude'))),
              const SizedBox(width: 8),
              Expanded(child: _field(_lon, tr('Longitude'))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final e in _presets.entries)
                HudChipTab(
                  label: tr(e.key),
                  active: false,
                  onTap: () => setState(() {
                    _lat.text = '${e.value.$1}';
                    _lon.text = '${e.value.$2}';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              NeonButton(
                label: tr('Set location'),
                icon: Icons.my_location_rounded,
                compact: true,
                onPressed: () {
                  final lat = double.tryParse(_lat.text.trim());
                  final lon = double.tryParse(_lon.text.trim());
                  if (lat == null ||
                      lon == null ||
                      lat.abs() > 90 ||
                      lon.abs() > 180) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr('Enter a valid latitude and longitude.'),
                        ),
                      ),
                    );
                    return;
                  }
                  runDeviceAction(
                    context,
                    trf('Location set to {0}, {1}', [lat, lon]),
                    () => svc.setLocation(widget.device, lat, lon),
                  );
                },
              ),
              const SizedBox(width: 8),
              NeonButton(
                label: tr('Reset'),
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: () => runDeviceAction(
                  context,
                  tr('Real location restored'),
                  () => svc.resetLocation(widget.device),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    style: HudTheme.telemetry(color: HudColors.textPrimary),
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _DeveloperCard extends ConsumerWidget {
  const _DeveloperCard({required this.device});

  final ConnectedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ddiProvider(device.id));
    final svc = ref.read(deviceServiceProvider);
    final major =
        int.tryParse((device.info?.productVersion ?? '').split('.').first) ?? 0;
    return DeviceCard(
      title: tr('Developer disk image'),
      icon: Icons.developer_mode_rounded,
      trailing: HudIconButton(
        icon: Icons.refresh_rounded,
        tooltip: tr('Refresh'),
        onPressed: () => ref.invalidate(_ddiProvider(device.id)),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => DeviceError(e),
        data: (v) {
          final (mounted, devMode) = v;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  HudPill(
                    mounted > 0
                        ? tr('Image mounted')
                        : mounted == 0
                        ? tr('No image mounted')
                        : tr('Mount status unknown'),
                    color: mounted > 0 ? HudColors.success : HudColors.warning,
                  ),
                  if (devMode != null)
                    HudPill(
                      devMode
                          ? tr('Developer Mode on')
                          : tr('Developer Mode off'),
                      color: devMode ? HudColors.success : HudColors.warning,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                major >= 17
                    ? tr(
                        'iOS 17+: pick the personalized DDI folder (contains BuildManifest.plist, Image.dmg and Firmware/), e.g. from Xcode’s DeveloperDiskImages.',
                      )
                    : trf(
                        'iOS {0}: pick DeveloperDiskImage.dmg for this iOS version; its .dmg.signature must sit next to it.',
                        [major],
                      ),
                style: TextStyle(color: HudColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NeonButton(
                    label: tr('Mount image…'),
                    icon: Icons.album_rounded,
                    compact: true,
                    onPressed: () async {
                      final path = major >= 17
                          ? await getDirectoryPath(
                              confirmButtonText: tr('Mount'),
                            )
                          : (await openFile(
                              acceptedTypeGroups: [
                                XTypeGroup(
                                  label: tr('Disk image'),
                                  extensions: ['dmg'],
                                ),
                              ],
                            ))?.path;
                      if (path == null || !context.mounted) return;
                      await runDeviceAction(
                        context,
                        tr('Developer disk image mounted'),
                        () => svc.mountDeveloperImage(device, path),
                      );
                      ref.invalidate(_ddiProvider(device.id));
                    },
                  ),
                  if (devMode == false) ...[
                    NeonButton(
                      label: tr('Reveal Developer Mode'),
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: () => runDeviceAction(
                        context,
                        tr(
                          'Settings › Privacy & Security › Developer Mode is now visible',
                        ),
                        () => svc.revealDeveloperMode(device),
                      ),
                    ),
                    NeonButton(
                      label: tr('Enable Developer Mode'),
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: () async {
                        if (await confirmDialog(
                              context,
                              title: tr('Enable Developer Mode?'),
                              message: tr(
                                'The device restarts. After it boots, unlock it and confirm "Turn On" in the prompt. Not possible with a passcode set on some versions.',
                              ),
                              confirmLabel: tr('Enable'),
                            ) &&
                            context.mounted) {
                          await runDeviceAction(
                            context,
                            tr(
                              'Developer Mode armed; confirm on the device after reboot',
                            ),
                            () => svc.enableDeveloperMode(device),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CrashCard extends ConsumerStatefulWidget {
  const _CrashCard({required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<_CrashCard> createState() => _CrashCardState();
}

class _CrashCardState extends ConsumerState<_CrashCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dir = deviceFolder(
      ref.watch(deviceDataDirProvider),
      widget.device,
      'Crash Reports',
    );
    Future<void> pull({required bool remove}) async {
      setState(() => _busy = true);
      final ok = await runDeviceAction(
        context,
        trf('Crash reports copied to {0}', [dir]),
        () => ref
            .read(deviceServiceProvider)
            .pullCrashReports(widget.device, dir, remove: remove),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) revealPath(dir);
    }

    return DeviceCard(
      title: tr('Crash reports & diagnostics logs'),
      icon: Icons.bug_report_rounded,
      child: Row(
        children: [
          Expanded(
            child: Text(
              trf('Copies crash, jetsam and panic logs to {0}', [dir]),
              style: TextStyle(color: HudColors.textMuted, fontSize: 12.5),
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 10),
          NeonButton(
            label: tr('Copy reports'),
            icon: Icons.download_rounded,
            compact: true,
            onPressed: _busy ? null : () => pull(remove: false),
          ),
          const SizedBox(width: 8),
          NeonButton(
            label: tr('Move (clear device)'),
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _busy ? null : () => pull(remove: true),
          ),
        ],
      ),
    );
  }
}

class _GestaltCard extends ConsumerStatefulWidget {
  const _GestaltCard({required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<_GestaltCard> createState() => _GestaltCardState();
}

class _GestaltCardState extends ConsumerState<_GestaltCard> {
  final _keys = TextEditingController(
    text: tr(
      'ProductType HWModelStr ModelNumber RegionInfo ChipID BoardId CPUArchitecture DeviceColor DeviceEnclosureColor main-screen-width main-screen-height',
    ),
  );
  Map<String, Object?>? _result;
  Object? _error;
  bool _busy = false;

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final keys = _keys.text
          .split(RegExp(r'[\s,]+'))
          .where((k) => k.isNotEmpty)
          .toList();
      final r = await ref
          .read(deviceServiceProvider)
          .mobileGestalt(widget.device, keys);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DeviceCard(
    title: tr('MobileGestalt query'),
    icon: Icons.manage_search_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keys,
                style: HudTheme.telemetry(
                  size: 12,
                  color: HudColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Keys (space separated)'),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _query(),
              ),
            ),
            const SizedBox(width: 8),
            NeonButton(
              label: tr('Query'),
              compact: true,
              onPressed: _busy ? null : _query,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Recent iOS versions answer many keys with MobileGestaltDeprecated.',
          ),
          style: TextStyle(color: HudColors.textMuted, fontSize: 11.5),
        ),
        if (_error != null) DeviceError(_error!),
        if (_result != null) ...[
          const SizedBox(height: 8),
          InfoTable([
            for (final e in _result!.entries) (e.key, _fmt(e.value)),
          ], labelWidth: 220),
        ],
      ],
    ),
  );
}

class _LockdownCard extends StatefulWidget {
  const _LockdownCard({required this.device});

  final ConnectedDevice device;

  @override
  State<_LockdownCard> createState() => _LockdownCardState();
}

class _LockdownCardState extends State<_LockdownCard> {
  String _filter = '';
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final raw = widget.device.info?.raw ?? const {};
    final f = _filter.toLowerCase();
    final keys =
        raw.keys.where((k) => f.isEmpty || k.toLowerCase().contains(f)).toList()
          ..sort();
    return DeviceCard(
      title: trf('All lockdown values ({0})', [raw.length]),
      icon: Icons.list_alt_rounded,
      trailing: HudIconButton(
        icon: _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
        tooltip: _open ? tr('Collapse') : tr('Expand'),
        onPressed: () => setState(() => _open = !_open),
      ),
      child: !_open
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  onChanged: (v) => setState(() => _filter = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Filter keys'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                InfoTable([
                  for (final k in keys) (k, _fmt(raw[k])),
                ], labelWidth: 260),
              ],
            ),
    );
  }
}

String _fmt(Object? v) => switch (v) {
  null => '—',
  Uint8List b => '<${b.length} bytes>',
  Map m => '{${m.length} keys}',
  List l => l.map(_fmt).join(', '),
  _ => '$v',
};
