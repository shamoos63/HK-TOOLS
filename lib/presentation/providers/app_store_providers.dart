import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/folder_access.dart';
import '../../services/appstore/app_store_service.dart';
import '../../services/device/device_toolchain.dart';
import 'core_providers.dart';
import 'device_providers.dart';

/// Passphrase for ipatool's file keyring on Windows/Linux (macOS uses the
/// system Keychain). Generated once per install and kept in app support, so
/// the session survives restarts without asking the user for another secret.
final ipatoolPassphraseProvider = Provider<String?>((ref) {
  if (Platform.isMacOS) return null;
  final file = File(p.join(ref.watch(appSupportDirProvider), 'ipatool.key'));
  try {
    if (file.existsSync()) {
      final v = file.readAsStringSync().trim();
      if (v.isNotEmpty) return v;
    }
    final rnd = Random.secure();
    final v = base64UrlEncode(List.generate(32, (_) => rnd.nextInt(256)));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(v);
    return v;
  } on FileSystemException {
    return null;
  }
});

final appStoreServiceProvider = Provider<AppStoreService>(
  (ref) => AppStoreService(
    ref.watch(deviceToolchainProvider),
    keychainPassphrase: ref.watch(ipatoolPassphraseProvider),
  ),
);

final appStoreToolMissingProvider = Provider<bool>(
  (ref) => !ref.watch(deviceToolchainProvider).has(DeviceTool.ipatool),
);

/// Where downloaded `.ipa` files go (Settings › Downloads).
final appStoreDirProvider = Provider<String>(
  (ref) =>
      ref.watch(settingsProvider.select((s) => s.ipaDirectory)) ??
      p.join(ref.watch(downloadsDirProvider), 'HK Tools', 'App Store'),
);

class StoreAccountController extends AsyncNotifier<StoreAccount?> {
  @override
  Future<StoreAccount?> build() async {
    if (ref.watch(appStoreToolMissingProvider)) return null;
    return ref.watch(appStoreServiceProvider).account();
  }

  /// First call without [authCode]; when it returns [LoginNeedsCode], call
  /// again with the code Apple sent to the user's trusted devices.
  Future<LoginResult> login(
    String email,
    String password, {
    String? authCode,
    void Function(String status)? onStatus,
    void Function(Process process)? onStarted,
  }) async {
    final result = await ref
        .read(appStoreServiceProvider)
        .login(
          email,
          password,
          authCode: authCode,
          onStatus: onStatus,
          onStarted: onStarted,
        );
    if (result is LoginSucceeded) state = AsyncData(result.account);
    return result;
  }

  Future<void> logout() async {
    await ref.read(appStoreServiceProvider).logout();
    state = const AsyncData(null);
  }
}

final storeAccountProvider =
    AsyncNotifierProvider<StoreAccountController, StoreAccount?>(
      StoreAccountController.new,
    );

final storePlatformProvider =
    NotifierProvider<ValueController<StorePlatform>, StorePlatform>(
      () => ValueController(StorePlatform.iphone),
    );

/// Search results for (term, platform); empty term = nothing.
final storeSearchProvider = FutureProvider.autoDispose
    .family<List<StoreApp>, (String, StorePlatform)>((ref, key) async {
      if (key.$1.trim().isEmpty) return const [];
      return ref
          .watch(appStoreServiceProvider)
          .search(key.$1.trim(), platform: key.$2);
    });

final storePurchasesProvider = FutureProvider.autoDispose
    .family<List<StoreApp>, StorePlatform>(
      (ref, platform) =>
          ref.watch(appStoreServiceProvider).purchases(platform: platform),
    );

final storeVersionIdsProvider = FutureProvider.autoDispose
    .family<List<String>, (StoreApp, StorePlatform)>(
      (ref, key) =>
          ref.watch(appStoreServiceProvider).versionIds(key.$1, key.$2),
    );

