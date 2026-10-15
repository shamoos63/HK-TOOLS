import 'platform_type.dart';

/// One board configuration of a device (a single identifier can ship with
/// several boards, e.g. different modems).
class BoardConfig {
  const BoardConfig({
    required this.boardConfig,
    this.platform,
    this.cpid,
    this.bdid,
  });

  final String boardConfig;

  /// SoC platform string from the API (e.g. `t8101`), not [PlatformType].
  final String? platform;
  final int? cpid;
  final int? bdid;

  factory BoardConfig.fromJson(Map<String, dynamic> json) => BoardConfig(
    boardConfig: json['boardconfig'] as String? ?? '',
    platform: json['platform'] as String?,
    cpid: (json['cpid'] as num?)?.toInt(),
    bdid: (json['bdid'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'boardconfig': boardConfig,
    'platform': platform,
    'cpid': cpid,
    'bdid': bdid,
  };
}

/// A piece of Apple hardware, keyed by its internal identifier.
class Device {
  const Device({
    required this.identifier,
    required this.name,
    required this.platform,
    this.boards = const [],
    this.modelNumbers = const [],
  });

  /// Internal identifier, e.g. `iPhone13,2` or `Mac14,2`.
  final String identifier;

  /// Commercial name, e.g. `iPhone 12` or `MacBook Air (M2, 2022)`.
  final String name;
  final PlatformType platform;
  final List<BoardConfig> boards;

  /// Marketing model numbers (`A2403`, `A2172`, ...). Not part of `/devices`;
  /// enriched separately so search by model number works.
  final List<String> modelNumbers;

  factory Device.fromJson(Map<String, dynamic> json) {
    final identifier = json['identifier'] as String;
    final rawBoards = json['boards'];
    final boards = rawBoards is List
        ? rawBoards
              .whereType<Map<String, dynamic>>()
              .map(BoardConfig.fromJson)
              .toList()
        // Older API shape: board fields live on the device itself.
        : json['boardconfig'] != null
        ? [BoardConfig.fromJson(json)]
        : const <BoardConfig>[];
    return Device(
      identifier: identifier,
      name: json['name'] as String? ?? identifier,
      platform: json['platformType'] is String
          ? PlatformType.fromName(json['platformType'] as String)
          : PlatformType.fromIdentifier(identifier),
      boards: boards,
      modelNumbers: (json['modelNumbers'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'identifier': identifier,
    'name': name,
    'platformType': platform.name,
    'boards': boards.map((b) => b.toJson()).toList(),
    'modelNumbers': modelNumbers,
  };

  Device copyWith({List<String>? modelNumbers}) => Device(
    identifier: identifier,
    name: name,
    platform: platform,
    boards: boards,
    modelNumbers: modelNumbers ?? this.modelNumbers,
  );

  @override
  bool operator ==(Object other) =>
      other is Device && other.identifier == identifier;

  @override
  int get hashCode => identifier.hashCode;

  @override
  String toString() => 'Device($identifier, $name)';
}
