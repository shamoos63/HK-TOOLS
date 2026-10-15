import '../../domain/entities/device.dart';
import '../../domain/entities/ipsw_release.dart';
import '../../domain/entities/platform_type.dart';
import 'search_query.dart';

class SearchResult {
  const SearchResult({required this.groups, required this.deviceCount});

  /// One entry per physical payload, newest first.
  final List<IpswGroup> groups;

  /// Distinct devices that matched.
  final int deviceCount;

  List<IpswGroup> get signedGroups => [
    for (final g in groups)
      if (g.release.signed) g,
  ];

  static const empty = SearchResult(groups: [], deviceCount: 0);
}

/// In-memory index over devices and their firmware lists, with payload-level
/// deduplication (which devices share one physical IPSW).
class CatalogIndex {
  CatalogIndex({
    required List<Device> devices,
    required Map<String, List<IpswRelease>> firmwares,
  }) : devices = List<Device>.unmodifiable(
         List<Device>.of(devices)..sort(compareDevicesNewestFirst),
       ),
       _firmwares = firmwares {
    for (final d in this.devices) {
      _byId[d.identifier] = d;
    }
    for (final entry in firmwares.entries) {
      for (final r in entry.value) {
        final ids = _payloadDevices.putIfAbsent(r.payloadKey, () => []);
        if (!ids.contains(entry.key)) ids.add(entry.key);
        _payloadRelease.putIfAbsent(r.payloadKey, () => r);
        _payloadByFileName.putIfAbsent(
          r.fileName.toLowerCase(),
          () => r.payloadKey,
        );
      }
    }
  }

  static final empty = CatalogIndex(devices: const [], firmwares: const {});

  final List<Device> devices;
  final Map<String, List<IpswRelease>> _firmwares;
  final Map<String, Device> _byId = {};
  final Map<String, List<String>> _payloadDevices = {};
  final Map<String, IpswRelease> _payloadRelease = {};
  final Map<String, String> _payloadByFileName = {};

  int get firmwareDeviceCount => _firmwares.length;
  int get payloadCount => _payloadRelease.length;
  int get signedPayloadCount =>
      _payloadRelease.values.where((r) => r.signed).length;

  Device? device(String identifier) => _byId[identifier];

  String displayName(String identifier) =>
      _byId[identifier]?.name ?? identifier;

  bool hasFirmwares(String identifier) => _firmwares.containsKey(identifier);

  List<Device> devicesIn(LibraryCategory category) => [
    for (final d in devices)
      if (d.platform.category == category) d,
  ];

  IpswGroup? groupFor(String payloadKey) {
    final r = _payloadRelease[payloadKey];
    return r == null ? null : IpswGroup(r, _payloadDevices[payloadKey]!);
  }

  /// Payload published under Apple's file name (fallback identification).
  IpswGroup? groupForFileName(String fileName) {
    final key = _payloadByFileName[fileName.toLowerCase()];
    return key == null ? null : groupFor(key);
  }

  /// Payload for a build that restores any of [productTypes]; prefers the
  /// candidate whose published size equals [size].
  IpswGroup? groupForBuild(
    String buildId,
    List<String> productTypes, {
    int? size,
  }) {
    IpswGroup? fallback;
    for (final id in productTypes) {
      for (final r in _firmwares[id] ?? const <IpswRelease>[]) {
        if (r.buildId != buildId) continue;
        final g = groupFor(r.payloadKey)!;
        if (size == null || r.fileSize == size) return g;
        fallback ??= g;
      }
    }
    return fallback;
  }

  /// Every payload one device can restore from, newest first.
  List<IpswGroup> groupsForDevice(
    String identifier, {
    bool signedOnly = false,
  }) {
    final releases = [...?_firmwares[identifier]]
      ..sort(compareReleasesNewestFirst);
    return [
      for (final r in releases)
        if (!signedOnly || r.signed)
          IpswGroup(r, _payloadDevices[r.payloadKey] ?? [identifier]),
    ];
  }

  /// Latest signed payload for a device (drives the "missing firmwares" diff).
  IpswGroup? latestSigned(String identifier) {
    final groups = groupsForDevice(identifier, signedOnly: true);
    return groups.isEmpty ? null : groups.first;
  }

