import 'dart:io';

import 'package:path/path.dart' as p;

/// Physical-file identity: paths with the same [id] are hardlinks of one file.
class FileIdentity {
  const FileIdentity(this.id, this.linkCount);

  final String id;
  final int linkCount;
}

class HardlinkException implements Exception {
  HardlinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Hardlink detection and creation via the OS tools (`stat`/`ln` on macOS,
/// `fsutil`/`mklink /H` on Windows — neither needs elevation for hardlinks).
class Hardlinks {
  /// Identities for many files in as few process launches as possible.
  static Future<Map<String, FileIdentity>> identify(List<String> paths) async {
    final out = <String, FileIdentity>{};
    if (paths.isEmpty) return out;
    try {
      if (Platform.isWindows) {
        for (final path in paths) {
          out[path] = await _windowsIdentity(path);
        }
      } else {
        // `stat -f` (BSD/macOS) prints "<dev>:<inode> <nlink>" per file.
        const batch = 200;
        for (var i = 0; i < paths.length; i += batch) {
          final slice = paths.sublist(
            i,
            i + batch > paths.length ? paths.length : i + batch,
          );
          final args = Platform.isMacOS
              ? ['-f', '%d:%i %l', ...slice]
              : ['-c', '%d:%i %h', ...slice];
          final r = await Process.run('stat', args);
          final lines = (r.stdout as String).trim().split('\n');
          for (var j = 0; j < slice.length && j < lines.length; j++) {
            final parts = lines[j].trim().split(' ');
            if (parts.length == 2) {
              out[slice[j]] = FileIdentity(
                parts[0],
                int.tryParse(parts[1]) ?? 1,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fall through: unidentified paths are treated as distinct files.
    }
    for (final path in paths) {
      out.putIfAbsent(path, () => FileIdentity('path:$path', 1));
    }
    return out;
  }

  static Future<FileIdentity> _windowsIdentity(String path) async {
    // Lists every link of the file (drive-relative); identical for all links.
    final r = await Process.run('fsutil', ['hardlink', 'list', path]);
    final links =
        (r.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim().toLowerCase())
            .where((l) => l.isNotEmpty)
            .toList()
          ..sort();
    if (r.exitCode != 0 || links.isEmpty) return FileIdentity('path:$path', 1);
    final drive = p.rootPrefix(path).toLowerCase();
    return FileIdentity('$drive${links.first}', links.length);
  }

  /// Creates [linkPath] as a hardlink to [target] (same volume only).
  static Future<void> create({
    required String target,
    required String linkPath,
  }) async {
    await Directory(p.dirname(linkPath)).create(recursive: true);
    final ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run('cmd', ['/c', 'mklink', '/H', linkPath, target]);
    } else {
      r = await Process.run('ln', [target, linkPath]);
    }
    if (r.exitCode != 0) {
      final msg = '${r.stderr}'.trim().isNotEmpty
          ? '${r.stderr}'.trim()
          : '${r.stdout}'.trim();
      throw HardlinkException('Could not link ${p.basename(linkPath)}: $msg');
    }
  }

  /// Replaces [duplicate] with a hardlink to [keeper] atomically enough that a
  /// failure leaves the original duplicate in place.
  static Future<void> replaceWithLink({
    required String keeper,
    required String duplicate,
  }) async {
    final backup = '$duplicate.hkreclaim';
    await File(duplicate).rename(backup);
    try {
      await create(target: keeper, linkPath: duplicate);
    } catch (_) {
      await File(backup).rename(duplicate);
      rethrow;
    }
    await File(backup).delete();
  }
}
