import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/domain/entities/device.dart';
import 'package:hk_ipsw_manager/domain/entities/ipsw_release.dart';
import 'package:hk_ipsw_manager/domain/entities/platform_type.dart';
import 'package:hk_ipsw_manager/services/catalog/catalog_index.dart';
import 'package:hk_ipsw_manager/services/catalog/search_query.dart';

Device _device(String id, String name, {String? soc}) => Device(
  identifier: id,
  name: name,
  platform: PlatformType.fromIdentifier(id),
  boards: [BoardConfig(boardConfig: '${id}ap', platform: soc)],
);

IpswRelease _fw(
  String id,
  String version,
  String build,
  String sha, {
  bool signed = true,
}) => IpswRelease(
  identifier: id,
  version: version,
  buildId: build,
  url: 'https://updates.cdn-apple.com/x/$sha.ipsw',
  fileSize: 1000,
  signed: signed,
  sha1sum: sha,
);

void main() {
  group('SearchQuery.parse', () {
    test('filter tags', () {
      final q = SearchQuery.parse('is:signed platform:macos chip:m-series');
      expect(q.signed, isTrue);
      expect(q.platforms, {PlatformType.macOS});
      expect(q.chip, 'm-series');
      expect(q.terms, isEmpty);
    });

    test('natural OS + version phrases', () {
      final q = SearchQuery.parse('iOS 18.0.1');
      expect(q.platforms, {PlatformType.iOS});
      expect(q.version, '18.0.1');
      expect(SearchQuery.parse('macOS 15').version, '15');
      final sequoia = SearchQuery.parse('macOS Sequoia 15.0.1');
      expect(sequoia.version, '15.0.1');
      expect(sequoia.terms, isEmpty);
    });

    test('builds, model numbers and identifiers', () {
      expect(SearchQuery.parse('22A3354').build, '22a3354');
      expect(SearchQuery.parse('a2442').modelNumbers, ['A2442']);
      expect(SearchQuery.parse('Mac13,2').terms, ['mac13,2']);
      expect(SearchQuery.parse('iPhone 15 Pro').terms, ['iphone', '15', 'pro']);
    });

    test('version prefix matches by component', () {
      final q = SearchQuery.parse('version:18.0');
      expect(q.matchesVersion('18.0'), isTrue);
      expect(q.matchesVersion('18.0.1'), isTrue);
      expect(q.matchesVersion('18.01'), isFalse);
    });
  });

  group('CatalogIndex', () {
    final index = CatalogIndex(
      devices: [
        _device('iPhone13,2', 'iPhone 12'),
        _device('iPhone13,3', 'iPhone 12 Pro'),
        _device('iPhone15,4', 'iPhone 15'),
        _device('iPhone16,1', 'iPhone 15 Pro'),
        _device('Mac14,2', 'MacBook Air (M2, 2022)', soc: 't8112'),
        _device('Mac13,2', 'Mac Studio (2022)', soc: 't6002'),
        _device('iPad14,1', 'iPad mini (6th generation)'),
      ],
      firmwares: {
        'iPhone13,2': [
          _fw('iPhone13,2', '18.0.1', '22A3370', 'aa'),
          _fw('iPhone13,2', '15.0', '19A346', 'old', signed: false),
        ],
        'iPhone13,3': [
          _fw('iPhone13,3', '18.0.1', '22A3370', 'aa'),
          _fw('iPhone13,3', '15.0', '19A346', 'old', signed: false),
        ],
        'iPhone15,4': [_fw('iPhone15,4', '18.0.1', '22A3370', 'bb')],
        'iPhone16,1': [_fw('iPhone16,1', '18.0.1', '22A3370', 'cc')],
        'Mac14,2': [_fw('Mac14,2', '15.0.1', '24A348', 'mac')],
        'Mac13,2': [_fw('Mac13,2', '15.0.1', '24A348', 'mac')],
        'iPad14,1': [_fw('iPad14,1', '18.0.1', '22A3370', 'pad')],
      },
    );

    test('shared payloads are deduplicated', () {
      final groups = index.groupsForDevice('iPhone13,2');
      expect(groups.first.deviceIdentifiers, ['iPhone13,2', 'iPhone13,3']);
      expect(index.groupFor('sha1:mac')!.deviceIdentifiers, [
        'Mac14,2',
        'Mac13,2',
      ]);
    });

    test('version bulk query returns one group per payload', () {
      final r = index.search(SearchQuery.parse('iOS 18.0.1'));
      expect(r.groups.map((g) => g.payloadKey).toSet(), {
        'sha1:aa',
        'sha1:bb',
        'sha1:cc',
      });
      expect(r.deviceCount, 4);
      expect(
        index.search(SearchQuery.parse('is:signed 18.0.1')).signedGroups,
        hasLength(4),
      );
    });

    test('model number in a name never matches an OS version', () {
      final r = index.search(SearchQuery.parse('iPhone 15 Pro'));
      expect(r.groups.single.payloadKey, 'sha1:cc');
      final r15 = index.search(SearchQuery.parse('iPhone 15'));
      expect(r15.groups.map((g) => g.payloadKey).toSet(), {
        'sha1:bb',
        'sha1:cc',
      });
    });

    test('identifier, build, chip and resolved model numbers', () {
      expect(
        index.search(SearchQuery.parse('Mac13,2')).groups.single.payloadKey,
        'sha1:mac',
      );
      expect(
        index.search(SearchQuery.parse('19A346')).groups.single.payloadKey,
        'sha1:old',
      );
      final silicon = index.search(SearchQuery.parse('chip:m-series'));
      expect(silicon.groups.single.deviceIdentifiers, hasLength(2));
      final model = index.search(
        SearchQuery.parse('A2403'),
        resolvedModels: {'A2403': 'iPhone13,2'},
      );
      expect(model.deviceCount, 1);
      expect(model.groups, hasLength(2));
    });

    test('devices sort newest first within a family', () {
      final phones = index
          .devicesIn(LibraryCategory.iPhone)
          .map((d) => d.identifier);
      expect(phones.first, 'iPhone16,1');
    });
  });

  test('version facets split a signed result so one OS version can be bulk-selected', () {
    IpswGroup g(String id, String v, String sha) =>
        IpswGroup(_fw(id, v, 'B', sha), [id]);
    final groups = [
      g('iPhone17,1', '27.0.1', 'a'),
      g('iPhone16,1', '27.0.1', 'b'),
      g('iPhone8,1', '15.8.8', 'c'),
      g('iPhone17,1', '27.0', 'd'),
      g('iPad14,1', '27.0.1', 'e'),
    ];
    final facets = VersionFacet.of(groups);
    expect(facets.map((f) => f.label), [
      'iOS 27.0.1',
      'iOS 27.0',
      'iOS 15.8.8',
      'iPadOS 27.0.1',
    ]);
    expect(facets.first.payloads, 2);
    expect(facets.first.bytes, 2000);
    expect(VersionFacet.latestKeys(facets), {'iOS:27.0.1', 'iPadOS:27.0.1'});
    final only = groups.where((x) => VersionFacet.keyOf(x) == 'iOS:27.0.1');
    expect(only.map((x) => x.payloadKey), ['sha1:a', 'sha1:b']);
  });
}