  SearchResult search(
    SearchQuery query, {
    Map<String, String> resolvedModels = const {},
  }) {
    if (query.isEmpty) return SearchResult.empty;
    final modelIds = {
      for (final m in query.modelNumbers)
        if (resolvedModels[m] case final id?) id.toLowerCase(),
    };
    // Unresolved model numbers can still match locally enriched devices.
    final pendingModels = [
      for (final m in query.modelNumbers)
        if (!resolvedModels.containsKey(m)) m,
    ];

    final matchedKeys = <String>{};
    final matchedDevices = <String>{};
    for (final device in devices) {
      if (query.platforms.isNotEmpty &&
          !query.platforms.contains(device.platform)) {
        continue;
      }
      if (query.chip != null && !_matchesChip(device, query.chip!)) continue;
      if (query.modelNumbers.isNotEmpty) {
        final id = device.identifier.toLowerCase();
        final viaModel =
            modelIds.contains(id) ||
            pendingModels.any(device.modelNumbers.contains);
        if (!viaModel) continue;
      }
      final releases = _firmwares[device.identifier];
      if (releases == null) continue;
      final deviceHay = _deviceHaystack(device);
      // Terms the device itself doesn't satisfy must match each release.
      final releaseTerms = <String>[];
      var deviceRejected = false;
      for (final term in query.terms) {
        if (_termMatches(deviceHay, term)) continue;
        if (_numericTerm.hasMatch(term)) {
          // "iPhone 15": bare numbers refer to the model, never a version.
          deviceRejected = true;
          break;
        }
        releaseTerms.add(term);
      }
      if (deviceRejected) continue;
      for (final r in releases) {
        if (query.signed != null && r.signed != query.signed) continue;
        if (!query.matchesVersion(r.version) ||
            !query.matchesBuild(r.buildId)) {
          continue;
        }
        if (releaseTerms.isNotEmpty) {
          final hay =
              '${r.version} ${r.buildId.toLowerCase()} ${r.fileName.toLowerCase()}';
          if (!releaseTerms.every(hay.contains)) continue;
        }
        matchedKeys.add(r.payloadKey);
        matchedDevices.add(device.identifier);
      }
    }
    final groups = [for (final key in matchedKeys) groupFor(key)!]
      ..sort((a, b) => compareReleasesNewestFirst(a.release, b.release));
    return SearchResult(groups: groups, deviceCount: matchedDevices.length);
  }

  static final _numericTerm = RegExp(r'^\d+$');

  static bool _termMatches(String hay, String term) {
    if (!_numericTerm.hasMatch(term)) return hay.contains(term);
    // Digit-boundary match so "1" doesn't hit "iPhone 12".
    return RegExp('(^|[^0-9])$term([^0-9]|\$)').hasMatch(hay);
  }

  static String _deviceHaystack(Device d) => [
    d.name,
    d.identifier,
    for (final b in d.boards) b.boardConfig,
    ...d.modelNumbers,
  ].join(' ').toLowerCase();

  static bool isAppleSilicon(Device d) =>
      d.platform == PlatformType.macOS &&
      d.boards.any((b) {
        final p = b.platform?.toLowerCase() ?? '';
        return p.startsWith('t8') || p.startsWith('t6');
      });

  static bool _matchesChip(Device d, String chip) {
    if (chip == 'm-series' || chip == 'apple-silicon' || chip == 'm') {
      return isAppleSilicon(d);
    }
    return d.boards.any(
      (b) => (b.platform ?? '').toLowerCase().startsWith(chip),
    );
  }

  static final _idPattern = RegExp(r'^([A-Za-z]+)(\d+),(\d+)$');

  /// Newest hardware first: `iPhone17,1` before `iPhone9,3`.
  static int compareDevicesNewestFirst(Device a, Device b) {
    final ma = _idPattern.firstMatch(a.identifier);
    final mb = _idPattern.firstMatch(b.identifier);
    if (ma == null || mb == null) return a.identifier.compareTo(b.identifier);
    final family = ma.group(1)!.compareTo(mb.group(1)!);
    if (family != 0) return family;
    final major = int.parse(mb.group(2)!).compareTo(int.parse(ma.group(2)!));
    if (major != 0) return major;
    return int.parse(mb.group(3)!).compareTo(int.parse(ma.group(3)!));
  }

  static int compareReleasesNewestFirst(IpswRelease a, IpswRelease b) {
    final byVersion = compareVersions(b.version, a.version);
    if (byVersion != 0) return byVersion;
    return b.buildId.compareTo(a.buildId);
  }

  /// Numeric dotted-version compare (`18.10` > `18.9`).
  static int compareVersions(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// One OS version within a result set ("iOS 27.0.1 · 40 payloads").
class VersionFacet {
  VersionFacet(this.platform, this.version);

  final PlatformType platform;
  final String version;
  int payloads = 0;
  int bytes = 0;
  int deviceTargets = 0;

  String get key => facetKey(platform, version);
  String get label => '${platform.label} $version';

  static String facetKey(PlatformType platform, String version) =>
      '${platform.name}:$version';

  static String keyOf(IpswGroup g) =>
      facetKey(g.release.platform, g.release.version);

  /// Facets for [groups], grouped by platform (iOS, iPadOS, macOS, ...) and
  /// newest version first within each platform.
  static List<VersionFacet> of(Iterable<IpswGroup> groups) {
    final map = <String, VersionFacet>{};
    for (final g in groups) {
      final f = map.putIfAbsent(
        keyOf(g),
        () => VersionFacet(g.release.platform, g.release.version),
      );
      f.payloads++;
      f.bytes += g.release.fileSize;
      f.deviceTargets += g.deviceIdentifiers.length;
    }
    return map.values.toList()..sort((a, b) {
      final byPlatform = a.platform.index.compareTo(b.platform.index);
      return byPlatform != 0
          ? byPlatform
          : CatalogIndex.compareVersions(b.version, a.version);
    });
  }

  /// Keys of the newest version per platform.
  static Set<String> latestKeys(List<VersionFacet> facets) {
    final seen = <PlatformType>{};
    return {
      for (final f in facets)
        if (seen.add(f.platform)) f.key,
    };
  }
}
