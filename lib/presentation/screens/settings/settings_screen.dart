import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../core/utils/folder_access.dart';
import '../../../domain/entities/app_settings.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/app_store_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/setup_providers.dart';
import '../setup/setup_assistant.dart';
import '../../widgets/hud_widgets.dart';
import '../../../core/l10n/l10n.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ipaDir = ref.watch(appStoreDirProvider);
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 6, 24, 24),
      children: [
        _AboutSection(),
        SizedBox(height: 16),
        _Section(
          title: tr('Interface'),
          icon: Icons.aspect_ratio_rounded,
          children: [
            _ChoiceRow<AppearanceMode>(
              label: tr('Appearance'),
              help: tr(
                'Automatic follows the light or dark mode of this computer.',
              ),
              value: s.appearance,
              options: {
                AppearanceMode.system: tr('Automatic'),
                AppearanceMode.light: tr('Light'),
                AppearanceMode.dark: tr('Dark'),
              },
              onChanged: (v) => update((x) => x.copyWith(appearance: v)),
            ),
            _ChoiceRow<AppLanguage>(
              label: tr('Language'),
              help: tr(
                'Automatic uses Arabic when it is the language of this computer.',
              ),
              value: s.language,
              options: {
                AppLanguage.system: tr('Automatic'),
                AppLanguage.english: tr('English'),
                AppLanguage.arabic: 'العربية',
              },
              onChanged: (v) => update((x) => x.copyWith(language: v)),
            ),
            _SliderRow(
              label: tr('Interface size'),
              help: tr(
                'Scales text and controls. Small windows shrink the interface further so everything fits.',
              ),
              value: (s.effectiveUiScale * 100).round(),
              min: 75,
              max: 125,
              divisions: 10,
              display:
                  '${(s.effectiveUiScale * 100).round()}%'
                  '${s.uiScale == null ? ' (default)' : ''}',
              onChanged: (v) =>
                  update((x) => x.copyWith(uiScale: () => v / 100)),
            ),
            _SwitchRow(
              label: tr('Reduced visual effects'),
              help: tr(
                'Solid panels without background glows or live blur. Use it if parts of the window look white or washed out (some graphics drivers), or to save battery. On by default on Windows.',
              ),
              value: s.effectiveReducedEffects,
              onChanged: (v) =>
                  update((x) => x.copyWith(reducedEffects: () => v)),
            ),
          ],
        ),
        _Section(
          title: tr('Downloads'),
          icon: Icons.folder_rounded,
          children: [
            _FolderRow(
              label: tr('IPSW download folder'),
              help: _withDriveWarning(
                tr(
                  'Firmware downloads land here. This is also the repository the Repository scanner audits.',
                ),
                s.targetDirectory,
              ),
              path: s.targetDirectory,
              onPick: (p) => update((x) => x.copyWith(targetDirectory: p)),
            ),
            _FolderRow(
              label: tr('IPA library folder'),
              help: _withDriveWarning(
                tr(
                  'App Store downloads (.ipa) land here, and the IPA Library lists this folder.',
                ),
                ipaDir,
              ),
              path: s.ipaDirectory,
              placeholder: ipaDir,
              onPick: (p) => update((x) => x.copyWith(ipaDirectory: () => p)),
              onClear: s.ipaDirectory == null
                  ? null
                  : () => update((x) => x.copyWith(ipaDirectory: () => null)),
            ),
            _SwitchRow(
              label: tr('Ask where to save each IPA'),
              help: tr('Choose a folder every time you download an app.'),
              value: s.askIpaLocation,
              onChanged: (v) => update((x) => x.copyWith(askIpaLocation: v)),
            ),
            _FolderRow(
              label: tr('Temp folder'),
              help: tr(
                'Optional scratch location for partial .hkdl files (e.g. a fast SSD). Same volume as the repository avoids a 10 GB copy at the end.',
              ),
              path: s.tempDirectory,
              placeholder: tr('Same as repository folder'),
              onPick: (p) => update((x) => x.copyWith(tempDirectory: () => p)),
              onClear: s.tempDirectory == null
                  ? null
                  : () => update((x) => x.copyWith(tempDirectory: () => null)),
            ),
            _SwitchRow(
              label: tr('Per-device hardlinks'),
              help: tr(
                'After a download, add "By Device/<identifier>_<version>_<build>_Restore.ipsw" hardlinks for every device the payload serves. Uses no extra disk space.',
              ),
              value: s.autoDeviceLinks,
              onChanged: (v) => update((x) => x.copyWith(autoDeviceLinks: v)),
            ),
          ],
        ),
        _Section(
          title: tr('Download engine'),
          icon: Icons.bolt_rounded,
          children: [
            _SliderRow(
              label: tr('Threads per download'),
              help: tr(
                'Parallel HTTP range connections. Idle threads split the largest remaining chunk.',
              ),
              value: s.threads,
              min: 2,
              max: 16,
              display: '${s.threads}',
              onChanged: (v) => update((x) => x.copyWith(threads: v)),
            ),
            _SliderRow(
              label: tr('Concurrent downloads'),
              help: tr(
                'Files transferring at the same time; the rest wait in queue order.',
              ),
              value: s.maxConcurrentDownloads,
              min: 1,
              max: 6,
              display: '${s.maxConcurrentDownloads}',
              onChanged: (v) =>
                  update((x) => x.copyWith(maxConcurrentDownloads: v)),
            ),
            _SliderRow(
              label: tr('Global speed cap'),
              help: tr(
                'Shared across all threads of all downloads. 0 = unlimited.',
              ),
              value: s.globalSpeedLimitBytesPerSecond ~/ (1024 * 1024),
              min: 0,
              max: 200,
              divisions: 40,
              display: s.globalSpeedLimitBytesPerSecond == 0
                  ? tr('Unlimited')
                  : formatRate(s.globalSpeedLimitBytesPerSecond),
              onChanged: (v) => update(
                (x) =>
                    x.copyWith(globalSpeedLimitBytesPerSecond: v * 1024 * 1024),
              ),
            ),
            _SliderRow(
              label: tr('Link refresh timeout'),
              help: tr(
                'How long to wait for IPSW.me when an expired Apple CDN link is re-resolved.',
              ),
              value: s.linkRefreshTimeout.inSeconds,
              min: 10,
              max: 120,
              divisions: 22,
              display: '${s.linkRefreshTimeout.inSeconds}s',
              onChanged: (v) => update(
                (x) => x.copyWith(linkRefreshTimeout: Duration(seconds: v)),
              ),
            ),
            _SwitchRow(
              label: tr('Verify SHA1 after download'),
              help: tr(
                'Hashes the file on a background isolate and compares with IPSW.me.',
              ),
              value: s.autoVerifySha1,
              onChanged: (v) => update((x) => x.copyWith(autoVerifySha1: v)),
            ),
          ],
        ),
        const _DeviceToolsSection(),
        const _CatalogSection(),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: HudColors.cyan),
              const SizedBox(width: 8),
              HudLabel(title, color: HudColors.cyan),
            ],
          ),
          const SizedBox(height: 8),
          for (final (i, c) in children.indexed) ...[
            if (i > 0)
              Divider(
                color: HudColors.overlay.withValues(alpha: 0.06),
                height: 1,
              ),
            c,
          ],
        ],
      ),
    ),
  );
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.label,
    required this.help,
    required this.trailing,
  });

  final String label;
  final String help;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                help,
                style: TextStyle(fontSize: 12, color: HudColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        trailing,
      ],
    ),
  );
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.label,
    required this.help,
    required this.path,
    required this.onPick,
    this.placeholder = '',
    this.onClear,
  });

  final String label;
  final String help;
  final String? path;
  final String placeholder;
  final ValueChanged<String> onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => _RowShell(
    label: label,
    help: help,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 340,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: HudColors.overlay.withValues(alpha: 0.05),
            border: Border.all(
              color: HudColors.overlay.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            path ?? placeholder,
            // File paths read left to right in every language.
            textDirection: path == null ? null : TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HudTheme.telemetry(
              size: 12,
              color: path == null ? HudColors.textMuted : HudColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (onClear != null) ...[
          HudIconButton(
            icon: Icons.close_rounded,
            tooltip: tr('Clear'),
            onPressed: onClear,
          ),
          const SizedBox(width: 4),
        ],
        NeonButton(
          label: tr('Choose'),
          icon: Icons.folder_open_rounded,
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: () async {
            final picked = await getDirectoryPath(
              initialDirectory: path,
              confirmButtonText: tr('Use folder'),
            );
            if (picked != null) onPick(picked);
          },
        ),
      ],
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String help;
  final int value;
  final int min;
  final int max;
  final int? divisions;
  final String display;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
    label: label,
    help: help,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 300,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: HudColors.cyan,
              inactiveTrackColor: HudColors.overlay.withValues(alpha: 0.1),
              thumbColor: HudColors.cyan,
              overlayColor: HudColors.cyan.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions ?? (max - min),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: HudTheme.telemetry(size: 13),
          ),
        ),
      ],
    ),
  );
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.help,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String help;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
    label: label,
    help: help,
    trailing: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HudColors.overlay.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: e.key == value
                      ? HudColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: e.key == value
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: e.key == value
                        ? HudColors.textPrimary
                        : HudColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
    label: label,
    help: help,
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

