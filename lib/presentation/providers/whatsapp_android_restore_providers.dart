import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n/l10n.dart';
import '../../services/whatsapp/wa_android.dart';
import '../../services/whatsapp/wa_android_restore.dart';
import '../../services/whatsapp/wa_android_writer.dart';
import '../../services/whatsapp/wa_crypt.dart';
import 'whatsapp_android_providers.dart';
import 'whatsapp_providers.dart';

enum WaAndroidRestorePhase {
  idle,
  preparing,
  reinstalling,
  pushing,
  done,
  failed,
}

class WaAndroidRestoreState {
  const WaAndroidRestoreState({
    this.phase = WaAndroidRestorePhase.idle,
    this.result,
    this.error,
    this.keptPhoneChats = false,
    this.installFailed = false,
  });

  final WaAndroidRestorePhase phase;
  final WaAndroidImportResult? result;
  final String? error;

  /// The phone's own chats were merged in (its backup had been copied).
  final bool keptPhoneChats;

  /// WhatsApp couldn't be installed again: the user installs it from Google
  /// Play (the backup is already on the phone).
  final bool installFailed;

  /// What the user types when WhatsApp asks for the 64-digit key.
  String get keyHex => waZeroKeyHex;

  bool get running =>
      phase == WaAndroidRestorePhase.preparing ||
      phase == WaAndroidRestorePhase.reinstalling ||
      phase == WaAndroidRestorePhase.pushing;
}

final waAndroidRestoreProvider =
    NotifierProvider<WaAndroidRestoreController, WaAndroidRestoreState>(
      WaAndroidRestoreController.new,
    );

/// iPhone backup → Android phone, following Dr.Fone's working method (traced
/// from its logs):
///
///  1. Build the Android backup on this computer: the phone's own chats when
///     its backup was copied in "From Android", plus the iPhone chats;
///     encrypted with the all-zeros key and a header carrying the installed
///     WhatsApp version and the last two digits of the phone number.
///  2. Save the installed WhatsApp app, uninstall it, install the same app
///     again (clean, not activated).
///  3. Copy the backup and the media into WhatsApp's folder and open it.
///  4. The user confirms the number, taps Restore, and types 64 zeros.
class WaAndroidRestoreController extends Notifier<WaAndroidRestoreState> {
  @override
  WaAndroidRestoreState build() => const WaAndroidRestoreState();

  void reset() {
    if (!state.running) state = const WaAndroidRestoreState();
  }

  Future<void> restore({
    required String iphoneBackupDir,
    required String phoneNumber,
  }) async {
    if (state.running) return;
    final flow = ref.read(waAndroidProvider);
    final serial = flow.serial;
    final flavor = flow.flavor;
    void fail(String m) => state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.failed,
      error: m,
    );
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      return fail(
        tr(
          'Enter the phone number WhatsApp is registered with on the Android phone, with the country code.',
        ),
      );
    }
    if (serial == null) {
      return fail(tr('Connect the Android phone with USB debugging on.'));
    }
    final client = ref.read(waAndroidClientProvider);
    final work = p.join(ref.read(waWorkDirProvider), 'to-android');

    // 0. WhatsApp must be on the phone: its own app is reinstalled clean.
    final String? version;
    try {
      version = await client.installedVersion(serial, flavor);
    } catch (e) {
      return fail('$e');
    }
    if (version == null) {
      return fail(
        trf(
          '{0} is not installed on the Android phone. Install it from Google Play, register it with your number, then try again.',
          [flavor.label],
        ),
      );
    }

    // The phone's own chats, when its backup was copied in "From Android".
    final inputs = ref.read(waInputsProvider);
    final keep =
        flow.step == WaAndroidStep.done &&
        flow.keyHex != null &&
        inputs.dbPath != null &&
        File(inputs.dbPath!).existsSync();

    // 1. Build the backup.
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.preparing,
      keptPhoneChats: keep,
    );
    final WaAndroidRestorePackage pkg;
    try {
      pkg = await _prepareInIsolate(
        iphoneBackupDir: iphoneBackupDir,
        outDir: p.join(work, 'out'),
        appVersion: version,
        jidSuffix: digits.substring(digits.length - 2),
        baseCrypt15: keep ? inputs.dbPath : null,
        baseKey: keep ? flow.keyHex : null,
        business: flavor == WaFlavor.business,
      );
    } catch (e) {
      return fail('$e');
    }

    // 2. Reinstall WhatsApp clean (same version).
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.reinstalling,
      result: pkg.result,
      keptPhoneChats: keep,
    );
    var installFailed = false;
    try {
      final apks = await client.saveApks(serial, flavor, p.join(work, 'apk'));
      await client.uninstall(serial, flavor);
      try {
        await client.install(serial, apks);
      } on AdbException {
        installFailed = true;
      }
    } catch (e) {
      return fail('$e');
    }

    // 3. Backup and media into WhatsApp's folder.
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.pushing,
      result: pkg.result,
      keptPhoneChats: keep,
      installFailed: installFailed,
    );
    final root = flavor == WaFlavor.business
        ? '/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business'
        : '/sdcard/Android/media/com.whatsapp/WhatsApp';
    try {
      await client.push(
        serial,
        pkg.crypt15Path,
        '$root/Databases/msgstore.db.crypt15',
        what: 'Copying the backup',
      );
      if (pkg.mediaDir != null) {
        await client.push(
          serial,
          pkg.mediaDir!,
          '$root/Media',
          what: 'Copying media',
        );
      }
      if (!installFailed) await client.launch(serial, flavor);
    } catch (e) {
      return fail('$e');
    }

    try {
      Directory(work).deleteSync(recursive: true);
    } on FileSystemException {
      // Only a cleanup.
    }
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.done,
      result: pkg.result,
      keptPhoneChats: keep,
      installFailed: installFailed,
    );
  }
}

/// Top-level so the isolate closure captures nothing but its arguments.
Future<WaAndroidRestorePackage> _prepareInIsolate({
  required String iphoneBackupDir,
  required String outDir,
  required String appVersion,
  required String jidSuffix,
  required String? baseCrypt15,
  required String? baseKey,
  required bool business,
}) {
  final arabic = L10n.arabic;
  return Isolate.run(() {
    L10n.arabic = arabic;
    return WaAndroidRestore.prepare(
      iphoneBackupDir: iphoneBackupDir,
      outDir: outDir,
      appVersion: appVersion,
      jidSuffix: jidSuffix,
      baseCrypt15Path: baseCrypt15,
      baseKeyHex: baseKey,
      business: business,
    );
  });
}
