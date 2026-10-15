import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hk_ipsw_manager/data/cache/scan_cache.dart';
import 'package:hk_ipsw_manager/domain/entities/device.dart';
import 'package:hk_ipsw_manager/domain/entities/ipsw_release.dart';
import 'package:hk_ipsw_manager/domain/entities/platform_type.dart';
import 'package:hk_ipsw_manager/services/catalog/catalog_index.dart';
import 'package:hk_ipsw_manager/services/repository/ipsw_manifest_reader.dart';
import 'package:hk_ipsw_manager/services/repository/repository_actions.dart';
import 'package:hk_ipsw_manager/services/repository/repository_inventory.dart';
import 'package:hk_ipsw_manager/services/repository/repository_scanner.dart';
import 'package:path/path.dart' as p;

import 'fake_ipsw.dart';

Device _device(String id, String name) => Device(
  identifier: id,
  name: name,
  platform: PlatformType.fromIdentifier(id),
);

IpswRelease _fw(
  String id,
  String v,
  String b,
  String sha,
  int size, {
  String? url,
}) => IpswRelease(
  identifier: id,
  version: v,
  buildId: b,
  url: url ?? 'https://cdn/x/$sha.ipsw',
  fileSize: size,
  signed: true,
  sha1sum: sha,
);

Future<String> _sha1(String path) async =>
    (await sha1.bind(File(path).openRead()).first).toString();

