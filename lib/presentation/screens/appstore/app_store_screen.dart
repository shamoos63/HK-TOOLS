import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/appstore/app_store_service.dart';
import '../../providers/app_store_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';

/// Search the App Store, download `.ipa` files (latest or older versions) with
/// an Apple ID, and install them on a connected device.
class AppStoreScreen extends ConsumerWidget {
  const AppStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appStoreToolMissingProvider)) return const _ToolMissing();
    final account = ref.watch(storeAccountProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AccountBar(),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: account.value == null
                      ? GlassPanel(
                          child: EmptyState(
                            icon: Icons.storefront_rounded,
                            title: account.isLoading
                                ? 'Checking App Store session…'
                                : 'Sign in to browse the App Store',
                            message:
                                'Search and download any app version your Apple ID can get. '
                                'Free apps are claimed automatically; paid apps must already '
                                'be purchased.',
                          ),
                        )
                      : const _Browser(),
                ),
                const SizedBox(width: 16),
                const SizedBox(width: 330, child: _DownloadsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountBar extends ConsumerWidget {
  const _AccountBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(storeAccountProvider);
    final a = account.value;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.account_circle_rounded,
            size: 30,
            color: a == null ? HudColors.textMuted : HudColors.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: account.isLoading
                ? const LinearProgressIndicator(minHeight: 2)
                : account.hasError
                ? Text(
                    '${account.error}',
                    style: const TextStyle(
                      color: HudColors.danger,
                      fontSize: 12.5,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a == null ? 'Not signed in' : (a.name ?? a.email),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        a == null
                            ? 'Apple ID required for App Store downloads'
                            : a.email,
                        style: HudTheme.telemetry(
                          size: 12,
                          color: HudColors.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),
          if (a == null)
            NeonButton(
              label: 'Sign in with Apple ID',
              icon: Icons.login_rounded,
              compact: true,
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const _SignInDialog(),
              ),
            )
          else
            NeonButton(
              label: 'Sign out',
              icon: Icons.logout_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: () async {
                if (await confirmDialog(
                      context,
                      title: 'Sign out of the App Store?',
                      message:
                          'The saved session is removed from this computer.',
                      confirmLabel: 'Sign out',
                    ) &&
                    context.mounted) {
                  await runDeviceAction(
                    context,
                    'Signed out',
                    () => ref.read(storeAccountProvider.notifier).logout(),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _SignInDialog extends ConsumerStatefulWidget {
  const _SignInDialog();

  @override
  ConsumerState<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _needsCode = false;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  String? _status;
  Process? _process;
  final _clock = Stopwatch();
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _process?.kill();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your Apple ID and password.');
      return;
    }
    if (_needsCode && !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(
        () => _error = 'Enter the 6-digit code shown on your Apple device.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _status = 'Starting…';
    });
    _clock
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final r = await ref
          .read(storeAccountProvider.notifier)
          .login(
            _email.text.trim(),
            _password.text,
            authCode: _needsCode ? _code.text.trim() : null,
            onStatus: (s) {
              if (mounted) setState(() => _status = s);
            },
            onStarted: (p) => _process = p,
          );
      if (!mounted) return;
      switch (r) {
        case LoginSucceeded():
          _password.clear();
          Navigator.pop(context);
        case LoginNeedsCode():
          setState(() => _needsCode = true);
      }
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() => _error = e is AppStoreException ? e.message : '$e');
      }
    } finally {
      _tick?.cancel();
      _clock.stop();
      _process = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (_busy) {
      _cancelled = true;
      _process?.kill();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: HudColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: HudColors.glassBorder),
    ),
    title: const Row(
      children: [
        Icon(Icons.storefront_rounded, color: HudColors.cyan),
        SizedBox(width: 10),
        Text('Sign in to the App Store', style: TextStyle(fontSize: 17)),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            enabled: !_needsCode && !_busy,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Apple ID (email or phone)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            enabled: !_needsCode && !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Password',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_needsCode) ...[
            const SizedBox(height: 14),
            const Text(
              'Apple sent a verification code to your trusted devices.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !_busy,
              maxLength: 6,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              style: HudTheme.telemetry(size: 18, color: HudColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '6-digit code',
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: HudColors.danger, fontSize: 12.5),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _status ?? 'Talking to Apple…',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '${_clock.elapsed.inMinutes}:${(_clock.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: HudTheme.telemetry(
                    size: 12,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'The first sign-in on this computer downloads and prepares Apple\'s '
              'sign-in component. That happens once and can take several minutes.',
              style: TextStyle(
                color: HudColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Your password is sent to Apple through ipatool and is not stored by '
            'HK Tools. Only the App Store session is kept, in your system '
            'keychain (encrypted file on Windows).',
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
        onPressed: _cancel,
      ),
      NeonButton(
        label: _needsCode ? 'Verify' : 'Sign in',
        compact: true,
        onPressed: _busy ? null : _submit,
      ),
    ],
  );
}

class _Browser extends ConsumerStatefulWidget {
  const _Browser();

  @override
  ConsumerState<_Browser> createState() => _BrowserState();
}

class _BrowserState extends ConsumerState<_Browser> {
  final _query = TextEditingController();
  String _term = '';
  bool _purchases = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(storePlatformProvider);
    final results = _purchases
        ? ref.watch(storePurchasesProvider(platform))
        : ref.watch(storeSearchProvider((_term, platform)));
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  onSubmitted: (v) => setState(() {
                    _term = v;
                    _purchases = false;
                  }),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search the App Store (name or keyword) and press Enter',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      onPressed: () => setState(() {
                        _term = _query.text;
                        _purchases = false;
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            children: [
              HudChipTab(
                label: 'Search',
                active: !_purchases,
                onTap: () => setState(() => _purchases = false),
              ),
              HudChipTab(
                label: 'My purchases',
                active: _purchases,
                onTap: () => setState(() => _purchases = true),
              ),
              const SizedBox(width: 14),
              for (final pl in StorePlatform.values)
                HudChipTab(
                  label: pl.label,
                  active: pl == platform,
                  onTap: () => ref.read(storePlatformProvider.notifier).set(pl),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: !_purchases && _term.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search for an app',
                    message: 'Try "WhatsApp", "Telegram", or a bundle keyword.',
                  )
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => DeviceError(
                      e,
                      onRetry: () => _purchases
                          ? ref.invalidate(storePurchasesProvider(platform))
                          : ref.invalidate(
                              storeSearchProvider((_term, platform)),
                            ),
                    ),
                    data: (apps) {
                      // Deduplicated inside ensure(); cheap to call per build.
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => ref
                            .read(appIconsProvider.notifier)
                            .ensure(apps.map((a) => a.bundleId)),
                      );
                      return apps.isEmpty
                          ? const EmptyState(
                              icon: Icons.apps_outage_rounded,
                              title: 'No apps found',
                            )
                          : ListView.separated(
                              itemCount: apps.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              itemBuilder: (_, i) => _StoreAppRow(
                                app: apps[i],
                                platform: platform,
                              ),
                            );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StoreAppRow extends ConsumerWidget {
  const _StoreAppRow({required this.app, required this.platform});

  final StoreApp app;
  final StorePlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          AppIcon(
            name: app.name,
            path: ref.watch(appIconsProvider.select((m) => m[app.bundleId])),
            size: 40,
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
                  '${app.bundleId}${app.version == null ? '' : '  ·  v${app.version}'}',
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.telemetry(
                    size: 11.5,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          HudPill(
            app.isFree ? 'Free' : '\$${app.price.toStringAsFixed(2)}',
            color: app.isFree ? HudColors.success : HudColors.warning,
          ),
          const SizedBox(width: 8),
          HudIconButton(
            icon: Icons.history_rounded,
            tooltip: 'Download an older version…',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _VersionsDialog(app: app, platform: platform),
            ),
          ),
          NeonButton(
            label: 'Download',
            icon: Icons.download_rounded,
            compact: true,
            onPressed: () => _downloadIpa(ref, app, platform),
          ),
        ],
      ),
    );
  }
}

/// Starts an `.ipa` download, first asking for a folder when Settings ›
/// Downloads › "Ask where to save each IPA" is on. [beforeStart] runs once
/// the folder is chosen (the versions dialog closes itself there).
Future<void> _downloadIpa(
  WidgetRef ref,
  StoreApp app,
  StorePlatform platform, {
  String? externalVersionId,
  String? versionLabel,
  VoidCallback? beforeStart,
}) async {
  // Read everything up front: the calling widget may be gone after the
  // folder picker (the versions dialog closes).
  final downloads = ref.read(storeDownloadsProvider.notifier);
  final ask = ref.read(settingsProvider).askIpaLocation;
  final initial = ref.read(appStoreDirProvider);
  String? dir;
  if (ask) {
    dir = await getDirectoryPath(
      initialDirectory: Directory(initial).existsSync() ? initial : null,
      confirmButtonText: 'Save here',
    );
    if (dir == null) return;
  }
  beforeStart?.call();
  await downloads.start(
    app,
    platform: platform,
    externalVersionId: externalVersionId,
    versionLabel: versionLabel,
    directory: dir,
  );
}

class _VersionsDialog extends ConsumerWidget {
  const _VersionsDialog({required this.app, required this.platform});

  final StoreApp app;
  final StorePlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(storeVersionIdsProvider((app, platform)));
    return AlertDialog(
      backgroundColor: HudColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HudColors.glassBorder),
      ),
      title: Text(
        'Versions of ${app.name}',
        style: const TextStyle(fontSize: 17),
      ),
      content: SizedBox(
        width: 480,
        height: 440,
        child: ids.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => DeviceError(e),
          data: (list) {
            final newestFirst = list.reversed.toList();
            return ListView.builder(
              itemCount: newestFirst.length,
              itemBuilder: (_, i) => _VersionRow(
                app: app,
                platform: platform,
                externalId: newestFirst[i],
                latest: i == 0,
              ),
            );
          },
        ),
      ),
      actions: [
        NeonButton(
          label: 'Close',
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _VersionRow extends ConsumerWidget {
  const _VersionRow({
    required this.app,
    required this.platform,
    required this.externalId,
    required this.latest,
  });

  final StoreApp app;
  final StorePlatform platform;
  final String externalId;
  final bool latest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Metadata is one request per version, so it loads as rows scroll in.
    final meta = ref
        .watch(storeVersionMetaProvider((app, externalId, platform)))
        .value;
    final d = meta?.releaseDate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              meta?.displayVersion ?? '…',
              style: HudTheme.telemetry(size: 13, color: HudColors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              d == null
                  ? 'id $externalId'
                  : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  ·  id $externalId',
              style: HudTheme.telemetry(size: 11.5, color: HudColors.textMuted),
            ),
          ),
          if (latest) const HudPill('Latest', color: HudColors.cyan),
          const SizedBox(width: 6),
          HudIconButton(
            icon: Icons.download_rounded,
            tooltip: 'Download this version',
            onPressed: () {
              final navigator = Navigator.of(context);
              _downloadIpa(
                ref,
                app,
                platform,
                externalVersionId: externalId,
                versionLabel: meta?.displayVersion ?? externalId,
                beforeStart: navigator.pop,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadsPanel extends ConsumerWidget {
  const _DownloadsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(storeDownloadsProvider);
    final dir = ref.watch(appStoreDirProvider);
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.downloading_rounded,
                size: 16,
                color: HudColors.cyan,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: HudLabel('IPA downloads', color: HudColors.textPrimary),
              ),
              HudIconButton(
                icon: Icons.folder_open_rounded,
                tooltip: dir,
                onPressed: () {
                  Directory(dir).createSync(recursive: true);
                  revealPath(dir);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: jobs.isEmpty
                ? const Center(
                    child: Text(
                      'Downloaded apps appear here.',
                      style: TextStyle(
                        color: HudColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                : ListView(children: [for (final j in jobs) _JobTile(job: j)]),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});

  final StoreDownload job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(storeDownloadsProvider.notifier);
    final color = switch (job.status) {
      StoreJobStatus.done => HudColors.success,
      StoreJobStatus.failed => HudColors.danger,
      StoreJobStatus.cancelled => HudColors.textMuted,
      StoreJobStatus.downloading => HudColors.cyan,
    };
    final devices = ref
        .watch(devicesProvider)
        .devices
        .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.app.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (job.versionLabel != null)
                Text(
                  'v${job.versionLabel}',
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (job.status == StoreJobStatus.downloading) ...[
            job.fraction == null
                ? const LinearProgressIndicator(minHeight: 3)
                : GlowProgressBar(value: job.fraction!, height: 4),
            const SizedBox(height: 4),
            Text(
              job.detail ?? 'Preparing… (claiming license if needed)',
              style: HudTheme.telemetry(size: 10.5, color: HudColors.textMuted),
            ),
          ] else if (job.status == StoreJobStatus.failed)
            Text(
              job.error ?? 'Failed',
              style: const TextStyle(color: HudColors.danger, fontSize: 12),
            )
          else if (job.status == StoreJobStatus.done)
            Text(
              p.basename(job.path!),
              overflow: TextOverflow.ellipsis,
              style: HudTheme.telemetry(size: 11, color: HudColors.success),
            )
          else
            const Text(
              'Cancelled',
              style: TextStyle(color: HudColors.textMuted, fontSize: 12),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (job.status == StoreJobStatus.done) ...[
                HudIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: 'Show file',
                  onPressed: () => revealPath(job.path!),
                ),
                if (devices.isNotEmpty)
                  PopupMenuButton<ConnectedDevice>(
                    tooltip: 'Install on a device',
                    onSelected: (d) => runDeviceAction(
                      context,
                      '${job.app.name} installed on ${d.displayName}',
                      () => ref
                          .read(deviceServiceProvider)
                          .installApp(d, job.path!),
                    ),
                    itemBuilder: (_) => [
                      for (final d in devices)
                        PopupMenuItem(
                          value: d,
                          child: Text('Install on ${d.displayName}'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.install_mobile_rounded,
                            size: 17,
                            color: HudColors.cyan,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Install',
                            style: TextStyle(
                              color: HudColors.cyan,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (job.status == StoreJobStatus.downloading)
                HudIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Cancel',
                  color: HudColors.danger,
                  onPressed: () => ctl.cancel(job.id),
                )
              else
                HudIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Remove from list',
                  onPressed: () => ctl.remove(job.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolMissing extends ConsumerWidget {
  const _ToolMissing();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
    child: GlassPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 44,
                color: HudColors.cyan.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 14),
              const Text(
                'ipatool not found',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SelectableText(
                Platform.isWindows
                    ? 'Download ipatool for Windows from github.com/majd/ipatool/releases '
                          'and put ipatool.exe in the device tools folder (a "tools" folder '
                          'next to hk_tools.exe, or the folder set in Settings).'
                    : 'Install it with Homebrew:\n  brew install ipatool',
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
