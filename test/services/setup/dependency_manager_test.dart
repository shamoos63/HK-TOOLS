import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/device/device_parsers.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:hk_ipsw_manager/services/setup/dependency_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('hk_dep_t_'));
  tearDown(() => tmp.delete(recursive: true));

  /// A tar.gz shaped like the ipatool Windows release.
  Future<List<int>> fakeArchive() async {
    final src = Directory(p.join(tmp.path, 'src', 'bin'))
      ..createSync(recursive: true);
    File(p.join(src.path, 'ipatool-2.7.0-windows-amd64.exe'))
        .writeAsStringSync('MZ fake');
    File(p.join(src.path, 'README.md')).writeAsStringSync('docs');
    final out = p.join(tmp.path, 'ipatool.tar.gz');
    final r = await Process.run('tar', [
      '-czf',
      out,
      '-C',
      p.join(tmp.path, 'src'),
      'bin',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return File(out).readAsBytesSync();
  }

  test('download is verified, unpacked, flattened and renamed', () async {
    final bytes = await fakeArchive();
    final install = p.join(tmp.path, 'tools');
    final mgr = DependencyManager(
      tools: DeviceToolchain(),
      installDirectory: install,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    final statuses = <String>[];
    await mgr.downloadAndExtract(
      PinnedDownload(
        'https://example.test/ipatool.tar.gz',
        sha256.convert(bytes).toString(),
      ),
      (s, _) => statuses.add(s),
      renameExe: (n) => n.startsWith('ipatool') ? 'ipatool.exe' : null,
    );
    expect(File(p.join(install, 'ipatool.exe')).readAsStringSync(), 'MZ fake');
    expect(File(p.join(install, 'README.md')).existsSync(), isFalse);
    expect(statuses.first, startsWith('Downloading'));
  }, skip: Platform.isWindows ? 'uses POSIX tar to build the fixture' : false);

  test('checksum mismatch installs nothing', () async {
    final bytes = await fakeArchive();
    final install = p.join(tmp.path, 'tools');
    final mgr = DependencyManager(
      tools: DeviceToolchain(),
      installDirectory: install,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    await expectLater(
      mgr.downloadAndExtract(
        PinnedDownload('https://example.test/x.tar.gz', 'ab' * 32),
        (_, _) {},
      ),
      throwsA(
        isA<DependencyInstallException>().having(
          (e) => e.message,
          'm',
          contains('Checksum mismatch'),
        ),
      ),
    );
    expect(Directory(install).existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'uses POSIX tar to build the fixture' : false);

  test('HTTP errors are reported', () async {
    final mgr = DependencyManager(
      tools: DeviceToolchain(),
      installDirectory: p.join(tmp.path, 'tools'),
      client: MockClient((_) async => http.Response('nope', 404)),
    );
    await expectLater(
      mgr.downloadAndExtract(
        const PinnedDownload('https://example.test/a.zip', '00'),
        (_, _) {},
      ),
      throwsA(
        isA<DependencyInstallException>().having(
          (e) => e.message,
          'm',
          contains('404'),
        ),
      ),
    );
  });

  test('pinned downloads carry SHA-256 hashes', () {
    for (final d in [
      Downloads.windowsDeviceTools,
      Downloads.ipatoolWindowsX64,
      Downloads.ipatoolWindowsArm64,
      Downloads.uvWindowsX64,
      Downloads.uvWindowsArm64,
      Downloads.uvMacArm64,
      Downloads.uvMacX64,
    ]) {
      expect(d.url, startsWith('https://github.com/'));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(d.sha256),
        isTrue,
        reason: d.url,
      );
    }
  });

  test('required dependencies are the USB stack and core tools', () {
    expect(Dependency.values.where((d) => d.required), [
      Dependency.appleDeviceSupport,
      Dependency.deviceTools,
    ]);
  });

  test('pymobiledevice3 app list JSON', () {
    final apps = DeviceParsers.appsFromJson('''
{
    "com.example.zed": {"CFBundleDisplayName": "Zed", "ApplicationType": "User",
        "CFBundleShortVersionString": "2.0", "StaticDiskUsage": 100},
    "net.whatsapp.WhatsApp": {"CFBundleName": "WhatsApp", "ApplicationType": "User"}
}''');
    expect(apps.map((a) => a.displayName), ['WhatsApp', 'Zed']);
    expect(apps.last.version, '2.0');
    expect(apps.last.bundleId, 'com.example.zed');
  });
}
