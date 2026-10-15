import 'platform_type.dart';

/// A single IPSW firmware file as reported by IPSW.me for one device.
///
/// The same physical file (same [url] / [sha1sum]) is usually reported once per
/// device that can restore from it — see [IpswGroup] for the deduplicated view.
class IpswRelease {
  const IpswRelease({
    required this.identifier,
    required this.version,
    required this.buildId,
    required this.url,
    required this.fileSize,
    required this.signed,
    this.sha1sum,
    this.md5sum,
    this.sha256sum,
    this.releaseDate,
    this.uploadDate,
  });

  /// Device identifier this entry was reported for.
  final String identifier;
  final String version;
  final String buildId;
  final String url;
  final int fileSize;
  final bool signed;
  final String? sha1sum;
  final String? md5sum;
  final String? sha256sum;
  final DateTime? releaseDate;
  final DateTime? uploadDate;

  PlatformType get platform => PlatformType.fromIdentifier(identifier);

  /// File name Apple publishes the IPSW under, e.g.
  /// `iPhone_6.1_P3_18.0_22A3354_Restore.ipsw`.
  String get fileName {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    return segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : '${identifier}_${version}_${buildId}_Restore.ipsw';
  }

  /// Key that identifies the physical payload. SHA1 is authoritative; the URL
  /// is the fallback for entries without a published hash.
  String get payloadKey {
    final sha = sha1sum;
    return sha != null && sha.isNotEmpty
        ? 'sha1:${sha.toLowerCase()}'
        : 'url:$url';
  }

  factory IpswRelease.fromJson(
    Map<String, dynamic> json, {
    String? identifier,
  }) => IpswRelease(
    identifier: json['identifier'] as String? ?? identifier ?? '',
    version: json['version'] as String? ?? '',
    buildId: json['buildid'] as String? ?? '',
    url: json['url'] as String? ?? '',
    fileSize: (json['filesize'] as num?)?.toInt() ?? 0,
    signed: json['signed'] as bool? ?? false,
    sha1sum: _nonEmpty(json['sha1sum']),
    md5sum: _nonEmpty(json['md5sum']),
    sha256sum: _nonEmpty(json['sha256sum']),
    releaseDate: _date(json['releasedate']),
    uploadDate: _date(json['uploaddate']),
  );

  Map<String, dynamic> toJson() => {
    'identifier': identifier,
    'version': version,
    'buildid': buildId,
    'url': url,
    'filesize': fileSize,
    'signed': signed,
    'sha1sum': sha1sum,
    'md5sum': md5sum,
    'sha256sum': sha256sum,
    'releasedate': releaseDate?.toIso8601String(),
    'uploaddate': uploadDate?.toIso8601String(),
  };

  IpswRelease copyWith({String? url, bool? signed}) => IpswRelease(
    identifier: identifier,
    version: version,
    buildId: buildId,
    url: url ?? this.url,
    fileSize: fileSize,
    signed: signed ?? this.signed,
    sha1sum: sha1sum,
    md5sum: md5sum,
    sha256sum: sha256sum,
    releaseDate: releaseDate,
    uploadDate: uploadDate,
  );

  static String? _nonEmpty(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// One physical IPSW payload and every device that restores from it
/// (e.g. iPhone 12 + iPhone 12 Pro, or an Apple Silicon universal macOS IPSW).
class IpswGroup {
  IpswGroup(this.release, List<String> deviceIdentifiers)
    : deviceIdentifiers = List.unmodifiable(deviceIdentifiers);

  /// Representative release; [IpswRelease.identifier] is the first device.
  final IpswRelease release;
  final List<String> deviceIdentifiers;

  String get payloadKey => release.payloadKey;
  bool get isShared => deviceIdentifiers.length > 1;

  /// Collapses per-device releases into one group per physical payload,
  /// preserving first-seen order.
  static List<IpswGroup> groupReleases(Iterable<IpswRelease> releases) {
    final byKey = <String, (IpswRelease, List<String>)>{};
    for (final r in releases) {
      final entry = byKey.putIfAbsent(r.payloadKey, () => (r, <String>[]));
      if (!entry.$2.contains(r.identifier)) entry.$2.add(r.identifier);
    }
    return [for (final (r, ids) in byKey.values) IpswGroup(r, ids)];
  }
}
