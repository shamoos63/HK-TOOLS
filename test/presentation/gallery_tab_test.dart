import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hk_ipsw_manager/core/theme/hud_theme.dart';
import 'package:hk_ipsw_manager/domain/entities/app_settings.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/presentation/providers/core_providers.dart';
import 'package:hk_ipsw_manager/presentation/screens/devices/gallery_tab.dart';
import 'package:hk_ipsw_manager/presentation/screens/devices/gallery_viewer.dart';
import 'package:hk_ipsw_manager/presentation/widgets/hud_widgets.dart';

class _Settings extends SettingsController {
  _Settings(this.privacy);

  final bool privacy;

  @override
  AppSettings build() =>
      AppSettings(targetDirectory: '/tmp/fw', galleryPrivacyMode: privacy);
}

const _device = ConnectedDevice(
  id: 'u',
  udid: 'u',
  mode: DeviceMode.normal,
  connection: DeviceConnection.usb,
  pairState: PairState.paired,
);

AfcEntry _item(String album, String name, DateTime date) => AfcEntry(
  name: name,
  path: '/DCIM/$album/$name',
  isDirectory: false,
  size: 1000,
  modified: date,
);

final _items = [
  _item('100APPLE', 'IMG_0001.JPG', DateTime(2025, 3, 1)),
  _item('100APPLE', 'IMG_0002.HEIC', DateTime(2026, 1, 5)),
  _item('101APPLE', 'IMG_0100.MOV', DateTime(2026, 9, 9)),
  _item('101APPLE', 'IMG_0101.JPG', DateTime(2025, 12, 31)),
  _item('101APPLE', 'IMG_0102.PNG', DateTime(2026, 10, 1)),
];

Widget _app({bool privacy = false}) => ProviderScope(
  overrides: [
    appSupportDirProvider.overrideWithValue('/tmp/hk_support'),
    downloadsDirProvider.overrideWithValue('/tmp/hk_downloads'),
    settingsProvider.overrideWith(() => _Settings(privacy)),
    galleryItemsProvider.overrideWith((ref, id) async => _items),
  ],
  child: MaterialApp(
    theme: HudTheme.dark(),
    home: const Scaffold(body: GalleryTab(device: _device)),
  ),
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(944, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 50));
}

List<String> _tileDates(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: find.byType(GridView), matching: find.byType(Text)),
  ))
    t.data!,
];

void main() {
  testWidgets('years, newest-first sort and the 2026 filter', (tester) async {
    await _pump(tester, _app());
    expect(tester.takeException(), isNull);

    expect(find.text('All years 5'), findsOneWidget);
    expect(find.text('2026  3'), findsOneWidget);
    expect(find.text('2025  2'), findsOneWidget);
    expect(find.text('Export all (5)'), findsOneWidget);
    expect(find.textContaining('Import'), findsNothing);
    expect(_tileDates(tester), [
      '2026-10-01',
      '2026-09-09',
      '2026-01-05',
      '2025-12-31',
      '2025-03-01',
    ]);

    await tester.tap(find.text('2026  3'));
    await tester.pump();
    expect(_tileDates(tester), ['2026-10-01', '2026-09-09', '2026-01-05']);
    expect(find.text('Export shown (3)'), findsOneWidget);

    // Album + year combine.
    await tester.tap(find.text('101APPLE'));
    await tester.pump();
    await tester.tap(find.text('2026  2'));
    await tester.pump();
    expect(_tileDates(tester), ['2026-10-01', '2026-09-09']);
  });

  testWidgets('select shown, then export selected', (tester) async {
    await _pump(tester, _app());
    await tester.tap(find.text('2025  2'));
    await tester.pump();
    await tester.tap(find.text('Select shown'));
    await tester.pump();
    expect(find.text('2 selected · 2 shown'), findsOneWidget);
    final btn = tester.widget<NeonButton>(
      find.widgetWithText(NeonButton, 'Export selected (2)'),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('privacy mode shows the blur marker on every tile', (
    tester,
  ) async {
    await _pump(tester, _app(privacy: true));
    expect(find.byIcon(Icons.visibility_off_rounded), findsNWidgets(1 + 5));
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isTrue);
  });

  testWidgets('mouse drag selects every tile under the box', (tester) async {
    await _pump(tester, _app());
    final tiles = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(InkWell),
    );
    final first = tester.getCenter(tiles.at(0));
    final third = tester.getCenter(tiles.at(2));
    final gesture = await tester.startGesture(
      first,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveTo(third);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('3 selected · 5 shown'), findsOneWidget);
  });

  testWidgets('double-click opens the viewer; arrows move; Esc closes', (
    tester,
  ) async {
    await _pump(tester, _app());
    final tile = find
        .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
        .first;
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('1 / 5'), findsOneWidget);
    // Double-click opens; it does not also toggle the selection.
    expect(find.textContaining('selected'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.textContaining('2 / 5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('/ 5'), findsNothing);
  });

  test('HEIC converts to a displayable JPEG with the OS codecs', () async {
    if (!Platform.isMacOS) return;
    final dir = await Directory.systemTemp.createTemp('hk_heic_');
    addTearDown(() => dir.delete(recursive: true));
    final png = p.join(dir.path, 'in.png');
    // 1x1 PNG.
    File(png).writeAsBytesSync(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
      0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final heic = p.join(dir.path, 'photo.heic');
    final made = await Process.run('sips', [
      '-s',
      'format',
      'heic',
      png,
      '--out',
      heic,
    ]);
    if (made.exitCode != 0) return; // HEIC encoder unavailable on this Mac.
    final jpg = p.join(dir.path, 'photo.jpg');
    expect(await GalleryOriginals.convertToJpeg(heic, jpg), isTrue);
    final bytes = File(jpg).readAsBytesSync();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
  });
}
