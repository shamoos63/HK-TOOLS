import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../services/whatsapp/wa_android.dart';
import 'device_providers.dart';
import 'whatsapp_providers.dart';
import '../../core/l10n/l10n.dart';

final waAndroidClientProvider = Provider<WaAndroidClient>(
  (ref) => WaAndroidClient(
    customDirectory: ref.watch(deviceToolchainProvider).customDirectory,
  ),
);

/// Connected Android phones, refreshed every few seconds while the WhatsApp
/// screen is showing the Android source.
final androidDevicesProvider = StreamProvider.autoDispose<List<AndroidDevice>>((
  ref,
) async* {
  final client = ref.watch(waAndroidClientProvider);
  while (true) {
    yield await client.devices();
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});

enum WaAndroidStep { key, backup, pulling, done }

class WaAndroidState {
  const WaAndroidState({
    this.serial,
    this.flavor = WaFlavor.whatsapp,
    this.step = WaAndroidStep.key,
    this.keyHex,
    this.keySetAt,
    this.backup,
    this.busy = false,
    this.status,
    this.error,
    this.includeMedia = true,
    this.mediaDir,
    this.mediaProgress,
  });

  final String? serial;
  final WaFlavor flavor;
  final WaAndroidStep step;

  /// The 64-digit key, read from the phone's screen or typed by the user.
  final String? keyHex;

  /// When the key was captured; only backups written after it use that key.
  final DateTime? keySetAt;
  final AndroidWaBackup? backup;
  final bool busy;
  final String? status;
  final String? error;

  /// Also copy photos, videos, voice notes and documents from the phone.
  final bool includeMedia;

  /// Local folder holding the copied `Media/` folder, once copied.
  final String? mediaDir;

  /// 0–1 while media is being copied.
  final double? mediaProgress;

  WaAndroidState copyWith({
    String? Function()? serial,
    WaFlavor? flavor,
    WaAndroidStep? step,
    String? Function()? keyHex,
    DateTime? Function()? keySetAt,
    AndroidWaBackup? Function()? backup,
    bool? busy,
    String? Function()? status,
    String? Function()? error,
    bool? includeMedia,
    String? Function()? mediaDir,
    double? Function()? mediaProgress,
  }) => WaAndroidState(
    serial: serial != null ? serial() : this.serial,
    flavor: flavor ?? this.flavor,
    step: step ?? this.step,
    keyHex: keyHex != null ? keyHex() : this.keyHex,
    keySetAt: keySetAt != null ? keySetAt() : this.keySetAt,
    backup: backup != null ? backup() : this.backup,
    busy: busy ?? this.busy,
    status: status != null ? status() : this.status,
    error: error != null ? error() : this.error,
    includeMedia: includeMedia ?? this.includeMedia,
    mediaDir: mediaDir != null ? mediaDir() : this.mediaDir,
    mediaProgress: mediaProgress != null ? mediaProgress() : this.mediaProgress,
  );
}

final waAndroidProvider = NotifierProvider<WaAndroidFlow, WaAndroidState>(
  WaAndroidFlow.new,
);

/// Drives the Android acquisition: key → backup → pull → hand the file and key
/// to the existing decrypt/parse pipeline ([waInputsProvider]).
class WaAndroidFlow extends Notifier<WaAndroidState> {
  int _generation = 0;

  @override
  WaAndroidState build() => const WaAndroidState();

  WaAndroidClient get _client => ref.read(waAndroidClientProvider);

  void selectDevice(String? serial) {
    if (serial == state.serial) return;
    _generation++;
    state = WaAndroidState(
      serial: serial,
      flavor: state.flavor,
      includeMedia: state.includeMedia,
    );
  }

  void setFlavor(WaFlavor flavor) => state = state.copyWith(flavor: flavor);

  void setIncludeMedia(bool v) => state = state.copyWith(includeMedia: v);

  void reset() {
    _generation++;
    state = WaAndroidState(
      serial: state.serial,
      flavor: state.flavor,
      includeMedia: state.includeMedia,
    );
  }

  Future<void> _guard(String status, Future<void> Function() body) async {
    state = state.copyWith(busy: true, status: () => status, error: () => null);
    try {
      await body();
    } on _Cancelled {
      // Nothing to report.
    } catch (e) {
      state = state.copyWith(error: () => '$e');
    } finally {
      state = state.copyWith(busy: false, status: () => null);
    }
  }

  Future<void> openWhatsApp() =>
      _guard(tr('Opening WhatsApp on the phone…'), () {
        return _client.openWhatsApp(state.serial!, state.flavor);
      });

  /// Reads the key the phone is currently showing.
  Future<void> readKey() =>
      _guard(tr('Reading the key from the phone…'), () async {
        final key = await _client.readKeyFromScreen(state.serial!);
        if (key == null) {
          throw AdbException(
            tr(
              'No 64-digit key is visible on the phone. Leave WhatsApp on the "Your 64-digit encryption key" page, unlocked, and try again. You can also type the key in below.',
            ),
          );
        }
        _acceptKey(key);
      });

  /// A key the user typed (spaces allowed).
  bool setKeyManually(String text) {
    final key = text.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) return false;
    _acceptKey(key, manual: true);
    return true;
  }

  void _acceptKey(String key, {bool manual = false}) {
    state = state.copyWith(
      keyHex: () => key,
      // A typed key may be for a backup that already exists; a key read off
      // the setup screen is new, so only later backups use it. Allow a minute
      // of clock skew between the phone and this computer.
      keySetAt: () =>
          manual ? null : DateTime.now().subtract(const Duration(minutes: 1)),
      step: WaAndroidStep.backup,
      error: () => null,
    );
  }

  /// Waits for the user to tap "Back up" in WhatsApp, then pulls the file.
  Future<void> waitAndPull() async {
    final gen = _generation;
    await _guard(tr('Waiting for WhatsApp to finish the backup…'), () async {
      final serial = state.serial!;
      final since = state.keySetAt;
      final AndroidWaBackup backup;
      if (since == null) {
        final all = await _client.findBackups(serial, flavors: [state.flavor]);
        backup =
            all.where((b) => b.isLatest).firstOrNull ??
            all.firstOrNull ??
            (throw AdbException(
              tr(
                'No WhatsApp backup on the phone yet. In WhatsApp open Settings → Chats → Chat backup and tap "Back up".',
              ),
            ));
      } else {
        try {
          backup = await _client.waitForNewBackup(
            serial,
            since: since,
            flavors: [state.flavor],
            cancelled: () => gen != _generation,
          );
        } catch (_) {
          // Cancelled by the user: not an error worth showing.
          if (gen != _generation) throw _Cancelled();
          rethrow;
        }
      }
      if (gen != _generation) return;
      await _pull(serial, backup);
    });
  }

  Future<void> _pull(String serial, AndroidWaBackup backup) async {
    state = state.copyWith(
      backup: () => backup,
      step: WaAndroidStep.pulling,
      status: () => trf('Copying {0} from the phone…', [backup.fileName]),
    );
    final dir = p.join(
      ref.read(waWorkDirProvider),
      'android',
      serial.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
    );
    try {
      final local = await _client.pull(serial, backup, dir);
      // Keep the key with the backup so it can be decrypted again later.
      final key = state.keyHex;
      if (key != null) {
        File(p.join(dir, 'backup-key.txt')).writeAsStringSync('$key\n');
      }
      final inputs = ref.read(waInputsProvider.notifier);
      inputs.clear();
      inputs.setDb(local);
      inputs.setKeyHex(state.keyHex);
      ref.read(waSelectedChatProvider.notifier).set(null);
      if (state.includeMedia) await _pullMedia(serial, backup, dir);
      state = state.copyWith(step: WaAndroidStep.done);
    } catch (_) {
      state = state.copyWith(step: WaAndroidStep.backup);
      rethrow;
    }
  }

  Future<void> _pullMedia(
    String serial,
    AndroidWaBackup backup,
    String dir,
  ) async {
    state = state.copyWith(
      mediaProgress: () => 0,
      status: () => tr('Copying photos, videos and voice notes…'),
    );
    try {
      await _client.pullMedia(
        serial,
        backup,
        dir,
        onProgress: (f, folder) => state = state.copyWith(
          mediaProgress: () => f,
          status: () => folder.isEmpty
              ? tr('Media copied.')
              : trf('Copying media: {0} ({1}%)…', [folder, (f * 100).round()]),
        ),
      );
      state = state.copyWith(mediaDir: () => dir);
    } catch (e) {
      // The chats are still usable; they just move without media files.
      state = state.copyWith(
        mediaDir: () => null,
        error: () => trf(
          'Media could not be copied ({0}). Chats will move with labels instead of photos and videos.',
          [e],
        ),
      );
    } finally {
      state = state.copyWith(mediaProgress: () => null);
    }
  }

  /// Stops waiting for a backup.
  void cancelWait() {
    _generation++;
    state = state.copyWith(busy: false, status: () => null);
  }
}

class _Cancelled implements Exception {}
