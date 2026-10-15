import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../data/api/ipsw_api_client.dart';
import '../../data/repositories/settings_store.dart';
import '../../domain/entities/app_settings.dart';

/// Values resolved in `main()` before the first frame and injected via
/// `ProviderScope.overrides`.
final appSupportDirProvider = Provider<String>(
  (_) => throw UnimplementedError(),
);

/// The user's Downloads folder (falls back to app support).
final downloadsDirProvider = Provider<String>(
  (_) => throw UnimplementedError(),
);
final catalogBoxProvider = Provider<Box<String>>(
  (_) => throw UnimplementedError(),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError(),
);

final ipswApiClientProvider = Provider<IpswApiClient>((ref) {
  final client = IpswApiClient();
  ref.onDispose(client.close);
  return client;
});

/// Simple holder for UI state (selected section, tab, etc.).
class ValueController<T> extends Notifier<T> {
  ValueController(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final saved = ref.watch(settingsStoreProvider).load();
    // Dev/QA: `--dart-define=HK_REPO_DIR=/path` points at a scratch repository
    // for this run without touching saved settings.
    const devRepo = String.fromEnvironment('HK_REPO_DIR');
    return devRepo.isEmpty ? saved : saved.copyWith(targetDirectory: devRepo);
  }

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    ref.read(settingsStoreProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
