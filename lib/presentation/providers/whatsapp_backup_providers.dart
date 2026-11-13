import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n/l10n.dart';
import '../../domain/entities/ios_device.dart';
import '../../services/device/contacts_service.dart';
import '../../services/whatsapp/wa_backup_locator.dart';
import '../../services/whatsapp/wa_backup_patcher.dart';
import '../../services/whatsapp/wa_media_index.dart';
import 'whatsapp_android_providers.dart';
import 'core_providers.dart';
import 'device_providers.dart';
import 'whatsapp_providers.dart';

/// Backup folders the user picked ("Choose backup folder…"): a 3uTools or
/// iTunes backup anywhere on disk. Kept for this session.
final waExtraBackupRootsProvider =
    NotifierProvider<ValueController<List<String>>, List<String>>(
      () => ValueController(const []),
    );

/// Every iPhone backup on this computer that holds WhatsApp: HK Tools,
/// Finder / iTunes, 3uTools and the folders the user picked. Newest first.
final waAllBackupsProvider = FutureProvider.autoDispose<List<ContactsSource>>((
  ref,
) {
  final root = p.join(ref.watch(deviceDataDirProvider), 'Backups');
  final extra = ref.watch(waExtraBackupRootsProvider);
  return _findWhatsAppBackups(root, extra);
});

enum WaRestorePhase { idle, preparing, restoring, done, failed }

class WaRestoreState {
  const WaRestoreState({this.phase = WaRestorePhase.idle, this.error});

  final WaRestorePhase phase;
  final String? error;

  bool get running =>
      phase == WaRestorePhase.preparing || phase == WaRestorePhase.restoring;
}

final waBackupRestoreProvider =
    NotifierProvider<WaBackupRestoreController, WaRestoreState>(
      WaBackupRestoreController.new,
    );

/// Puts the WhatsApp chats from an iTunes / Finder / 3uTools / HK Tools
/// backup onto a connected iPhone. Only WhatsApp's data is restored (a
/// WhatsApp-only copy of the backup), the way 3uTools' "Restore WhatsApp"
/// does: photos, apps and settings on the iPhone are left alone.
class WaBackupRestoreController extends Notifier<WaRestoreState> {
  @override
  WaRestoreState build() => const WaRestoreState();

  void reset() {
    if (!state.running) state = const WaRestoreState();
  }

  Future<void> restore(
    ConnectedDevice device,
    String backupDir, {
    bool business = false,
  }) async {
    if (state.running) return;
    void fail(String m) =>
        state = WaRestoreState(phase: WaRestorePhase.failed, error: m);

    final src = BackupContacts.describe(backupDir, origin: '');
    if (src == null) return fail(tr('This folder is not an iPhone backup.'));
    if (src.encrypted) {
      return fail(
        tr(
          'This backup is encrypted, so WhatsApp can\'t be taken from it. Pick an unencrypted backup, or turn off encryption in the app that made it and back up again.',
        ),
      );
    }
    final service = ref.read(deviceServiceProvider);
    if (await _findMyOn(device)) {
      return fail(
        tr(
          'Find My is on. The iPhone refuses restores while it is on: open Settings → your name → Find My → Find My iPhone, turn it off, then try again.',
        ),
      );
    }
    final app = business ? 'WhatsApp Business' : 'WhatsApp';
    if (await _appMissing(
      device,
      business ? 'net.whatsapp.WhatsAppSMB' : 'net.whatsapp.WhatsApp',
    )) {
      return fail(
        trf(
          '{0} is not installed on the iPhone. Install it from the App Store first, then try again. Don\'t register it yet: the restored chats bring the account with them.',
          [app],
        ),
      );
    }

    // 1. A WhatsApp-only copy of the backup.
    state = const WaRestoreState(phase: WaRestorePhase.preparing);
    final outRoot = p.join(ref.read(waWorkDirProvider), 'restore-from-backup');
    final String restoreDir;
    try {
      restoreDir = await _buildRestoreSet(backupDir, outRoot, business);
    } catch (e) {
      return fail('$e');
    }

    // 2. Restore it (the iPhone restarts afterwards).
    state = const WaRestoreState(phase: WaRestorePhase.restoring);
    final job = ref.read(backupJobProvider.notifier);
    await job.run(
      trf('Restoring WhatsApp to {0}', [device.displayName]),
      () => service.startBackupRestore(
        device,
        outRoot,
        sourceUdid: p.basename(restoreDir),
        settings: false,
      ),
    );
    final done = ref.read(backupJobProvider);
    final ok =
        done.status == JobStatus.succeeded ||
        done.log.any((l) => l.contains('Restore Successful'));
    try {
      Directory(outRoot).deleteSync(recursive: true);
    } on FileSystemException {
      // Only a cleanup.
    }
    if (!ok) {
      return fail(
        trf(
          'Restoring to the iPhone failed: {0}. Keep the iPhone unlocked and connected, check that Find My is off, and try again. Nothing on the iPhone was changed.',
          [done.log.isEmpty ? tr('unknown error') : done.log.last],
        ),
      );
    }
    state = const WaRestoreState(phase: WaRestorePhase.done);
  }

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

  Future<bool> _appMissing(ConnectedDevice d, String bundleId) async {
    try {
      final apps = await ref.read(deviceServiceProvider).apps(d);
      return apps.isNotEmpty && !apps.any((a) => a.bundleId == bundleId);
    } on Object {
      return false;
    }
  }
}

/// Which WhatsApp versions a backup holds: `false` = WhatsApp, `true` =
/// WhatsApp Business.
final waBackupFlavorsProvider = FutureProvider.autoDispose
    .family<List<bool>, String>((ref, dir) => _backupFlavors(dir));

// Isolate entry points. They are top-level so their closures capture only
// plain values: a closure written inside a provider or controller also
// captures `ref` / `this`, which can't be sent to another isolate.

Future<List<ContactsSource>> _findWhatsAppBackups(
  String root,
  List<String> extra,
) => Isolate.run(
  () => [
    for (final s in BackupContacts.allBackups(
      appBackupRoot: root,
      extraRoots: extra,
    ))
      if (s.encrypted || WaBackupLocator.hasWhatsApp(s.directory)) s,
  ],
);

Future<String> _buildRestoreSet(
  String backupDir,
  String outRoot,
  bool business,
) {
  final arabic = L10n.arabic; // error messages in the interface language
  return Isolate.run(() {
    L10n.arabic = arabic;
    return WaBackupPatcher.buildRestoreSet(
      backupDir: backupDir,
      outRoot: outRoot,
      business: business,
    );
  });
}

Future<List<bool>> _backupFlavors(String dir) => Isolate.run(
  () => {for (final m in WaBackupLocator.find(dir)) m.isBusiness}.toList(),
);

/// Where the open archive's photos, videos and stickers are on disk: the
/// selected iPhone backup, or the media copied from the Android phone.
final waMediaIndexProvider = FutureProvider.autoDispose<WaMediaIndex?>((ref) {
  switch (ref.watch(waSourceModeProvider)) {
    case WaSourceMode.iphone:
      final dir = ref.watch(waBackupDirProvider);
      return dir == null ? null : _mediaIndex(dir);
    case WaSourceMode.android:
      final dir = ref.watch(waAndroidProvider.select((s) => s.mediaDir));
      return dir == null ? null : WaMediaIndex.fromFolder(dir);
    case WaSourceMode.file:
      return null;
  }
});

Future<WaMediaIndex> _mediaIndex(String dir) =>
    Isolate.run(() => WaMediaIndex.fromBackup(dir));