final storeVersionMetaProvider = FutureProvider.autoDispose
    .family<StoreVersion, (StoreApp, String, StorePlatform)>(
      (ref, key) => ref
          .watch(appStoreServiceProvider)
          .versionMetadata(key.$1, key.$2, key.$3),
    );

enum StoreJobStatus { downloading, done, failed, cancelled }

class StoreDownload {
  const StoreDownload({
    required this.id,
    required this.app,
    required this.platform,
    this.versionLabel,
    this.status = StoreJobStatus.downloading,
    this.fraction,
    this.detail,
    this.path,
    this.error,
  });

  final String id;
  final StoreApp app;
  final StorePlatform platform;
  final String? versionLabel;
  final StoreJobStatus status;
  final double? fraction;
  final String? detail;
  final String? path;
  final String? error;

  StoreDownload copyWith({
    StoreJobStatus? status,
    double? fraction,
    String? detail,
    String? path,
    String? error,
  }) => StoreDownload(
    id: id,
    app: app,
    platform: platform,
    versionLabel: versionLabel,
    status: status ?? this.status,
    fraction: fraction ?? this.fraction,
    detail: detail ?? this.detail,
    path: path ?? this.path,
    error: error ?? this.error,
  );
}

class StoreDownloadsController extends Notifier<List<StoreDownload>> {
  final Map<String, Process> _processes = {};

  @override
  List<StoreDownload> build() {
    ref.onDispose(() {
      for (final proc in _processes.values) {
        proc.kill();
      }
    });
    return const [];
  }

  void _update(String id, StoreDownload Function(StoreDownload) f) =>
      state = [for (final d in state) d.id == id ? f(d) : d];

  /// Downloads [app] and completes with the `.ipa` path (or `null` on
  /// failure/cancel). Progress is visible in [state].
  Future<String?> start(
    StoreApp app, {
    required StorePlatform platform,
    String? externalVersionId,
    String? versionLabel,
    String? directory,
  }) async {
    final String dir = directory ?? ref.read(appStoreDirProvider);
    final id =
        '${app.id}-${externalVersionId ?? 'latest'}-${DateTime.now().microsecondsSinceEpoch}';
    state = [
      StoreDownload(
        id: id,
        app: app,
        platform: platform,
        versionLabel: versionLabel,
      ),
      ...state,
    ];
    try {
      String? path;
      await for (final e
          in ref
              .read(appStoreServiceProvider)
              .download(
                app,
                ref.read(appStoreDirProvider),
                platform: platform,
                externalVersionId: externalVersionId,
                versionLabel: versionLabel,
                onStarted: (proc) => _processes[id] = proc,
              )) {
        switch (e) {
          case StoreDownloadProgress(:final fraction, :final detail):
            _update(id, (d) => d.copyWith(fraction: fraction, detail: detail));
          case StoreDownloadDone(path: final done):
            path = done;
            _update(
              id,
              (d) => d.copyWith(
                status: StoreJobStatus.done,
                fraction: 1,
                path: done,
              ),
            );
        }
      }
      return path;
    } on Object catch (e) {
      final cancelled = state.any(
        (d) => d.id == id && d.status == StoreJobStatus.cancelled,
      );
      if (!cancelled) {
        _update(
          id,
          (d) => d.copyWith(
            status: StoreJobStatus.failed,
            error: switch (e) {
              AppStoreException() => e.message,
              FileSystemException() => describeFolderError(e, dir),
              _ => '$e',
            },
          ),
        );
        if (e is AppStoreException && e.notSignedIn) {
          ref.invalidate(storeAccountProvider);
        }
      }
      return null;
    } finally {
      _processes.remove(id);
    }
  }

  void cancel(String id) {
    _update(id, (d) => d.copyWith(status: StoreJobStatus.cancelled));
    _processes.remove(id)?.kill();
  }

  void remove(String id) => state = [
    for (final d in state)
      if (d.id != id) d,
  ];
}

final storeDownloadsProvider =
    NotifierProvider<StoreDownloadsController, List<StoreDownload>>(
      StoreDownloadsController.new,
    );
