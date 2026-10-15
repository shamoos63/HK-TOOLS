import '../../domain/entities/platform_type.dart';

/// Parsed form of the universal search box.
///
/// Supports filter tags (`is:signed`, `is:unsigned`, `platform:ios`,
/// `chip:m-series`, `version:18.0`, `build:22A3354`) and natural phrases:
/// `iOS 18.0.1`, `macOS Sequoia`, `iPhone 15 Pro`, `Mac13,2`, `A2442`,
/// `22A3354`. Free-text terms are AND-ed against device name, identifier,
/// board config, version and build.
class SearchQuery {
  SearchQuery({
    this.signed,
    Set<PlatformType>? platforms,
    this.chip,
    this.version,
    this.build,
    List<String>? modelNumbers,
    List<String>? terms,
  }) : platforms = platforms ?? {},
       modelNumbers = modelNumbers ?? [],
       terms = terms ?? [];

  /// `true` = signed only, `false` = unsigned only, `null` = both.
  final bool? signed;
  final Set<PlatformType> platforms;

  /// `m-series` or a raw SoC platform prefix such as `t8112`.
  final String? chip;

  /// Version prefix by component: `18` matches `18.0.1`, `18.0` does not
  /// match `18.01`.
  final String? version;

  /// Build prefix, case-insensitive (`22A` matches `22A3354`).
  final String? build;

  /// Marketing model numbers (`A2442`) to resolve to identifiers.
  final List<String> modelNumbers;

  /// Lower-case free-text terms.
  final List<String> terms;

  bool get isEmpty =>
      signed == null &&
      platforms.isEmpty &&
      chip == null &&
      version == null &&
      build == null &&
      modelNumbers.isEmpty &&
      terms.isEmpty;

  /// True when the query targets one OS release (enables bulk select).
  bool get targetsVersion => version != null || build != null;

  static const _platformWords = {
    'ios': PlatformType.iOS,
    'iphoneos': PlatformType.iOS,
    'ipados': PlatformType.iPadOS,
    'macos': PlatformType.macOS,
    'osx': PlatformType.macOS,
    'tvos': PlatformType.tvOS,
    'watchos': PlatformType.watchOS,
    'audioos': PlatformType.audioOS,
    'visionos': PlatformType.visionOS,
  };

  /// macOS codenames → major version.
  static const _macCodenames = {
    'monterey': '12',
    'ventura': '13',
    'sonoma': '14',
    'sequoia': '15',
    'tahoe': '26',
  };

  static final _versionLike = RegExp(r'^\d+(\.\d+)+$');
  static final _bareMajor = RegExp(r'^\d+(\.\d+)*$');
  static final _buildLike = RegExp(r'^\d{1,2}[A-Za-z]\d{1,5}[a-z]?$');
  static final _modelLike = RegExp(r'^[Aa]\d{4}$');

  static SearchQuery parse(String input) {
    bool? signed;
    final platforms = <PlatformType>{};
    String? chip;
    String? version;
    String? build;
    final models = <String>[];
    final terms = <String>[];

    final tokens = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final lower = token.toLowerCase();
      final colon = lower.indexOf(':');
      if (colon > 0 && colon < lower.length - 1) {
        final key = lower.substring(0, colon);
        final value = lower.substring(colon + 1);
        switch (key) {
          case 'is':
            if (value == 'signed') signed = true;
            if (value == 'unsigned') signed = false;
            continue;
          case 'platform' || 'os':
            final p = _platformWords[value] ?? _platformByName(value);
            if (p != null) platforms.add(p);
            continue;
          case 'chip':
            chip = value;
            continue;
          case 'version' || 'v':
            version = value;
            continue;
          case 'build' || 'b':
            build = value;
            continue;
        }
      }
      final platform = _platformWords[lower];
      if (platform != null) {
        platforms.add(platform);
        // "iOS 18" — a bare number right after the OS name is a version.
        if (i + 1 < tokens.length && _bareMajor.hasMatch(tokens[i + 1])) {
          version = tokens[++i];
        }
        continue;
      }
      if (_macCodenames[lower] case final major?) {
        platforms.add(PlatformType.macOS);
        version ??= major;
        continue;
      }
      if (_versionLike.hasMatch(token)) {
        version = token;
      } else if (_buildLike.hasMatch(token)) {
        build = lower;
      } else if (_modelLike.hasMatch(token)) {
        models.add(token.toUpperCase());
      } else {
        terms.add(lower);
      }
    }
    return SearchQuery(
      signed: signed,
      platforms: platforms,
      chip: chip,
      version: version,
      build: build,
      modelNumbers: models,
      terms: terms,
    );
  }

  static PlatformType? _platformByName(String value) {
    for (final p in PlatformType.values) {
      if (p.name.toLowerCase() == value) return p;
    }
    return null;
  }

  bool matchesVersion(String releaseVersion) {
    final v = version;
    if (v == null) return true;
    return releaseVersion == v || releaseVersion.startsWith('$v.');
  }

  bool matchesBuild(String buildId) =>
      build == null || buildId.toLowerCase().startsWith(build!);
}
