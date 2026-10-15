import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../domain/entities/app_settings.dart';

class SettingsStore {
  SettingsStore(this._box, {required this.defaultTargetDirectory});

  static const boxName = 'settings_v1';

  final Box<String> _box;
  final String defaultTargetDirectory;

  AppSettings load() {
    final raw = _box.get('app');
    if (raw == null) {
      return AppSettings(targetDirectory: defaultTargetDirectory);
    }
    try {
      return AppSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        fallbackTarget: defaultTargetDirectory,
      );
    } catch (_) {
      return AppSettings(targetDirectory: defaultTargetDirectory);
    }
  }

  Future<void> save(AppSettings settings) =>
      _box.put('app', jsonEncode(settings.toJson()));
}
