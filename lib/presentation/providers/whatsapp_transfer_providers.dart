import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/ios_device.dart';
import '../../services/whatsapp/wa_backup_patcher.dart';
import '../../services/whatsapp/wa_ios_writer.dart';
import '../../services/whatsapp/wa_parser.dart';
import 'device_providers.dart';
import 'whatsapp_providers.dart';
import '../../core/l10n/l10n.dart';

enum WaTransferPhase { idle, backingUp, writing, restoring, done, failed }

class WaTransferState {
  const WaTransferState({
    this.phase = WaTransferPhase.idle,
    this.udid,
    this.result,
    this.error,
  });

  final WaTransferPhase phase;

  /// The iPhone the transfer is for.
  final String? udid;
  final WaIosImportResult? result;
  final String? error;

  bool get running =>
      phase == WaTransferPhase.backingUp ||
      phase == WaTransferPhase.writing ||
      phase == WaTransferPhase.restoring;
}

final waTransferProvider =
    NotifierProvider<WaTransferController, WaTransferState>(
      WaTransferController.new,
    );

/// Android → iPhone: back up the iPhone, merge the Android chats into its
/// WhatsApp database inside that backup, restore the backup to the iPhone.
class WaTransferController extends Notifier<WaTransferState> {
  @override
  WaTransferState build() => const WaTransferState();

  String get _backupRoot => p.join(ref.read(deviceDataDirProvider), 'Backups');

  String _undoDir(String udid) =>
      p.join(ref.read(waWorkDirProvider), 'transfer-original', udid);

  void reset() {
    if (!state.running) state = const WaTransferState();
  }

  Future<void> transfer(
    ConnectedDevice device,
    WaArchive archive, {
    bool business = false,
    String? mediaRoot,
  }) async {
    if (state.running) return;
    final udid = device.udid!;
    void fail(String message) => state = WaTransferState(
      phase: WaTransferPhase.failed,
      udid: udid,
      error: message,
    );

    // 0. Checks the commercial tools also run before touching anything.
    final service = ref.read(deviceServiceProvider);
    if (await service.backupWillEncrypt(device) ?? false) {
      return fail(
        tr(
          'Backups of this iPhone are encrypted, and WhatsApp can only be written into an unencrypted backup. Turn encryption off in Devices → Backup (you need the backup password), then try again.',
        ),
      );
    }
    if (await _findMyOn(device)) {
      return fail(
        tr(
          'Find My is on. The iPhone refuses restores while it is on: open Settings → your name → Find My → Find My iPhone, turn it off, then try again.',
        ),
      );
    }
    final bundle = business
        ? 'net.whatsapp.WhatsAppSMB'
        : 'net.whatsapp.WhatsApp';
    if (await _appMissing(device, bundle)) {
      return fail(
        trf(
          '{0} is not installed on the iPhone. Install it from the App Store, register with the same phone number as the Android phone, then try again.',
          [business ? 'WhatsApp Business' : 'WhatsApp'],
        ),
      );
    }

    // 1. Fresh backup of the iPhone: it supplies WhatsApp's own database (the
    //    exact schema of the installed version) and file records.
    state = WaTransferState(phase: WaTransferPhase.backingUp, udid: udid);
    final job = ref.read(backupJobProvider.notifier);
    // Same "<device name> <date>" folder as backups made from Devices, so it
    // also shows up (and can be restored) in the backup lists.
    final backupRoot = namedBackupDir(_backupRoot, device);
    await job.run(
      trf('Backup of {0}', [device.displayName]),
      () => service.startBackup(device, backupRoot),
    );
    final backed = ref.read(backupJobProvider);
    if (backed.status != JobStatus.succeeded) {
      return fail(
        trf('The iPhone backup failed: {0}', [
          backed.log.isEmpty ? tr('unknown error') : backed.log.last,
        ]),
      );
    }

    // 2. Build a WhatsApp-only backup from it and merge the chats into that.
    //    The full backup stays untouched.
    state = WaTransferState(phase: WaTransferPhase.writing, udid: udid);
    final backupDir = p.join(backupRoot, udid);
    final restoreRoot = p.join(ref.read(waWorkDirProvider), 'restore');
    final WaIosImportResult result;
    try {
      result = await _patchInIsolate(
        backupDir,
        restoreRoot,
        archive,
        _undoDir(udid),
        business,
        mediaRoot,
      );
    } catch (e) {
      return fail('$e');
    }

    // 3. Restore only WhatsApp's data to the iPhone (it restarts afterwards).
    //    Nothing else on the phone is replaced or removed.
    state = WaTransferState(
      phase: WaTransferPhase.restoring,
      udid: udid,
      result: result,
    );
    await job.run(
      trf('Restoring WhatsApp to {0}', [device.displayName]),
      () => service.startBackupRestore(
        device,
        restoreRoot,
        sourceUdid: udid,
        settings: false,
      ),
    );
    final restored = ref.read(backupJobProvider);
    // The iPhone often drops the connection as it starts rebooting, so a
    // reported success counts even if the tool then exits with an error.
    final ok =
        restored.status == JobStatus.succeeded ||
        restored.log.any((l) => l.contains('Restore Successful'));
    if (!ok) {
      return fail(
        trf(
          'Restoring to the iPhone failed: {0}. Keep the iPhone unlocked and connected, check that Find My is off, and try again. Nothing on the iPhone was changed.',
          [restored.log.isEmpty ? tr('unknown error') : restored.log.last],
        ),
      );
    }
    try {
      Directory(restoreRoot).deleteSync(recursive: true);
    } on FileSystemException {
      // Only a cleanup.
    }
    state = WaTransferState(
      phase: WaTransferPhase.done,
      udid: udid,
      result: result,
    );
  }

  /// Find My blocks restores. `false` when it can't be read.
  Future<bool> _findMyOn(ConnectedDevice d) async {
    try {
      final v = (await ref
          .read(deviceServiceProvider)
          .domain(d, 'com.apple.fmip'))['IsAssociated'];
      return v == true || v == 1;
    } on Object {
      return false;
    }
  }

  /// `true` only when the app list was read and [bundleId] is not in it.
  Future<bool> _appMissing(ConnectedDevice d, String bundleId) async {
    try {
      final apps = await ref.read(deviceServiceProvider).apps(d);
      return apps.isNotEmpty && !apps.any((a) => a.bundleId == bundleId);
    } on Object {
      return false;
    }
  }
}

/// Top-level so the isolate closure captures nothing but its arguments.
Future<WaIosImportResult> _patchInIsolate(
  String backupDir,
  String restoreRoot,
  WaArchive archive,
  String undoDir,
  bool business,
  String? mediaRoot,
) {
  // The isolate starts with default statics; carry the interface language
  // over so error messages come back translated.
  final arabic = L10n.arabic;
  return Isolate.run(() {
    L10n.arabic = arabic;
    final set = WaBackupPatcher.buildRestoreSet(
      backupDir: backupDir,
      outRoot: restoreRoot,
      business: business,
    );
    final undo = Directory(undoDir);
    if (undo.existsSync()) undo.deleteSync(recursive: true);
    return WaBackupPatcher.transfer(
      backupDir: set,
      archive: archive,
      undoDir: undoDir,
      business: business,
      mediaRoot: mediaRoot,
    );
  });
}
