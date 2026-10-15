import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/utils/folder_access.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  test('unplugged drive is named in the message', () async {
    if (!Platform.isMacOS) return;
    const path = '/Volumes/HK_Not_Connected_Drive/Device Data/App Store';
    expect(missingVolume(path), '/Volumes/HK_Not_Connected_Drive');
    expect(missingVolume('/Users/someone/Downloads'), isNull);
    await expectLater(
      ensureWritableDirectory(path),
      throwsA(
        isA<FolderAccessException>().having(
          (e) => e.message,
          'message',
          contains('/Volumes/HK_Not_Connected_Drive is not connected'),
        ),
      ),
    );
  });

  test('permission denied becomes a readable message', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('hk_perm_');
    addTearDown(() async {
      await Process.run('chmod', ['755', root.path]);
      await root.delete(recursive: true);
    });
    await Process.run('chmod', ['555', root.path]);
    await expectLater(
      ensureWritableDirectory(p.join(root.path, 'App Store')),
      throwsA(
        isA<FolderAccessException>().having(
          (e) => e.message,
          'message',
          contains('No permission to write'),
        ),
      ),
    );
  });

  test('writable folder is created and left clean', () async {
    final root = await Directory.systemTemp.createTemp('hk_ok_');
    addTearDown(() => root.delete(recursive: true));
    final target = p.join(root.path, 'a', 'b');
    await ensureWritableDirectory(target);
    expect(Directory(target).existsSync(), isTrue);
    expect(Directory(target).listSync(), isEmpty);
  });

  test('download folder settings round-trip', () {
    const s = AppSettings(
      targetDirectory: '/fw',
      ipaDirectory: '/apps',
      askIpaLocation: true,
    );
    final back = AppSettings.fromJson(s.toJson(), fallbackTarget: '/x');
    expect(back.ipaDirectory, '/apps');
    expect(back.askIpaLocation, isTrue);
    final cleared = back.copyWith(ipaDirectory: () => null);
    expect(cleared.ipaDirectory, isNull);
    expect(
      AppSettings.fromJson(const {}, fallbackTarget: '/x').askIpaLocation,
      isFalse,
    );
  });
}
