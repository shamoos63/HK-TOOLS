import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/appstore/ipa_library.dart';
import '../../providers/app_store_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/ipa_library_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';

enum _Filter { all, updates, notInstalled, installed }

/// Local IPA collection: install to a device, keep apps up to date from the
/// App Store, import and tidy files.
class IpaLibraryScreen extends ConsumerStatefulWidget {
  const IpaLibraryScreen({super.key});

  @override
  ConsumerState<IpaLibraryScreen> createState() => _IpaLibraryScreenState();
}

class _IpaLibraryScreenState extends ConsumerState<IpaLibraryScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(ipaLibraryProvider);
    final apps = ref.watch(libraryAppsProvider);
    final listings = ref.watch(libraryListingsProvider).value ?? const {};
    final installed = ref.watch(libraryInstalledProvider);
    final target = ref.watch(libraryTargetProvider);

    // Icons for every app in the library (cached after the first fetch).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref
          .read(appIconsProvider.notifier)
          .ensure(apps.map((a) => a.bundleId), device: target),
    );

    bool hasUpdate(LibraryApp a) =>
        isNewerVersion(listings[a.bundleId]?.version, a.latest.version);
    final updates = apps.where(hasUpdate).toList();
    final q = _query.toLowerCase();
    final shown = apps.where((a) {
      if (q.isNotEmpty &&
          !a.name.toLowerCase().contains(q) &&
          !a.bundleId.toLowerCase().contains(q)) {
        return false;
      }
      return switch (_filter) {
        _Filter.all => true,
        _Filter.updates => hasUpdate(a),
        _Filter.notInstalled =>
          target != null && !installed.containsKey(a.bundleId),
        _Filter.installed => installed.containsKey(a.bundleId),
      };
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(appCount: apps.length, updates: updates, listings: listings),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filter by name or bundle ID',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: HudChipTab(
                    label: switch (f) {
                      _Filter.all => 'All ${apps.length}',
                      _Filter.updates => 'Updates ${updates.length}',
                      _Filter.notInstalled => 'Not on device',
                      _Filter.installed => 'On device',
                    },
                    active: f == _filter,
                    enabled:
                        f == _Filter.all ||
                        f == _Filter.updates ||
                        target != null,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: library.isLoading && apps.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : library.hasError
                  ? DeviceError(
                      library.error!,
                      onRetry: () =>
                          ref.read(ipaLibraryProvider.notifier).rescan(),
                    )
                  : shown.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: apps.isEmpty
                          ? 'No IPAs in this folder yet'
                          : 'Nothing matches',
                      message: apps.isEmpty
                          ? 'Download apps from the App Store section, add existing .ipa '
                                'files, or point the library at the folder you keep them in.'
                          : null,
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (_, i) => _AppRow(
                        app: shown[i],
                        listing: listings[shown[i].bundleId],
                        installed: installed[shown[i].bundleId],
                        target: target,
                      ),
                    ),
            ),
          ),
          const _Unreadable(),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.appCount,
    required this.updates,
    required this.listings,
  });

  final int appCount;
  final List<LibraryApp> updates;
  final Map<String, StoreListing> listings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(appStoreDirProvider);
    final files = ref.watch(ipaLibraryProvider).value ?? const <IpaInfo>[];
    final bytes = files.fold<int>(0, (a, f) => a + f.size);
    final keepOld = ref.watch(
      settingsProvider.select((s) => s.keepOldIpaVersions),
    );
    final devices = ref
        .watch(devicesProvider)
        .devices
        .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
        .toList();
    final target = ref.watch(libraryTargetProvider);
    final checking = ref.watch(libraryListingsProvider).isLoading;
    final actions = ref.read(libraryActionsProvider.notifier);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_rounded,
                color: HudColors.cyan,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: 'Show in folder',
                      child: InkWell(
                        onTap: () => Directory(folder).existsSync()
                            ? revealPath(folder)
                            : null,
                        child: Text(
                          folder,
                          overflow: TextOverflow.ellipsis,
                          style: HudTheme.telemetry(
                            size: 12.5,
                            color: HudColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '$appCount apps · ${files.length} files · ${formatBytes(bytes, decimals: 1)}',
                      style: const TextStyle(
                        color: HudColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              HudIconButton(
                icon: Icons.drive_folder_upload_rounded,
                tooltip: 'Change library folder',
                onPressed: () async {
                  final dir = await getDirectoryPath(
                    initialDirectory: Directory(folder).existsSync()
                        ? folder
                        : null,
                    confirmButtonText: 'Use this folder',
                  );
                  if (dir == null) return;
                  ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(ipaDirectory: () => dir));
                },
              ),
              HudIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Add IPA files to the library',
                onPressed: () => _import(context, ref),
              ),
              HudIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Rescan folder and check for updates',
                onPressed: () {
                  ref.read(ipaLibraryProvider.notifier).rescan();
                  ref.invalidate(libraryListingsProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TargetPicker(devices: devices, target: target),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Keep old versions',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  Switch(
                    value: keepOld,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(keepOldIpaVersions: v)),
                  ),
                ],
              ),
              if (checking)
                const Text(
                  'Checking App Store versions…',
                  style: TextStyle(color: HudColors.textMuted, fontSize: 12),
                ),
              if (updates.isNotEmpty)
                NeonButton(
                  label: 'Update all (${updates.length})',
                  icon: Icons.system_update_rounded,
                  compact: true,
                  onPressed: () async {
                    if (!await _ensureSignedIn(context, ref)) return;
                    for (final a in updates) {
                      await actions.update(a, listings[a.bundleId]!);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'iOS apps', extensions: ['ipa']),
      ],
    );
    if (files.isEmpty || !context.mounted) return;
    var n = 0;
    await runDeviceAction(
      context,
      'Added files to the library',
      () async => n = await ref.read(ipaLibraryProvider.notifier).import([
        for (final f in files) f.path,
      ]),
    );
    if (n < files.length && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${files.length - n} file(s) were already in the library folder.',
          ),
        ),
      );
    }
  }
}

