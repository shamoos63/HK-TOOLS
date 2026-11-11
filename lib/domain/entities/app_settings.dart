import 'dart:io';

/// Light / dark appearance.
enum AppearanceMode { system, light, dark }

/// Interface language.
enum AppLanguage { system, english, arabic }

/// User preferences (Settings screen).
class AppSettings {
  const AppSettings({
    required this.targetDirectory,
    this.tempDirectory,
    this.threads = 8,
    this.maxConcurrentDownloads = 2,
    this.autoVerifySha1 = true,
    this.autoDeviceLinks = true,
    this.globalSpeedLimitBytesPerSecond = 0,
    this.linkRefreshTimeout = const Duration(seconds: 30),
    this.deviceToolsDirectory,
    this.deviceDataDirectory,
    this.uiScale,
    this.ipaDirectory,
    this.askIpaLocation = false,
    this.keepOldIpaVersions = false,
    this.checkToolsAtStartup = true,
    this.galleryPrivacyMode = false,
    this.reducedEffects,
    this.appearance = AppearanceMode.system,
    this.language = AppLanguage.system,
  });

  /// Repository folder downloads land in (e.g. `D:\Apple_Firmwares`).
  final String targetDirectory;

  /// Optional scratch folder for partial files; `null` = next to the target.
  final String? tempDirectory;
  final int threads;
  final int maxConcurrentDownloads;
  final bool autoVerifySha1;

  /// After a download, hardlink it as one file name per device it serves.
  final bool autoDeviceLinks;
  final int globalSpeedLimitBytesPerSecond;
  final Duration linkRefreshTimeout;

  /// Folder holding the libimobiledevice tools; `null` = auto-detect.
  final String? deviceToolsDirectory;

  /// Where device backups, screenshots, pulled files and crash logs go;
  /// `null` = `<Downloads>/HK Tools/Device Data`.
  final String? deviceDataDirectory;

  /// Interface size multiplier (0.75–1.25); `null` = platform default
  /// ([defaultUiScale]).
  final double? uiScale;

  /// Where App Store `.ipa` downloads go; `null` =
  /// `<Downloads>/HK Tools/App Store`.
  final String? ipaDirectory;

  /// Ask for a folder each time an `.ipa` is downloaded.
  final bool askIpaLocation;

  /// IPA library: keep the previous file when an app is updated.
  final bool keepOldIpaVersions;

  /// Run the setup assistant check when the app starts.
  final bool checkToolsAtStartup;

  /// Gallery thumbnails are blurred until switched off.
  final bool galleryPrivacyMode;

  /// No glows / live background blur (solid panels). `null` = platform
  /// default: on for Windows, where some graphics drivers render those
  /// effects as bright, washed-out areas.
  final bool? reducedEffects;

  /// Light or dark; `system` follows the computer's setting.
  final AppearanceMode appearance;

  /// `system` follows the computer's language (Arabic or English).
  final AppLanguage language;

  bool get effectiveReducedEffects => reducedEffects ?? Platform.isWindows;

  /// Windows renders larger at the common 125–150% display scaling, so the
  /// UI starts a step smaller there.
  static double get defaultUiScale => Platform.isWindows ? 0.9 : 1.0;

  double get effectiveUiScale => uiScale ?? defaultUiScale;