class _CatalogSection extends ConsumerWidget {
  const _CatalogSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(catalogProvider).value;
    return _Section(
      title: tr('Catalog cache'),
      icon: Icons.cloud_sync_rounded,
      children: [
        _RowShell(
          label: tr('IPSW.me index'),
          help: state == null
              ? tr('Loading…')
              : trf(
                  '{0} devices · {1} unique payloads · {2} signed. Device lists refresh every 24 h, firmware every 6 h.',
                  [
                    state.index.devices.length,
                    state.index.payloadCount,
                    state.index.signedPayloadCount,
                  ],
                ),
          trailing: Row(
            children: [
              NeonButton(
                label: tr('Clear cache'),
                variant: NeonVariant.danger,
                compact: true,
                onPressed: () async {
                  await ref.read(catalogRepositoryProvider).clearCache();
                  ref.invalidate(catalogProvider);
                },
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: state?.syncing ?? false
                    ? tr('Syncing…')
                    : tr('Resync now'),
                icon: Icons.sync_rounded,
                compact: true,
                onPressed: state?.syncing ?? true
                    ? null
                    : () =>
                          ref.read(catalogProvider.notifier).sync(force: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      glow: true,
      borderColor: HudColors.purple.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: HudColors.cyan.withValues(alpha: 0.25),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                Branding.logo,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HudLabel(tr('About'), color: HudColors.cyan),
                const SizedBox(height: 8),
                Text(
                  Branding.appName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trf('Version {0}', [Branding.version]),
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  Branding.credit,
                  style: TextStyle(fontSize: 14, color: HudColors.textPrimary),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    NeonButton(
                      label: trf('Telegram: {0}', [Branding.telegramLabel]),
                      icon: Icons.send_rounded,
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: () => Branding.open(Branding.telegramUrl),
                    ),
                    NeonButton(
                      label: trf('Website: {0}', [Branding.websiteLabel]),
                      icon: Icons.language_rounded,
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: () => Branding.open(Branding.websiteUrl),
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

class _DeviceToolsSection extends ConsumerWidget {
  const _DeviceToolsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final found = ref.watch(deviceToolchainProvider).probeAll();
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);
    final missing = found.entries.where((e) => e.value == null).toList();
    return _Section(
      title: tr('Device tools'),
      icon: Icons.phone_iphone_rounded,
      children: [
        _FolderRow(
          label: tr('Tools folder'),
          help: tr(
            'Folder with the libimobiledevice tools and idevicerestore. Empty = auto-detect (a "tools" folder next to the app, PATH, Homebrew).',
          ),
          path: s.deviceToolsDirectory,
          placeholder: tr('Auto-detect'),
          onPick: (p) =>
              update((x) => x.copyWith(deviceToolsDirectory: () => p)),
          onClear: s.deviceToolsDirectory == null
              ? null
              : () =>
                    update((x) => x.copyWith(deviceToolsDirectory: () => null)),
        ),
        _FolderRow(
          label: tr('Device data folder'),
          help: tr(
            'Backups, screenshots, imported photos, pulled files and crash logs.',
          ),
          path: s.deviceDataDirectory,
          placeholder: ref.watch(deviceDataDirProvider),
          onPick: (p) =>
              update((x) => x.copyWith(deviceDataDirectory: () => p)),
          onClear: s.deviceDataDirectory == null
              ? null
              : () =>
                    update((x) => x.copyWith(deviceDataDirectory: () => null)),
        ),
        _RowShell(
          label: missing.isEmpty
              ? trf('All {0} tools found', [found.length])
              : trf('{0} of {1} tools found', [
                  found.length - missing.length,
                  found.length,
                ]),
          help: missing.isEmpty
              ? tr('Every device feature is available.')
              : trf('Missing: {0}', [
                  missing
                      .map((e) => '${e.key.executable} (${e.key.purpose})')
                      .join(', '),
                ]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeonButton(
                label: tr('Re-check'),
                icon: Icons.refresh_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: () => ref.invalidate(deviceToolchainProvider),
              ),
              const SizedBox(width: 8),
              NeonButton(
                label: tr('Setup assistant'),
                icon: Icons.build_circle_rounded,
                compact: true,
                onPressed: () {
                  ref.invalidate(dependencyStatusProvider);
                  showSetupAssistant(context);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in found.entries)
                Tooltip(
                  message: e.value ?? tr('Not found'),
                  child: HudPill(
                    e.key.executable,
                    color: e.value != null
                        ? HudColors.success
                        : e.key.core
                        ? HudColors.danger
                        : HudColors.warning,
                    icon: e.value != null
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Appends a warning when [path] is on a drive that isn't connected.
String _withDriveWarning(String help, String path) {
  final volume = missingVolume(path);
  return volume == null
      ? help
      : trf('{0}\n⚠ {1} is not connected: downloads will fail until it is.', [
          help,
          volume,
        ]);
}