class _TargetPicker extends ConsumerWidget {
  const _TargetPicker({required this.devices, required this.target});

  final List<ConnectedDevice> devices;
  final ConnectedDevice? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (devices.isEmpty) {
      return const HudPill(
        'No device connected',
        color: HudColors.textMuted,
        icon: Icons.phone_iphone_rounded,
        mono: false,
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Install target',
      onSelected: (id) => ref.read(libraryTargetIdProvider.notifier).set(id),
      itemBuilder: (_) => [
        for (final d in devices)
          PopupMenuItem(value: d.id, child: Text(d.displayName)),
      ],
      child: HudPill(
        'Install to: ${target?.displayName ?? '—'}',
        color: HudColors.cyan,
        icon: Icons.phone_iphone_rounded,
        mono: false,
      ),
    );
  }
}

class _AppRow extends ConsumerWidget {
  const _AppRow({
    required this.app,
    required this.listing,
    required this.installed,
    required this.target,
  });

  final LibraryApp app;
  final StoreListing? listing;
  final InstalledApp? installed;
  final ConnectedDevice? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = app.latest;
    final job = ref.watch(
      libraryActionsProvider.select((m) => m[app.bundleId]),
    );
    final running = job is LibraryJobRunning;
    final actions = ref.read(libraryActionsProvider.notifier);
    final update = isNewerVersion(listing?.version, latest.version);
    final onDevice = installed?.version;
    final deviceOutdated = isNewerVersion(latest.version, onDevice);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          AppIcon(
            name: app.name,
            path: ref.watch(appIconsProvider.select((m) => m[app.bundleId])),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  [app.bundleId, ?latest.artist].join('  ·  '),
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    HudPill(
                      'v${latest.version ?? '?'}'
                      '${app.files.length > 1 ? ' +${app.files.length - 1} older' : ''}',
                      color: HudColors.textPrimary,
                    ),
                    if (update)
                      HudPill(
                        'Update ${listing!.version}',
                        color: HudColors.warning,
                        icon: Icons.arrow_upward_rounded,
                      )
                    else if (listing != null)
                      const HudPill('Latest', color: HudColors.success)
                    else
                      const HudPill(
                        'Not on App Store',
                        color: HudColors.textMuted,
                        mono: false,
                      ),
                    if (target != null)
                      onDevice == null
                          ? const HudPill(
                              'Not installed',
                              color: HudColors.textMuted,
                              mono: false,
                            )
                          : HudPill(
                              deviceOutdated
                                  ? 'Device has $onDevice'
                                  : 'On device $onDevice',
                              color: deviceOutdated
                                  ? HudColors.purple
                                  : HudColors.cyan,
                            ),
                  ],
                ),
                if (job != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (running)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      else
                        Icon(
                          job is LibraryJobDone
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          size: 14,
                          color: job is LibraryJobDone
                              ? HudColors.success
                              : HudColors.danger,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          switch (job) {
                            LibraryJobRunning(:final label) => label,
                            LibraryJobDone(:final message) => message,
                            LibraryJobFailed(:final message) => message,
                          },
                          style: TextStyle(
                            fontSize: 11.5,
                            color: job is LibraryJobFailed
                                ? HudColors.danger
                                : HudColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              formatBytes(latest.size, decimals: 1),
              textAlign: TextAlign.right,
              style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          if (update)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: NeonButton(
                label: 'Update',
                icon: Icons.system_update_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: running
                    ? null
                    : () async {
                        if (await _ensureSignedIn(context, ref)) {
                          await actions.update(app, listing!);
                        }
                      },
              ),
            ),
          NeonButton(
            label: deviceOutdated ? 'Update on device' : 'Install',
            icon: Icons.install_mobile_rounded,
            compact: true,
            onPressed: target == null || running
                ? null
                : () => actions.install(latest, target!),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: HudColors.textMuted,
            ),
            onSelected: (v) => _menu(context, ref, v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reveal',
                child: Text('Show in folder'),
              ),
              if (target != null && app.files.length > 1)
                for (final f in app.files.skip(1))
                  PopupMenuItem(
                    value: 'install:${f.path}',
                    child: Text(
                      'Install older v${f.version ?? '?'} (${f.build ?? ''})',
                    ),
                  ),
              if (app.files.length > 1)
                PopupMenuItem(
                  value: 'prune',
                  child: Text('Delete ${app.files.length - 1} older file(s)'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete from library…'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String v) async {
    final lib = ref.read(ipaLibraryProvider.notifier);
    if (v == 'reveal') {
      revealPath(app.latest.path);
    } else if (v.startsWith('install:')) {
      final path = v.substring(8);
      final file = app.files.firstWhere((f) => f.path == path);
      await ref.read(libraryActionsProvider.notifier).install(file, target!);
    } else if (v == 'prune') {
      await runDeviceAction(
        context,
        'Older versions of ${app.name} deleted',
        () => lib.deleteFiles(app.files.skip(1).map((f) => f.path)),
      );
    } else if (v == 'delete') {
      final ok = await confirmDialog(
        context,
        title: 'Delete ${app.name} from the library?',
        message:
            '${app.files.length} file(s), ${formatBytes(app.totalSize, decimals: 1)}, '
            'will be deleted from disk:\n'
            '${app.files.map((f) => p.basename(f.path)).join('\n')}',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (!ok || !context.mounted) return;
      await runDeviceAction(
        context,
        '${app.name} removed from the library',
        () => lib.deleteFiles(app.files.map((f) => f.path)),
      );
    }
  }
}

/// Updates download from the App Store, which needs a signed-in Apple ID.
Future<bool> _ensureSignedIn(BuildContext context, WidgetRef ref) async {
  if (ref.read(appStoreToolMissingProvider)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Updating needs ipatool (see the App Store section).'),
      ),
    );
    return false;
  }
  final account = await ref
      .read(storeAccountProvider.future)
      .catchError((_) => null);
  if (account != null) return true;
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Sign in to the App Store to download updates.'),
      action: SnackBarAction(
        label: 'SIGN IN',
        onPressed: () =>
            ref.read(sectionProvider.notifier).set(AppSection.appStore),
      ),
    ),
  );
  return false;
}

class _Unreadable extends ConsumerWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bad = ref.watch(libraryUnreadableProvider);
    if (bad.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tooltip(
        message: bad.map((f) => '${p.basename(f.path)}: ${f.error}').join('\n'),
        child: Text(
          '${bad.length} file(s) in the folder are not readable IPAs (hover for details).',
          style: const TextStyle(color: HudColors.warning, fontSize: 12),
        ),
      ),
    );
  }
}
