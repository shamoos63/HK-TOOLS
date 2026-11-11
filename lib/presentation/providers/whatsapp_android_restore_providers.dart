import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n/l10n.dart';
import '../../services/whatsapp/wa_android.dart';
import '../../services/whatsapp/wa_android_restore.dart';
import '../../services/whatsapp/wa_android_writer.dart';
import 'whatsapp_android_providers.dart';
import 'whatsapp_providers.dart';

enum WaAndroidRestorePhase { idle, preparing, pushing, resetting, done, failed }

class WaAndroidRestoreState {
  const WaAndroidRestoreState({
    this.phase = WaAndroidRestorePhase.idle,
    this.result,
    this.error,
    this.keyHex,
  });

  final WaAndroidRestorePhase phase;
  final WaAndroidImportResult? result;
  final String? error;

  /// The key WhatsApp will ask for when restoring.
  final String? keyHex;

  bool get running =>
      phase == WaAndroidRestorePhase.preparing ||
      phase == WaAndroidRestorePhase.pushing ||
      phase == WaAndroidRestorePhase.resetting;
}

final waAndroidRestoreProvider =
    NotifierProvider<WaAndroidRestoreController, WaAndroidRestoreState>(
      WaAndroidRestoreController.new,
    );

/// iPhone backup → Android phone.
///
/// Needs the Android side ready first (the "From Android" steps): the phone's
/// own encrypted backup and its 64-digit key, copied to this computer. That
/// backup is the template: the iPhone chats are merged into it, it is
/// encrypted again with the same key, and put back on the phone with the
/// media. WhatsApp on the phone is then reset, and restores the backup during
/// setup when the user enters the key — the same route Dr.Fone takes.
class WaAndroidRestoreController extends Notifier<WaAndroidRestoreState> {
  @override
  WaAndroidRestoreState build() => const WaAndroidRestoreState();

  void reset() {
    if (!state.running) state = const WaAndroidRestoreState();
  }

  Future<void> restore({required String iphoneBackupDir}) async {
    if (state.running) return;
    final flow = ref.read(waAndroidProvider);
    final inputs = ref.read(waInputsProvider);
    final serial = flow.serial;
    final backup = flow.backup;
    final key = flow.keyHex;
    final crypt = inputs.dbPath;
    void fail(String m) => state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.failed,
      error: m,
    );
    if (serial == null ||
        backup == null ||
        key == null ||
        crypt == null ||
        flow.step != WaAndroidStep.done) {
      return fail(
        tr(
          'Prepare the Android phone first: in "From Android", read the 64-digit key and copy the phone\'s backup.',
        ),
      );
    }
    final client = ref.read(waAndroidClientProvider);
    final business = flow.flavor == WaFlavor.business;
    final root = WaAndroidClient.whatsAppRootOf(backup);
    final outDir = p.join(ref.read(waWorkDirProvider), 'to-android');

    // 1. Merge and re-encrypt on this computer.
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.preparing,
      keyHex: key,
    );
    final WaAndroidRestorePackage pkg;
    try {
      pkg = await _prepareInIsolate(
        iphoneBackupDir,
        crypt,
        key,
        outDir,
        business,
      );
    } catch (e) {
      return fail('$e');
    }

    try {
      // 2. Put the backup and media on the phone.
      state = WaAndroidRestoreState(
        phase: WaAndroidRestorePhase.pushing,
        result: pkg.result,
        keyHex: key,
      );
      Future<void> pushAll() async {
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
      }

      await pushAll();

      // 3. Reset WhatsApp so it offers to restore on next launch.
      state = WaAndroidRestoreState(
        phase: WaAndroidRestorePhase.resetting,
        result: pkg.result,
        keyHex: key,
      );
      await client.clearApp(serial, flow.flavor);
      // Some Android versions clear the app's media folder too: put
      // everything back if it went (including the phone's own media, when it
      // was copied in the "From Android" steps).
      if (!await client.exists(serial, '$root/Databases/msgstore.db.crypt15')) {
        final own = flow.mediaDir;
        if (own != null && Directory(p.join(own, 'Media')).existsSync()) {
          await client.push(
            serial,
            p.join(own, 'Media'),
            '$root/Media',
            what: 'Copying media',
          );
        }
        await pushAll();
      }
      await client.launch(serial, flow.flavor);
    } catch (e) {
      return fail('$e');
    }

    try {
      Directory(outDir).deleteSync(recursive: true);
    } on FileSystemException {
      // Only a cleanup.
    }
    state = WaAndroidRestoreState(
      phase: WaAndroidRestorePhase.done,
      result: pkg.result,
      keyHex: key,
    );
  }
}

/// Top-level so the isolate closure captures nothing but its arguments.
Future<WaAndroidRestorePackage> _prepareInIsolate(
  String iphoneBackupDir,
  String crypt15,
  String key,
  String outDir,
  bool business,
) {
  final arabic = L10n.arabic;
  return Isolate.run(() {
    L10n.arabic = arabic;
    return WaAndroidRestore.prepare(
      iphoneBackupDir: iphoneBackupDir,
      androidCrypt15Path: crypt15,
      keyHex: key,
      outDir: outDir,
      business: business,
    );
  });
}
