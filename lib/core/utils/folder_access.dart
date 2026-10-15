import 'dart:io';

import 'package:path/path.dart' as p;

/// A download / data folder that can't be used, with a message for the UI.
class FolderAccessException implements Exception {
  FolderAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The external volume a path lives on when that volume is not mounted
/// (`/Volumes/Sonic` on macOS, `E:\` on Windows), else `null`.
String? missingVolume(String path) {
  final abs = p.absolute(path);
  if (Platform.isMacOS) {
    final parts = p.split(abs);
    if (parts.length >= 3 && parts[1] == 'Volumes') {
      final root = p.joinAll(parts.take(3));
      return Directory(root).existsSync() ? null : root;
    }
    return null;
  }
  if (Platform.isWindows) {
    final root = p.rootPrefix(abs);
    if (root.isNotEmpty && !Directory(root).existsSync()) return root;
  }
  return null;
}

/// Readable explanation for a file-system failure while using [path].
String describeFolderError(Object error, String path) {
  final volume = missingVolume(path);
  if (volume != null) {
    return 'The drive $volume is not connected. Connect it, or choose another '
        'download folder in Settings › Downloads.';
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // 13 = EACCES (macOS/Linux), 5 = ERROR_ACCESS_DENIED (Windows),
    // 30 = EROFS (read-only volume).
    if (error is PathAccessException || code == 13 || code == 5) {
      return 'No permission to write to "${error.path ?? path}". Choose another '
          'folder in Settings › Downloads.';
    }
    if (code == 30) {
      return '"$path" is on a read-only drive. Choose another folder in '
          'Settings › Downloads.';
    }
    if (code == 28 || code == 112) {
      return 'The drive holding "$path" is full.';
    }
    return '${error.message}: ${error.path ?? path}';
  }
  return '$error';
}

/// Creates [path] if needed and proves it is writable, or throws
/// [FolderAccessException] with a readable reason.
Future<void> ensureWritableDirectory(String path) async {
  final volume = missingVolume(path);
  if (volume != null) {
    throw FolderAccessException(describeFolderError(Object(), path));
  }
  try {
    final dir = Directory(path);
    await dir.create(recursive: true);
    final probe = File(p.join(dir.path, '.hk_write_test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  } on FileSystemException catch (e) {
    throw FolderAccessException(describeFolderError(e, path));
  }
}
