import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/cache/scan_cache.dart';
import 'hardlinks.dart';
import 'ipsw_manifest_reader.dart';

/// The repository folder itself cannot be listed.
class RepositoryAccessException implements Exception {
  RepositoryAccessException(this.folder);

  final String folder;

  @override
  String toString() => 'No permission to read $folder';
}

/// One `.ipsw` path found on disk.
class ScanEntry {
  const ScanEntry({
    required this.path,
    required this.size,
    required this.modified,
    required this.identity,
    this.manifest,
    this.manifestError,
    this.sha1,
  });

  final String path;
  final int size;
  final DateTime modified;
  final FileIdentity identity;
  final IpswManifest? manifest;
  final String? manifestError;
  final String? sha1;

  String get fileName => p.basename(path);

  ScanEntry withSha1(String sha1) => ScanEntry(
    path: path,
    size: size,
    modified: modified,
    identity: identity,
    manifest: manifest,
    manifestError: manifestError,
    sha1: sha1,
  );
}

class ScanProgress {
  const ScanProgress({
    required this.done,
    required this.total,
    this.currentPath,
    this.entries,
    this.skipped = const [],
  });

  /// Folders / files that could not be read (permissions) and were skipped.
  final List<String> skipped;

  final int done;
  final int total;
  final String? currentPath;

  /// Set on the final event.
  final List<ScanEntry>? entries;

  bool get isComplete => entries != null;
}

/// Finds `.ipsw` files and identifies each from its `BuildManifest.plist`.
/// Results are cached by path + size + mtime, so rescans only stat files.
class RepositoryScanner {
  RepositoryScanner(this._cache);

  final ScanCache _cache;

  /// OS bookkeeping folders that are never readable / never hold firmware.
  static const _systemFolders = {
    '.trashes',
    '.trash',
    '.spotlight-v100',
    '.fseventsd',
    '.documentrevisions-v100',
    '.temporaryitems',
    r'$recycle.bin',
    'system volume information',
  };

  Stream<ScanProgress> scan(String folder, {bool recursive = true}) async* {
    final dir = Directory(folder);
    if (!await dir.exists()) {
      yield const ScanProgress(done: 0, total: 0, entries: []);
      return;
    }

    final files = <File>[];
    final skipped = <String>[];
    await _collect(dir, files, skipped, recursive: recursive);
    if (skipped.contains(dir.path)) {
      throw RepositoryAccessException(folder);
    }
    yield ScanProgress(done: 0, total: files.length, skipped: skipped);

    final raw = <(File, FileStat, ScanCacheEntry)>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final FileStat stat;
      try {
        stat = await f.stat();
        if (stat.type == FileSystemEntityType.notFound) continue;
      } on FileSystemException {
        skipped.add(f.path);
        continue;
      }
      final mtime = stat.modified.millisecondsSinceEpoch;
      var info = _cache.get(f.path, size: stat.size, modifiedMs: mtime);
      if (info == null) {
        IpswManifest? manifest;
        String? error;
        var cacheable = true;
        try {
          manifest = await IpswManifestReader.readFile(f.path);
        } on ManifestReadException catch (e) {
          error = e.message;
        } on FileSystemException catch (e) {
          // Typically "Operation not permitted": retry on the next scan
          // (e.g. after access is granted) instead of caching the failure.
          error = 'Cannot read file: ${e.osError?.message ?? e.message}';
          cacheable = false;
          skipped.add(f.path);
        } catch (e) {
          error = '$e';
        }
        info = ScanCacheEntry(
          size: stat.size,
          modifiedMs: mtime,
          manifest: manifest,
          manifestError: error,
        );
        if (cacheable) await _cache.put(f.path, info);
      }
      raw.add((f, stat, info));
      yield ScanProgress(
        done: i + 1,
        total: files.length,
        currentPath: f.path,
        skipped: skipped,
      );
    }

    final identities = await Hardlinks.identify([
      for (final (f, _, _) in raw) f.path,
    ]);
    // Trailing separator so "/IPSW" never prunes "/IPSW2"; files inside
    // skipped folders keep their cache entries.
    final prefix = folder.endsWith(p.separator)
        ? folder
        : '$folder${p.separator}';
    await _cache.prune(
      prefix,
      {for (final f in files) f.path},
      keepUnder: [for (final s in skipped) '$s${p.separator}'],
    );

    yield ScanProgress(
      done: files.length,
      total: files.length,
      skipped: skipped,
      entries: [
        for (final (f, stat, info) in raw)
          ScanEntry(
            path: f.path,
            size: stat.size,
            modified: stat.modified,
            identity: identities[f.path]!,
            manifest: info.manifest,
            manifestError: info.manifestError,
            sha1: info.sha1,
          ),
      ],
    );
  }

  /// Iterative walk that survives unreadable folders: `Directory.list` with
  /// `recursive: true` aborts the whole listing on the first
  /// PathAccessException, so each folder is listed on its own.
  static Future<void> _collect(
    Directory root,
    List<File> files,
    List<String> skipped, {
    required bool recursive,
  }) async {
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      try {
        await for (final e in dir.list(followLinks: false)) {
          final name = p.basename(e.path).toLowerCase();
          if (e is File && name.endsWith('.ipsw')) {
            files.add(e);
          } else if (e is Directory &&
              recursive &&
              !_systemFolders.contains(name)) {
            pending.add(e);
          }
        }
      } on FileSystemException {
        skipped.add(dir.path);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
  }

  /// Records a computed SHA1 so it survives rescans.
  Future<void> rememberSha1(ScanEntry entry, String sha1) => _cache.put(
    entry.path,
    ScanCacheEntry(
      size: entry.size,
      modifiedMs: entry.modified.millisecondsSinceEpoch,
      manifest: entry.manifest,
      manifestError: entry.manifestError,
      sha1: sha1,
    ),
  );
}