void main() {
  late Directory dir;
  late Box<String> box;
  late RepositoryScanner scanner;

  setUpAll(() async {
    final hiveDir = await Directory.systemTemp.createTemp('hk_hive');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hk_repo');
    box = await Hive.openBox<String>(
      'scan_test_${DateTime.now().microsecondsSinceEpoch}',
    );
    scanner = RepositoryScanner(ScanCache(box));
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<List<ScanEntry>> scan() async =>
      (await scanner.scan(dir.path).last).entries!;

  group('IpswManifestReader', () {
    for (final zip64 in [false, true]) {
      test('reads BuildManifest.plist (zip64: $zip64)', () async {
        final f = await writeFakeIpsw(
          p.join(dir.path, 'a.ipsw'),
          version: '27.0.1',
          build: '24A446',
          productTypes: ['iPhone13,2', 'iPhone13,3'],
          zip64: zip64,
        );
        final m = await IpswManifestReader.readFile(f.path);
        expect(m.productVersion, '27.0.1');
        expect(m.buildVersion, '24A446');
        expect(m.supportedProductTypes, ['iPhone13,2', 'iPhone13,3']);
      });
    }

    test('rejects non-zip and truncated files', () async {
      final junk = File(p.join(dir.path, 'junk.ipsw'))
        ..writeAsBytesSync(List.filled(5000, 7));
      expect(
        IpswManifestReader.readFile(junk.path),
        throwsA(isA<ManifestReadException>()),
      );
      final good = await writeFakeIpsw(
        p.join(dir.path, 'g.ipsw'),
        version: '1',
        build: '1A1',
        productTypes: ['iPhone1,1'],
      );
      final bytes = good.readAsBytesSync();
      final cut = File(p.join(dir.path, 'cut.ipsw'))
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 40));
      expect(
        IpswManifestReader.readFile(cut.path),
        throwsA(isA<ManifestReadException>()),
      );
    });
  });

  group('scan → inventory', () {
    late String aPath;
    late String copyPath;
    late String bPath;
    late CatalogIndex index;

    setUp(() async {
      aPath = p.join(
        dir.path,
        'iPhone13,2,iPhone13,3_27.0.1_24A446_Restore.ipsw',
      );
      copyPath = p.join(dir.path, 'old', 'copy of iPhone 12.ipsw');
      bPath = p.join(dir.path, 'iPhone_4.7_15.8.8_19H422_Restore.ipsw');
      await writeFakeIpsw(
        aPath,
        version: '27.0.1',
        build: '24A446',
        productTypes: ['iPhone13,2', 'iPhone13,3'],
      );
      await File(aPath).copy(
        (await Directory(p.dirname(copyPath)).create()).path +
            p.separator +
            p.basename(copyPath),
      );
      await writeFakeIpsw(
        bPath,
        version: '15.8.8',
        build: '19H422',
        productTypes: ['iPhone8,1'],
        zip64: true,
        seed: 9,
      );
      File(p.join(dir.path, 'broken.ipsw'))
          .writeAsBytesSync(List.filled(3000, 1));

      final aSha = await _sha1(aPath);
      final aSize = File(aPath).lengthSync();
      final bSize = File(bPath).lengthSync();
      index = CatalogIndex(
        devices: [
          _device('iPhone13,2', 'iPhone 12'),
          _device('iPhone13,3', 'iPhone 12 Pro'),
          _device('iPhone8,1', 'iPhone 6s'),
          _device('iPad14,1', 'iPad mini (6th generation)'),
        ],
        firmwares: {
          'iPhone13,2': [
            _fw(
              'iPhone13,2',
              '27.0.1',
              '24A446',
              aSha,
              aSize,
              url: 'https://updates.cdn-apple.com/x/iPhone13,2,iPhone13,3_27.0.1_24A446_Restore.ipsw',
            ),
            _fw('iPhone13,2', '27.0', '24A437', 'older', 1),
          ],
          'iPhone13,3': [
            _fw(
              'iPhone13,3',
              '27.0.1',
              '24A446',
              aSha,
              aSize,
              url: 'https://updates.cdn-apple.com/x/iPhone13,2,iPhone13,3_27.0.1_24A446_Restore.ipsw',
            ),
          ],
          // Deliberately wrong published hash for B.
          'iPhone8,1': [
            _fw('iPhone8,1', '15.8.8', '19H422', 'bad0' * 10, bSize),
          ],
          'iPad14,1': [_fw('iPad14,1', '27.0.1', '24A446', 'ipad', 1)],
        },
      );
    });

    test('identifies files, flags duplicates, unreadable files and missing firmware', () async {
      final inv = RepositoryInventory.analyze(dir.path, await scan(), index);
      expect(inv.files, hasLength(4));
      final a = inv.files.firstWhere((f) => f.primary.path == aPath);
      expect(a.method, MatchMethod.manifest);
      expect(a.group!.deviceIdentifiers, ['iPhone13,2', 'iPhone13,3']);
      expect(
        inv.files.where((f) => f.integrity == Integrity.unreadable),
        hasLength(1),
      );
      expect(inv.duplicates.single.files, hasLength(2));
      expect(inv.reclaimableBytes, File(aPath).lengthSync());

      final ios = inv.missingLatest(platforms: {PlatformType.iOS});
      expect(ios.missing, isEmpty);
      expect(ios.upToDate, 3);
      final all = inv.missingLatest();
      expect(all.missing.single.devices, ['iPad14,1']);
      // "Devices in repository" scope ignores the iPad.
      expect(inv.missingLatest(onlyDevicesInRepository: true).missing, isEmpty);
    });

    test('SHA1 results are cached and drive integrity', () async {
      var entries = await scan();
      for (final e in entries.where(
        (e) => e.path == aPath || e.path == bPath,
      )) {
        await scanner.rememberSha1(e, await _sha1(e.path));
      }
      entries = await scan();
      final inv = RepositoryInventory.analyze(dir.path, entries, index);
      expect(
        inv.files.firstWhere((f) => f.primary.path == aPath).integrity,
        Integrity.verified,
      );
      expect(
        inv.files.firstWhere((f) => f.primary.path == bPath).integrity,
        Integrity.mismatch,
      );
      // A file whose payload failed its hash doesn't count as present.
      expect(inv.payloadKeys.any((k) => k.contains('bad0')), isFalse);
    });

    test(
      'reclaim merges duplicates into hardlinks, device links share the file',
      () async {
        var inv = RepositoryInventory.analyze(dir.path, await scan(), index);
        final freed = await RepositoryActions.reclaim(
          inv.duplicates.single,
          (f) => _sha1(f.primary.path),
        );
        expect(freed, File(aPath).lengthSync());

        inv = RepositoryInventory.analyze(dir.path, await scan(), index);
        expect(inv.duplicates, isEmpty);
        final a = inv.files.firstWhere(
          (f) =>
              f.payloadKey == inv.files.first.payloadKey &&
              f.group != null &&
              f.version == '27.0.1',
        );
        expect(a.links.map((l) => l.path).toSet(), {aPath, copyPath});
        expect(File(copyPath).readAsBytesSync(), File(aPath).readAsBytesSync());

        final created = await RepositoryActions.createDeviceLinks(
          folder: dir.path,
          sourcePath: aPath,
          deviceIdentifiers: a.deviceIdentifiers,
          version: a.version,
          buildId: a.buildId,
        );
        expect(created, 2);
        expect(
          File(
            p.join(
              dir.path,
              deviceLinksFolder,
              'iPhone13,3_27.0.1_24A446_Restore.ipsw',
            ),
          ).existsSync(),
          isTrue,
        );
        inv = RepositoryInventory.analyze(dir.path, await scan(), index);
        final linked = inv.files.firstWhere(
          (f) => f.version == '27.0.1' && f.group != null,
        );
        expect(linked.links, hasLength(4));
        expect(linked.deviceLinkCount, 2);
        expect(
          linked.primary.path,
          aPath,
          reason: 'primary path is never a By Device link',
        );
        expect(inv.duplicates, isEmpty);
        // Idempotent.
        expect(
          await RepositoryActions.createDeviceLinks(
            folder: dir.path,
            sourcePath: aPath,
            deviceIdentifiers: a.deviceIdentifiers,
            version: a.version,
            buildId: a.buildId,
          ),
          0,
        );
      },
    );

    test('reclaim refuses to merge files whose hashes differ', () async {
      // Same manifest (so same payload by build), different bytes.
      File(copyPath).deleteSync();
      await writeFakeIpsw(
        copyPath,
        version: '27.0.1',
        build: '24A446',
        productTypes: ['iPhone13,2', 'iPhone13,3'],
        seed: 77,
      );
      final inv = RepositoryInventory.analyze(dir.path, await scan(), index);
      expect(inv.duplicates.single.files, hasLength(2));
      await expectLater(
        RepositoryActions.reclaim(
          inv.duplicates.single,
          (f) => _sha1(f.primary.path),
        ),
        throwsA(anything),
      );
      expect(File(copyPath).existsSync(), isTrue);
    });
  });

  group('permissions', () {
    // chmod-based; Windows ACLs differ.
    final skip = Platform.isWindows ? 'POSIX permissions only' : null;

    test('unreadable subfolders and files are skipped, not fatal', () async {
      await writeFakeIpsw(
        p.join(dir.path, 'ok', 'a.ipsw'),
        version: '1',
        build: '1A1',
        productTypes: ['iPhone1,1'],
      );
      final locked = Directory(p.join(dir.path, 'locked'));
      await writeFakeIpsw(
        p.join(locked.path, 'b.ipsw'),
        version: '1',
        build: '1A2',
        productTypes: ['iPhone1,1'],
      );
      final secret = await writeFakeIpsw(
        p.join(dir.path, 'secret.ipsw'),
        version: '1',
        build: '1A3',
        productTypes: ['iPhone1,1'],
      );
      await Process.run('chmod', ['000', locked.path]);
      await Process.run('chmod', ['000', secret.path]);
      addTearDown(() async {
        await Process.run('chmod', ['755', locked.path]);
        await Process.run('chmod', ['644', secret.path]);
      });

      final last = await scanner.scan(dir.path).last;
      expect(
        last.entries!.map((e) => p.basename(e.path)),
        containsAll(['a.ipsw', 'secret.ipsw']),
      );
      expect(last.skipped, containsAll([locked.path, secret.path]));
      final unreadable = last.entries!.firstWhere((e) => e.path == secret.path);
      expect(unreadable.manifestError, startsWith('Cannot read file'));

      // Once readable, the next scan identifies it (the failure wasn't cached).
      await Process.run('chmod', ['644', secret.path]);
      final again = await scanner.scan(dir.path).last;
      expect(
        again.entries!
            .firstWhere((e) => e.path == secret.path)
            .manifest
            ?.buildVersion,
        '1A3',
      );
    }, skip: skip);

    test(
      'an unreadable repository folder raises RepositoryAccessException',
      () async {
        final root = Directory(p.join(dir.path, 'root'))..createSync();
        await Process.run('chmod', ['000', root.path]);
        addTearDown(() => Process.run('chmod', ['755', root.path]));
        await expectLater(
          scanner.scan(root.path).last,
          throwsA(isA<RepositoryAccessException>()),
        );
      },
      skip: skip,
    );
  });
}
