import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../services/device/contacts_service.dart';
import '../../services/whatsapp/wa_backup_locator.dart';
import '../../services/whatsapp/wa_crypt.dart';
import '../../services/whatsapp/wa_parser.dart';
import 'core_providers.dart';
import 'device_providers.dart';

/// Inputs the user has chosen on the WhatsApp Archive screen.
class WaInputs {
  const WaInputs({this.dbPath, this.keyPath, this.keyHex});

  /// A `.crypt15`/`.crypt14` backup, or an already-decrypted `msgstore.db`.
  final String? dbPath;

  /// The WhatsApp `key` file (needed only for an encrypted backup).
  final String? keyPath;

  /// A 64-char key pasted instead of a key file.
  final String? keyHex;

  bool get encrypted {
    final path = dbPath;
    if (path == null) return false;
    final ext = p.extension(path).toLowerCase();
    return ext == '.crypt15' || ext == '.crypt14' || ext == '.crypt12';
  }

  bool get ready =>
      dbPath != null &&
      (!encrypted || keyPath != null || (keyHex?.length == 64));

  WaInputs copyWith({
    String? Function()? dbPath,
    String? Function()? keyPath,
    String? Function()? keyHex,
  }) => WaInputs(
    dbPath: dbPath != null ? dbPath() : this.dbPath,
    keyPath: keyPath != null ? keyPath() : this.keyPath,
    keyHex: keyHex != null ? keyHex() : this.keyHex,
  );
}

enum WaSourceMode { file, android, iphone }

final waSourceModeProvider = NotifierProvider<_WaMode, WaSourceMode>(
  _WaMode.new,
);

class _WaMode extends Notifier<WaSourceMode> {
  @override
  // QA: --dart-define=HK_WA_SOURCE=android
  WaSourceMode build() =>
      WaSourceMode.values
          .where((m) => m.name == const String.fromEnvironment('HK_WA_SOURCE'))
          .firstOrNull ??
      WaSourceMode.file;
  void set(WaSourceMode m) => state = m;
}

/// Selected iPhone backup folder (`<root>/<udid>`) to read WhatsApp from.
final waBackupDirProvider = NotifierProvider<_WaBackupDir, String?>(
  _WaBackupDir.new,
);

class _WaBackupDir extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? dir) => state = dir;
}

/// Local backups of [udid] (HK Tools + Finder/iTunes) that contain WhatsApp,
/// newest first.
final waBackupSourcesProvider = FutureProvider.autoDispose
    .family<List<ContactsSource>, String>((ref, udid) async {
      final root = p.join(ref.watch(deviceDataDirProvider), 'Backups');
      final all = BackupContacts.sourcesFor(udid, appBackupRoot: root);
      return [
        for (final s in all)
          if (WaBackupLocator.hasWhatsApp(s.directory)) s,
      ];
    });

final waInputsProvider = NotifierProvider<_WaInputs, WaInputs>(_WaInputs.new);

class _WaInputs extends Notifier<WaInputs> {
  @override
  WaInputs build() => const WaInputs();

  void setDb(String? path) => state = state.copyWith(dbPath: () => path);
  void setKey(String? path) => state = state.copyWith(keyPath: () => path);
  void setKeyHex(String? hex) => state = state.copyWith(keyHex: () => hex);
  void clear() => state = const WaInputs();
}

/// Where a decrypted `msgstore.db` is written (so the user can keep it).
final waWorkDirProvider = Provider<String>(
  (ref) => p.join(ref.watch(appSupportDirProvider), 'whatsapp'),
);

/// Decrypts (if needed) and parses the chosen inputs on a background isolate.
/// `null` until the inputs are ready.
final waArchiveProvider = FutureProvider.autoDispose<WaArchive?>((ref) async {
  if (ref.watch(waSourceModeProvider) == WaSourceMode.iphone) {
    final dir = ref.watch(waBackupDirProvider);
    if (dir == null) return null;
    return Isolate.run(() => WaBackupLocator.read(dir));
  }
  final inputs = ref.watch(waInputsProvider);
  if (!inputs.ready) return null;
  final workDir = ref.watch(waWorkDirProvider);
  final request = _WaLoadRequest(
    dbPath: inputs.dbPath!,
    encrypted: inputs.encrypted,
    keyPath: inputs.keyPath,
    keyHex: inputs.keyHex,
    outDir: workDir,
  );
  return Isolate.run(() => _load(request));
});

final waSelectedChatProvider = NotifierProvider<_WaSelectedChat, String?>(
  _WaSelectedChat.new,
);

class _WaSelectedChat extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? jid) => state = jid;
}

class _WaLoadRequest {
  const _WaLoadRequest({
    required this.dbPath,
    required this.encrypted,
    required this.keyPath,
    required this.keyHex,
    required this.outDir,
  });

  final String dbPath;
  final bool encrypted;
  final String? keyPath;
  final String? keyHex;
  final String outDir;
}

/// Runs in a background isolate.
WaArchive _load(_WaLoadRequest r) {
  var dbPath = r.dbPath;
  if (r.encrypted) {
    final keyBytes = r.keyHex != null
        ? Uint8List.fromList(r.keyHex!.codeUnits)
        : File(r.keyPath!).readAsBytesSync();
    final key = WaBackupKey.fromKeyFile(keyBytes);
    final plain = decryptWhatsAppDb(File(r.dbPath).readAsBytesSync(), key);
    Directory(r.outDir).createSync(recursive: true);
    dbPath = p.join(r.outDir, 'msgstore.db');
    File(dbPath).writeAsBytesSync(plain);
  }
  return WaParser.parseFile(dbPath);
}
