import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/core/utils/plist.dart';
import 'package:hk_ipsw_manager/services/appstore/ipa_library.dart';
import 'package:path/path.dart' as p;

// Generated with Python's plistlib (FMT_BINARY) and zipfile.
const _bplist =
    'YnBsaXN0MDDYAQIDBAUGBwgJCgsMDQ4PEFNCaWdfEBNDRkJ1bmRsZURpc3BsYXlOYW1lXxAS'
    'Q0ZCdW5kbGVJZGVudGlmaWVyXxAaQ0ZCdW5kbGVTaG9ydFZlcnNpb25TdHJpbmdfEA9DRkJ1'
    'bmRsZVZlcnNpb25fEBJMU1JlcXVpcmVzSVBob25lT1NfEBBNaW5pbXVtT1NWZXJzaW9uXlVJ'
    'RGV2aWNlRmFtaWx5EwAAAR9x+wTLaABEAOkAbQBvACAAQQBwAHBfEBBjb20uZXhhbXBsZS5k'
    'ZW1vVTEuMi4zUjQ1CVQxNS4wohESEAEQAggZHTNIZXeMn663yNvh5OXq7e8AAAAAAAABAQAA'
    'AAAAAAATAAAAAAAAAAAAAAAAAAAA8Q==';

const _ipa =
    'UEsDBBQAAAAIABRdT102Y411BgAAAEAAAAAVAAAAUGF5bG9hZC9EZW1vLmFwcC9EZW1vY2CgDAAA'
    'UEsDBBQAAAAIABRdT13tNuSt9AAAACQBAAAbAAAAUGF5bG9hZC9EZW1vLmFwcC9JbmZvLnBsaXN0'
    'SyrIySwuMTC4wcjEzMLKxs7BycXNw8vHLxDslJkeLyDs7OZUmpeSk+qSWVyQk1jpl5ibGi8gBBP1'
    'TEnNK8lMy0wtiheQggkGZ+QXlYSlFhVn5ucFlxRl5gHN4YdJQsWBZvgEB6UWlmYWpRZ7BmTk56X6'
    'B8cLCPhm5mXmlub6B0PVxYV6uqSWZSanuiXmZuZUCjMwMMoX/mY5ncHgwvCSIZchn0GBwZGhgKEA'
    'qDc5P1cvtSIxtyAnVS8lNTc/1FDPSM84yMSUM8TQVM9gkaCQAKMAE4ekrLFHannP/HXbT9x++OTp'
    'q7fvGcCAkRFCMwgzoIKPAFBLAwQUAAAACAAUXU9dloSpM/sAAACOAQAAFAAAAGlUdW5lc01ldGFk'
    'YXRhLnBsaXN0bZBLb4MwEITP5Ve4vuMtSR9R5ThqA5WQUIoEqdQjxVZiFdvIuCX59zUhfUU5ejzz'
    '7ezSxU416FPYTho9xxG5wkjo2nCpN3O8Lp/CGV6wgF7Gz8vyNU9Q28jOoXz9mKVLhEOAh7ZtBEBc'
    'xijP0qJEngGQrDDCW+fae4C+70k1uEht1GDsILemFdbtMw8LfYBwx7EfM9L/1fEql7VjwQV9F3tW'
    'Wectq0oJCsPby52zvi1LdpXyQ1Cqa0LhKB5Tbx+aN6LYGuteRnhx+D9lRGRCpqdh6YRK+Y9Vaic2'
    'wrJoMr2+ub2j8C38sZ/rFwtlkL/WL57CuBmFw94s+AJQSwECFAMUAAAACAAUXU9dNmONdQYAAABA'
    'AAAAFQAAAAAAAAAAAAAAgAEAAAAAUGF5bG9hZC9EZW1vLmFwcC9EZW1vUEsBAhQDFAAAAAgAFF1P'
    'Xe025K30AAAAJAEAABsAAAAAAAAAAAAAAIABOQAAAFBheWxvYWQvRGVtby5hcHAvSW5mby5wbGlz'
    'dFBLAQIUAxQAAAAIABRdT12WhKkz+wAAAI4BAAAUAAAAAAAAAAAAAACAAWYBAABpVHVuZXNNZXRh'
    'ZGF0YS5wbGlzdFBLBQYAAAAAAwADAM4AAACTAgAAAAA=';

