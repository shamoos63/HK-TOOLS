import 'dart:convert';
import 'dart:io';

import '../device/device_toolchain.dart';

/// A WhatsApp-only backup of an iPhone, the way Dr.Fone makes one (its log:
/// "CustomBackupTask filter dir: /var/mobile/Containers/…", 93 GB received,
/// 24 GB saved).
///
/// The iPhone always streams its whole backup; only WhatsApp's own folders
/// (its app container and its app-group containers, found by bundle id) are
/// written to disk, and `Manifest.db` is trimmed to match. The result is a
/// normal backup folder that every WhatsApp feature here can read, and that
/// can be restored.
///
/// Uses pymobiledevice3 (`backup2 backup --only-regex … --patch-manifest`),
/// which filters by the device-side path of each file.
abstract final class WaIosBackup {
  static const whatsAppBundle = 'net.whatsapp.WhatsApp';
  static const businessBundle = 'net.whatsapp.WhatsAppSMB';

  static const _env = {
    'PYTHONIOENCODING': 'utf-8',
    'PYTHONUTF8': '1',
    'NO_COLOR': '1',
  };

  static bool available(DeviceToolchain tools) =>
      tools.has(DeviceTool.pymobiledevice3);

  /// Device paths of the WhatsApp (or WhatsApp Business) containers on the
  /// iPhone [udid]. Empty when the app isn't installed.
  static Future<List<String>> containers(
    DeviceToolchain tools,
    String udid, {
    required bool business,
  }) async {
    final bundle = business ? businessBundle : whatsAppBundle;
    final r = await tools.run(
      DeviceTool.pymobiledevice3,
      ['apps', 'query', bundle, '--udid', udid],
      timeout: const Duration(minutes: 1),
      environment: _env,
    );
    if (!r.ok) return const [];
    return parseContainers(r.stdout, bundle);
  }

  static List<String> parseContainers(String json, String bundle) {
    final start = json.indexOf('{');
    if (start < 0) return const [];
    final Object? data;
    try {
      data = jsonDecode(json.substring(start));
    } on FormatException {
      return const [];
    }
    if (data is! Map || data[bundle] is! Map) return const [];
    final app = data[bundle] as Map;
    return [
      if (app['Container'] is String) app['Container'] as String,
      if (app['GroupContainers'] is Map)
        for (final e in (app['GroupContainers'] as Map).entries)
          if ('${e.key}'.contains('whatsapp') && e.value is String)
            e.value as String,
    ];
  }

  /// Regex keeping files inside [containers] (matched on the container's
  /// UUID, so `/var/…` and `/private/var/…` both match), plus WhatsApp's
  /// backup domains when a file is reported by domain instead.
  static String filterRegex(List<String> containers, {required bool business}) {
    final ids = [
      for (final c in containers)
        if (RegExp(r'[0-9A-Fa-f-]{36}$').firstMatch(c) case final m?) m[0]!,
    ];
    final domain = business
        ? r'AppDomain(Group)?-(group\.)?net\.whatsapp\.WhatsAppSMB'
        : r'AppDomain(Group)?-(group\.)?net\.whatsapp\.WhatsApp(\.|$|/|-)';
    return [
      if (ids.isNotEmpty) '(${ids.map(RegExp.escape).join('|')})',
      domain,
      if (!business) r'AppDomainGroup-group\.net\.whatsapp\.(family|stickers)',
    ].join('|');
  }

  /// Starts a WhatsApp-only backup of [udid] into `<directory>/<udid>`.
  /// Output lines carry tqdm percentages for the progress bar.
  static Future<Process> start(
    DeviceToolchain tools,
    String udid,
    String directory, {
    required List<String> containers,
    required bool business,
  }) async {
    await Directory(directory).create(recursive: true);
    return tools.start(DeviceTool.pymobiledevice3, [
      'backup2',
      'backup',
      '--full',
      '--only-regex',
      filterRegex(containers, business: business),
      '--patch-manifest',
      '--udid',
      udid,
      directory,
    ], environment: _env);
  }
}