  AppSettings copyWith({
    String? targetDirectory,
    String? Function()? tempDirectory,
    int? threads,
    int? maxConcurrentDownloads,
    bool? autoVerifySha1,
    bool? autoDeviceLinks,
    int? globalSpeedLimitBytesPerSecond,
    Duration? linkRefreshTimeout,
    String? Function()? deviceToolsDirectory,
    String? Function()? deviceDataDirectory,
    double? Function()? uiScale,
    String? Function()? ipaDirectory,
    bool? askIpaLocation,
    bool? keepOldIpaVersions,
    bool? checkToolsAtStartup,
    bool? galleryPrivacyMode,
    bool? Function()? reducedEffects,
    AppearanceMode? appearance,
    AppLanguage? language,
  }) => AppSettings(
    targetDirectory: targetDirectory ?? this.targetDirectory,
    tempDirectory: tempDirectory != null ? tempDirectory() : this.tempDirectory,
    threads: threads ?? this.threads,
    maxConcurrentDownloads:
        maxConcurrentDownloads ?? this.maxConcurrentDownloads,
    autoVerifySha1: autoVerifySha1 ?? this.autoVerifySha1,
    autoDeviceLinks: autoDeviceLinks ?? this.autoDeviceLinks,
    globalSpeedLimitBytesPerSecond:
        globalSpeedLimitBytesPerSecond ?? this.globalSpeedLimitBytesPerSecond,
    linkRefreshTimeout: linkRefreshTimeout ?? this.linkRefreshTimeout,
    deviceToolsDirectory: deviceToolsDirectory != null
        ? deviceToolsDirectory()
        : this.deviceToolsDirectory,
    deviceDataDirectory: deviceDataDirectory != null
        ? deviceDataDirectory()
        : this.deviceDataDirectory,
    uiScale: uiScale != null ? uiScale() : this.uiScale,
    ipaDirectory: ipaDirectory != null ? ipaDirectory() : this.ipaDirectory,
    askIpaLocation: askIpaLocation ?? this.askIpaLocation,
    keepOldIpaVersions: keepOldIpaVersions ?? this.keepOldIpaVersions,
    checkToolsAtStartup: checkToolsAtStartup ?? this.checkToolsAtStartup,
    galleryPrivacyMode: galleryPrivacyMode ?? this.galleryPrivacyMode,
    reducedEffects: reducedEffects != null
        ? reducedEffects()
        : this.reducedEffects,
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
  );

  factory AppSettings.fromJson(
    Map<String, dynamic> json, {
    required String fallbackTarget,
  }) => AppSettings(
    targetDirectory: json['targetDirectory'] as String? ?? fallbackTarget,
    tempDirectory: json['tempDirectory'] as String?,
    threads: ((json['threads'] as num?)?.toInt() ?? 8).clamp(2, 16),
    maxConcurrentDownloads:
        ((json['maxConcurrentDownloads'] as num?)?.toInt() ?? 2).clamp(1, 8),
    autoVerifySha1: json['autoVerifySha1'] as bool? ?? true,
    autoDeviceLinks: json['autoDeviceLinks'] as bool? ?? true,
    globalSpeedLimitBytesPerSecond:
        (json['globalSpeedLimitBytesPerSecond'] as num?)?.toInt() ?? 0,
    linkRefreshTimeout: Duration(
      seconds: (json['linkRefreshTimeoutSeconds'] as num?)?.toInt() ?? 30,
    ),
    deviceToolsDirectory: json['deviceToolsDirectory'] as String?,
    deviceDataDirectory: json['deviceDataDirectory'] as String?,
    uiScale: (json['uiScale'] as num?)?.toDouble().clamp(0.75, 1.25),
    ipaDirectory: json['ipaDirectory'] as String?,
    askIpaLocation: json['askIpaLocation'] as bool? ?? false,
    keepOldIpaVersions: json['keepOldIpaVersions'] as bool? ?? false,
    checkToolsAtStartup: json['checkToolsAtStartup'] as bool? ?? true,
    galleryPrivacyMode: json['galleryPrivacyMode'] as bool? ?? false,
    reducedEffects: json['reducedEffects'] as bool?,
    appearance:
        AppearanceMode.values
            .where((m) => m.name == json['appearance'])
            .firstOrNull ??
        AppearanceMode.system,
    language:
        AppLanguage.values
            .where((m) => m.name == json['language'])
            .firstOrNull ??
        AppLanguage.system,
  );

  Map<String, dynamic> toJson() => {
    'targetDirectory': targetDirectory,
    'tempDirectory': tempDirectory,
    'threads': threads,
    'maxConcurrentDownloads': maxConcurrentDownloads,
    'autoVerifySha1': autoVerifySha1,
    'autoDeviceLinks': autoDeviceLinks,
    'globalSpeedLimitBytesPerSecond': globalSpeedLimitBytesPerSecond,
    'linkRefreshTimeoutSeconds': linkRefreshTimeout.inSeconds,
    'deviceToolsDirectory': deviceToolsDirectory,
    'deviceDataDirectory': deviceDataDirectory,
    'uiScale': uiScale,
    'ipaDirectory': ipaDirectory,
    'askIpaLocation': askIpaLocation,
    'keepOldIpaVersions': keepOldIpaVersions,
    'checkToolsAtStartup': checkToolsAtStartup,
    'galleryPrivacyMode': galleryPrivacyMode,
    'reducedEffects': reducedEffects,
    'appearance': appearance.name,
    'language': language.name,
  };
}
