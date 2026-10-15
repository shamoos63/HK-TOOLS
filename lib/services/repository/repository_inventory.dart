import 'package:path/path.dart' as p;

import '../../domain/entities/ipsw_release.dart';
import '../../domain/entities/platform_type.dart';
import '../catalog/catalog_index.dart';
import 'repository_scanner.dart';

/// Folder that holds per-device hardlink names.
const deviceLinksFolder = 'By Device';

enum MatchMethod { manifest, fileName, none }

enum Integrity {
  /// Identified, hash not computed yet.
  unverified,
  verified,
  mismatch,

  /// Size differs from IPSW.me (truncated / partial copy).
  sizeMismatch,

  /// Not a readable IPSW and not matched by name.
  unreadable,
}

/// One physical file on disk and every hardlinked path that points at it.
class PhysicalFile {
  PhysicalFile({
    required this.identityId,
    required this.links,
    required this.group,
    required this.method,
    required this.integrity,
  });

  final String identityId;

  /// Primary (non-"By Device") path first.
  final List<ScanEntry> links;
  final IpswGroup? group;
  final MatchMethod method;
  final Integrity integrity;

  ScanEntry get primary => links.first;
  int get size => primary.size;
  String? get payloadKey => group?.payloadKey;
  String? get sha1 =>
      links.map((l) => l.sha1).firstWhere((s) => s != null, orElse: () => null);
  String get version =>
      primary.manifest?.productVersion ?? group?.release.version ?? '?';
  String get buildId =>
      primary.manifest?.buildVersion ?? group?.release.buildId ?? '?';
  PlatformType? get platform =>
      group?.release.platform ??
      (primary.manifest?.supportedProductTypes.isNotEmpty ?? false
          ? PlatformType.fromIdentifier(
              primary.manifest!.supportedProductTypes.first,
            )
          : null);
  List<String> get deviceIdentifiers =>
      group?.deviceIdentifiers ??
      primary.manifest?.supportedProductTypes ??
      const [];

  /// Paths in the device-links folder.
  int get deviceLinkCount => links.where((l) => _inDeviceFolder(l.path)).length;
}

/// The same payload stored as more than one physical file.
class DuplicateSet {
  DuplicateSet(this.group, this.files);

  final IpswGroup group;
  final List<PhysicalFile> files;

  int get reclaimableBytes => files.skip(1).fold(0, (s, f) => s + f.size);
}

/// A latest-signed payload that the repository lacks, and who needs it.
class MissingFirmware {
  MissingFirmware(this.group, this.devices);

  final IpswGroup group;
  final List<String> devices;
}

class RepositoryInventory {
  RepositoryInventory._(this.folder, this.files, this.index);

  static final empty = RepositoryInventory._('', const [], CatalogIndex.empty);

  final String folder;
  final List<PhysicalFile> files;
  final CatalogIndex index;

  late final Set<String> payloadKeys = {
    for (final f in files)
      if (f.payloadKey != null &&
          f.integrity != Integrity.sizeMismatch &&
          f.integrity != Integrity.mismatch)
        f.payloadKey!,
  };

  int get physicalBytes => files.fold(0, (s, f) => s + f.size);
  int get pathCount => files.fold(0, (s, f) => s + f.links.length);
  int get identifiedCount => files.where((f) => f.group != null).length;
  int get verifiedCount =>
      files.where((f) => f.integrity == Integrity.verified).length;
  int get problemCount => files
      .where(
        (f) =>
            f.integrity == Integrity.mismatch ||
            f.integrity == Integrity.sizeMismatch ||
            f.integrity == Integrity.unreadable,
      )
      .length;

  late final List<DuplicateSet> duplicates = () {
    final byPayload = <String, List<PhysicalFile>>{};
    for (final f in files) {
      if (f.payloadKey != null) {
        byPayload.putIfAbsent(f.payloadKey!, () => []).add(f);
      }
    }
    return [
      for (final e in byPayload.entries)
        if (e.value.length > 1)
          DuplicateSet(
            e.value.first.group!,
            // Keep the copy that already has the most links.
            [...e.value]
              ..sort((a, b) => b.links.length.compareTo(a.links.length)),
          ),
    ];
  }();

  int get reclaimableBytes =>
      duplicates.fold(0, (s, d) => s + d.reclaimableBytes);

