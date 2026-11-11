import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';

import '../../services/setup/dependency_manager.dart';
import 'device_providers.dart';

final dependencyManagerProvider = Provider<DependencyManager>(
  (ref) => DependencyManager(tools: ref.watch(deviceToolchainProvider)),
);

/// Current state of every dependency (re-checked after installs).
final dependencyStatusProvider = FutureProvider<List<DependencyStatus>>(
  (ref) => ref.watch(dependencyManagerProvider).checkAll(),
);

sealed class InstallState {
  const InstallState();
}

class Installing extends InstallState {
  const Installing(this.status, this.fraction);

  final String status;
  final double? fraction;
}

class InstallDone extends InstallState {
  const InstallDone();
}

class InstallFailed extends InstallState {
  const InstallFailed(this.message);

  final String message;
}

class SetupController extends Notifier<Map<Dependency, InstallState>> {
  @override
  Map<Dependency, InstallState> build() => const {};

  bool get busy => state.values.any((s) => s is Installing);

  /// Installs [deps] one after another, in declaration order, then
  /// re-checks everything.
  Future<void> installAll(Iterable<Dependency> deps) async {
    final ordered = Dependency.values.where(deps.contains).toList();
    final manager = ref.read(dependencyManagerProvider);
    for (final d in ordered) {
      state = {...state, d: Installing(tr('Starting…'), null)};
      try {
        await manager.install(
          d,
          onProgress: (status, fraction) =>
              state = {...state, d: Installing(status, fraction)},
        );
        state = {...state, d: const InstallDone()};
      } on Object catch (e) {
        state = {...state, d: InstallFailed('$e')};
      }
    }
    ref.invalidate(deviceToolchainProvider);
    ref.invalidate(dependencyStatusProvider);
  }

  void reset() => state = const {};
}

final setupProvider =
    NotifierProvider<SetupController, Map<Dependency, InstallState>>(
      SetupController.new,
    );
