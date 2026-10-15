import 'package:path/path.dart' as p;

import 'ipsw_release.dart';
import 'platform_type.dart';

enum DownloadStatus {
  queued,
  connecting,
  downloading,
  refreshingLink,
  paused,
  verifying,
  completed,
  failed,
  cancelled;

  bool get isActive =>
      this == connecting ||
      this == downloading ||
      this == refreshingLink ||
      this == verifying;

  bool get isTerminal => this == completed || this == cancelled;

  /// States from which the user may press "Resume" / "Retry".
  bool get isResumable => this == paused || this == failed;

  static DownloadStatus fromName(String? name) => DownloadStatus.values
      .firstWhere((s) => s.name == name, orElse: () => DownloadStatus.queued);
}

enum VerificationState {
  notRequested,
  pending,
  verifying,
  passed,
  failed,

  /// No SHA1 published for this file.
  unavailable;

  static VerificationState fromName(String? name) =>
      VerificationState.values.firstWhere(
        (s) => s.name == name,
        orElse: () => VerificationState.notRequested,
      );
}

/// A queued / running / finished IPSW download.
///
/// Immutable snapshot; the download manager replaces it via [copyWith].
/// Per-chunk byte ranges are not stored here — they live in the engine's
/// sidecar file next to the partial download so resume survives app restarts
/// and DB loss.
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.targetDirectory,
    required this.version,
    required this.buildId,
    required this.platform,
    required this.deviceIdentifiers,
    required this.createdAt,
    this.tempDirectory,
    this.sha1sum,
    this.expectedBytes = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.threadCount = 8,
    this.speedLimitBytesPerSecond = 0,
    this.status = DownloadStatus.queued,
    this.verification = VerificationState.notRequested,
    this.errorMessage,
    this.linkRefreshCount = 0,
    this.completedAt,
  });

  final String id;

  /// Current download URL (replaced by the link refresh engine).
  final String url;
  final String fileName;
  final String targetDirectory;

  /// Where the partial file lives while downloading. `null` = next to target.
  final String? tempDirectory;
  final String version;
  final String buildId;
  final PlatformType platform;

  /// Every device this payload serves; drives hardlink creation.
  final List<String> deviceIdentifiers;
  final String? sha1sum;

  /// Size reported by IPSW.me (may be 0 / stale).
  final int expectedBytes;

  /// Size reported by the server; authoritative once known.
  final int totalBytes;
  final int downloadedBytes;
  final int threadCount;

  /// Per-task cap; 0 = unlimited (global cap still applies).
  final int speedLimitBytesPerSecond;
  final DownloadStatus status;
  final VerificationState verification;
  final String? errorMessage;
  final int linkRefreshCount;
  final DateTime createdAt;
  final DateTime? completedAt;

  String get targetPath => p.join(targetDirectory, fileName);

  /// Partial payload, pre-allocated to full size.
  String get partialPath =>
      p.join(tempDirectory ?? targetDirectory, '$fileName.hkdl');

  /// Chunk map / resume metadata for [partialPath].
  String get sidecarPath => '$partialPath.json';

  int get knownSize => totalBytes > 0 ? totalBytes : expectedBytes;

  /// Same key as [IpswRelease.payloadKey], linking a task to catalog entries.
  String get payloadKey {
    final sha = sha1sum;
    return sha != null && sha.isNotEmpty
        ? 'sha1:${sha.toLowerCase()}'
        : 'url:$url';
  }

  double get fraction =>
      knownSize > 0 ? (downloadedBytes / knownSize).clamp(0.0, 1.0) : 0.0;

  factory DownloadTask.fromGroup({
    required String id,
    required IpswGroup group,
    required String targetDirectory,
    String? tempDirectory,
    int threadCount = 8,
  }) {
    final r = group.release;
    return DownloadTask(
      id: id,
      url: r.url,
      fileName: r.fileName,
      targetDirectory: targetDirectory,
      tempDirectory: tempDirectory,
      version: r.version,
      buildId: r.buildId,
      platform: r.platform,
      deviceIdentifiers: group.deviceIdentifiers,
      sha1sum: r.sha1sum,
      expectedBytes: r.fileSize,
      threadCount: threadCount,
      createdAt: DateTime.now(),
    );
  }

  DownloadTask copyWith({
    String? url,
    List<String>? deviceIdentifiers,
    int? totalBytes,
    int? downloadedBytes,
    int? threadCount,
    int? speedLimitBytesPerSecond,
    DownloadStatus? status,
    VerificationState? verification,
    String? Function()? errorMessage,
    int? linkRefreshCount,
    DateTime? Function()? completedAt,
  }) => DownloadTask(
    id: id,
    url: url ?? this.url,
    fileName: fileName,
    targetDirectory: targetDirectory,
    tempDirectory: tempDirectory,
    version: version,
    buildId: buildId,
    platform: platform,
    deviceIdentifiers: deviceIdentifiers ?? this.deviceIdentifiers,
    sha1sum: sha1sum,
    expectedBytes: expectedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    threadCount: threadCount ?? this.threadCount,
    speedLimitBytesPerSecond:
        speedLimitBytesPerSecond ?? this.speedLimitBytesPerSecond,
    status: status ?? this.status,
    verification: verification ?? this.verification,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    linkRefreshCount: linkRefreshCount ?? this.linkRefreshCount,
    createdAt: createdAt,
    completedAt: completedAt != null ? completedAt() : this.completedAt,
  );

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    url: json['url'] as String,
    fileName: json['fileName'] as String,
    targetDirectory: json['targetDirectory'] as String,
    tempDirectory: json['tempDirectory'] as String?,
    version: json['version'] as String? ?? '',
    buildId: json['buildId'] as String? ?? '',
    platform: PlatformType.fromName(json['platform'] as String?),
    deviceIdentifiers:
        (json['deviceIdentifiers'] as List?)?.cast<String>() ?? const [],
    sha1sum: json['sha1sum'] as String?,
    expectedBytes: (json['expectedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
    threadCount: (json['threadCount'] as num?)?.toInt() ?? 8,
    speedLimitBytesPerSecond:
        (json['speedLimitBytesPerSecond'] as num?)?.toInt() ?? 0,
    status: DownloadStatus.fromName(json['status'] as String?),
    verification: VerificationState.fromName(json['verification'] as String?),
    errorMessage: json['errorMessage'] as String?,
    linkRefreshCount: (json['linkRefreshCount'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'targetDirectory': targetDirectory,
    'tempDirectory': tempDirectory,
    'version': version,
    'buildId': buildId,
    'platform': platform.name,
    'deviceIdentifiers': deviceIdentifiers,
    'sha1sum': sha1sum,
    'expectedBytes': expectedBytes,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'threadCount': threadCount,
    'speedLimitBytesPerSecond': speedLimitBytesPerSecond,
    'status': status.name,
    'verification': verification.name,
    'errorMessage': errorMessage,
    'linkRefreshCount': linkRefreshCount,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}