  /// Devices whose latest signed IPSW is not in the repository, grouped by
  /// payload so shared files are queued once.
  ({List<MissingFirmware> missing, int upToDate}) missingLatest({
    Set<PlatformType> platforms = const {},
    bool onlyDevicesInRepository = false,
  }) {
    final owned = onlyDevicesInRepository
        ? {for (final f in files) ...f.deviceIdentifiers}
        : const <String>{};
    final missing = <String, MissingFirmware>{};
    var upToDate = 0;
    for (final d in index.devices) {
      if (platforms.isNotEmpty && !platforms.contains(d.platform)) continue;
      if (onlyDevicesInRepository && !owned.contains(d.identifier)) continue;
      final latest = index.latestSigned(d.identifier);
      if (latest == null) continue;
      if (payloadKeys.contains(latest.payloadKey)) {
        upToDate++;
      } else {
        missing
            .putIfAbsent(latest.payloadKey, () => MissingFirmware(latest, []))
            .devices
            .add(d.identifier);
      }
    }
    final list = missing.values.toList()
      ..sort(
        (a, b) => CatalogIndex.compareReleasesNewestFirst(
          a.group.release,
          b.group.release,
        ),
      );
    return (missing: list, upToDate: upToDate);
  }

  static RepositoryInventory analyze(
    String folder,
    List<ScanEntry> entries,
    CatalogIndex index,
  ) {
    final byIdentity = <String, List<ScanEntry>>{};
    for (final e in entries) {
      byIdentity.putIfAbsent(e.identity.id, () => []).add(e);
    }
    final files = <PhysicalFile>[];
    for (final MapEntry(key: id, value: links) in byIdentity.entries) {
      // Every link is the same bytes, so any one identifies the file.
      final manifest = links
          .map((l) => l.manifest)
          .firstWhere((m) => m != null, orElse: () => null);
      final size = links.first.size;
      IpswGroup? group;
      var method = MatchMethod.none;
      if (manifest != null) {
        group = index.groupForBuild(
          manifest.buildVersion,
          manifest.supportedProductTypes,
          size: size,
        );
        if (group != null) method = MatchMethod.manifest;
      }
      if (group == null) {
        for (final l in links) {
          group = index.groupForFileName(l.fileName);
          if (group != null) {
            method = MatchMethod.fileName;
            break;
          }
        }
      }
      // Primary name: outside "By Device", Apple's published file name,
      // shallowest, shortest.
      final appleName = group?.release.fileName.toLowerCase();
      int rank(ScanEntry e) =>
          (_inDeviceFolder(e.path) ? 2 : 0) +
          (e.fileName.toLowerCase() == appleName ? 0 : 1);
      links.sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final byDepth = p
            .split(a.path)
            .length
            .compareTo(p.split(b.path).length);
        return byDepth != 0 ? byDepth : a.path.length.compareTo(b.path.length);
      });
      final primary = links.first;
      final m = primary.manifest ?? manifest;
      final sha = links
          .map((l) => l.sha1)
          .firstWhere((s) => s != null, orElse: () => null);
      final expected = group?.release.sha1sum?.toLowerCase();
      final Integrity integrity;
      if (group != null &&
          group.release.fileSize > 0 &&
          group.release.fileSize != primary.size) {
        integrity = Integrity.sizeMismatch;
      } else if (sha != null && expected != null) {
        integrity = sha == expected ? Integrity.verified : Integrity.mismatch;
      } else if (group == null && m == null) {
        integrity = Integrity.unreadable;
      } else {
        integrity = Integrity.unverified;
      }
      files.add(
        PhysicalFile(
          identityId: id,
          links: links,
          group: group,
          method: method,
          integrity: integrity,
        ),
      );
    }
    files.sort((a, b) {
      final ra = a.group?.release;
      final rb = b.group?.release;
      if (ra != null && rb != null) {
        return CatalogIndex.compareReleasesNewestFirst(ra, rb);
      }
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.primary.fileName.compareTo(b.primary.fileName);
    });
    return RepositoryInventory._(folder, files, index);
  }
}

bool _inDeviceFolder(String path) => p.split(path).contains(deviceLinksFolder);

/// Per-device file name for a hardlink, e.g. `iPhone13,2_27.0.1_24A446_Restore.ipsw`.
String deviceLinkName(String identifier, String version, String buildId) =>
    '${identifier}_${version}_${buildId}_Restore.ipsw';
