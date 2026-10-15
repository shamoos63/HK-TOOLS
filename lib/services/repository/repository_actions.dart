import 'dart:io';

import 'package:path/path.dart' as p;

import 'hardlinks.dart';
import 'repository_inventory.dart';

/// File-system operations on the repository folder.
class RepositoryActions {
  /// Creates `<folder>/By Device/<identifier>_<version>_<build>_Restore.ipsw`
  /// hardlinks to [sourcePath] for every device; existing names are skipped.
  /// Costs no extra disk space. Returns the number of links created.
  static Future<int> createDeviceLinks({
    required String folder,
    required String sourcePath,
    required List<String> deviceIdentifiers,
    required String version,
    required String buildId,
  }) async {
    var created = 0;
    for (final id in deviceIdentifiers.toSet()) {
      final link = p.join(
        folder,
        deviceLinksFolder,
        deviceLinkName(id, version, buildId),
      );
      if (p.equals(link, sourcePath) || await File(link).exists()) continue;
      await Hardlinks.create(target: sourcePath, linkPath: link);
      created++;
    }
    return created;
  }

  /// Replaces every extra physical copy in [set] with hardlinks to the first
  /// one. [sha1Of] must return the file's SHA1; copies are only merged when
  /// their hashes match, so differing files are never destroyed.
  static Future<int> reclaim(
    DuplicateSet set,
    Future<String> Function(PhysicalFile f) sha1Of,
  ) async {
    final keeper = set.files.first;
    final keeperHash = await sha1Of(keeper);
    var freed = 0;
    for (final dup in set.files.skip(1)) {
      if (await sha1Of(dup) != keeperHash) {
        throw HardlinkException(
          '${dup.primary.fileName} differs from ${keeper.primary.fileName} (SHA1 mismatch); not merged.',
        );
      }
      for (final link in dup.links) {
        await Hardlinks.replaceWithLink(
          keeper: keeper.primary.path,
          duplicate: link.path,
        );
      }
      freed += dup.size;
    }
    return freed;
  }
}
