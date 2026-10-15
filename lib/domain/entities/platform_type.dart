/// Apple OS families served by IPSW.me.
enum PlatformType {
  iOS('iOS'),
  iPadOS('iPadOS'),
  macOS('macOS'),
  tvOS('tvOS'),
  watchOS('watchOS'),
  audioOS('audioOS'),
  visionOS('visionOS'),
  other('Other');

  const PlatformType(this.label);

  final String label;

  /// Derives the platform from an Apple hardware identifier
  /// (e.g. `iPhone13,2`, `iPad14,1`, `Mac14,2`, `VirtualMac2,1`).
  static PlatformType fromIdentifier(String identifier) {
    final id = identifier.toLowerCase();
    if (id.startsWith('iphone') || id.startsWith('ipod')) return iOS;
    if (id.startsWith('ipad')) return iPadOS;
    if (id.startsWith('mac') ||
        id.startsWith('imac') ||
        id.startsWith('virtualmac') ||
        id.startsWith('adp')) {
      return macOS;
    }
    if (id.startsWith('appletv')) return tvOS;
    if (id.startsWith('watch')) return watchOS;
    if (id.startsWith('audioaccessory')) return audioOS;
    if (id.startsWith('realitydevice')) return visionOS;
    return other;
  }

  static PlatformType fromName(String? name) => PlatformType.values.firstWhere(
    (p) => p.name == name,
    orElse: () => PlatformType.other,
  );

  LibraryCategory get category => switch (this) {
    iOS => LibraryCategory.iPhone,
    iPadOS => LibraryCategory.iPad,
    _ => LibraryCategory.others,
  };
}

/// Top-level tabs of the Library / Catalog screen.
enum LibraryCategory {
  iPhone('iPhone'),
  iPad('iPad'),
  others('Others');

  const LibraryCategory(this.label);

  final String label;
}