void main() {
  test('binary plist decodes strings, unicode, ints, bools, arrays', () {
    final v = parsePlistBytes(base64.decode(_bplist)) as Map<String, Object?>;
    expect(v['CFBundleIdentifier'], 'com.example.demo');
    expect(v['CFBundleDisplayName'], 'Démo App');
    expect(v['CFBundleShortVersionString'], '1.2.3');
    expect(v['LSRequiresIPhoneOS'], isTrue);
    expect(v['UIDeviceFamily'], [1, 2]);
    expect(v['Big'], 1234567890123);
  });

  group('library', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('hk_ipa_'));
    tearDown(() => dir.delete(recursive: true));

    test('reads Info.plist and iTunesMetadata from an IPA', () async {
      final f = File(p.join(dir.path, 'demo.ipa'))
        ..writeAsBytesSync(base64.decode(_ipa));
      final info = await IpaReader.read(f.path);
      expect(info.error, isNull);
      expect(info.bundleId, 'com.example.demo');
      expect(info.name, 'Démo App');
      expect(info.version, '1.2.3');
      expect(info.build, '45');
      expect(info.minimumOs, '15.0');
      expect(info.itemId, 1234567);
      expect(info.artist, 'Example Inc.');
    });

    test(
      'scanner finds nested IPAs, flags junk, caches, honours depth',
      () async {
        final bytes = base64.decode(_ipa);
        File(p.join(dir.path, 'a.ipa')).writeAsBytesSync(bytes);
        Directory(p.join(dir.path, 'sub', 'deeper'))
            .createSync(recursive: true);
        File(p.join(dir.path, 'sub', 'deeper', 'b.ipa'))
            .writeAsBytesSync(bytes);
        File(p.join(dir.path, 'broken.ipa')).writeAsStringSync('not a zip');
        final tooDeep = Directory(p.join(dir.path, '1', '2', '3', '4'))
          ..createSync(recursive: true);
        File(p.join(tooDeep.path, 'c.ipa')).writeAsBytesSync(bytes);

        final cache = p.join(dir.path, '.cache', 'lib.json');
        final scanner = IpaLibraryScanner(cacheFile: cache);
        final first = await scanner.scan(dir.path);
        expect(first.where((i) => i.readable).length, 2);
        expect(
          first.singleWhere((i) => !i.readable).path,
          endsWith('broken.ipa'),
        );
        expect(File(cache).existsSync(), isTrue);

        final again = await scanner.scan(dir.path);
        expect(
          again.map((i) => i.path).toSet(),
          first.map((i) => i.path).toSet(),
        );
      },
    );
  });

  test('store lookup parse and version comparison', () {
    final l = StoreLookup.parse(
      jsonEncode({
        'resultCount': 1,
        'results': [
          {
            'bundleId': 'com.xvpn',
            'trackId': 1250312807,
            'version': '43.3.4',
            'trackName': 'X-VPN',
            'price': 0,
            'fileSizeBytes': '123456',
            'currentVersionReleaseDate': '2026-10-01T07:00:00Z',
          },
        ],
      }),
    );
    expect(l['com.xvpn']!.trackId, 1250312807);
    expect(l['com.xvpn']!.fileSize, 123456);
    expect(isNewerVersion('43.3.4', '43.3.3'), isTrue);
    expect(isNewerVersion('43.3.3', '43.3.3'), isFalse);
    expect(isNewerVersion('43.10', '43.9'), isTrue);
    expect(isNewerVersion(null, '1.0'), isFalse);
  });
}
