import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/branding.dart';
import 'core/l10n/l10n.dart';
import 'domain/entities/app_settings.dart';
import 'core/theme/hud_theme.dart';
import 'data/cache/catalog_cache.dart';
import 'data/cache/scan_cache.dart';
import 'data/repositories/settings_store.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/providers/repository_providers.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/shell/window_chrome.dart';
import 'presentation/widgets/hud_widgets.dart';
import 'presentation/widgets/ui_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // flutter_acrylic: native window effects (macOS / Windows).
  if (Platform.isMacOS || Platform.isWindows) await Window.initialize();
  if (Platform.isMacOS) {
    // Window buttons sit inside the translucent sidebar (no title strip).
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.hideTitle();
  }
  // Windows: hide the system title bar; the app draws its own buttons.
  await initWindowChrome();
  final support = (await getApplicationSupportDirectory()).path;
  Hive.init(p.join(support, 'hive'));

  final Box<String> catalogBox;
  final Box<String> settingsBox;
  final Box<String> scanBox;
  try {
    catalogBox = await Hive.openBox<String>(CatalogCache.boxName);
    settingsBox = await Hive.openBox<String>(SettingsStore.boxName);
    scanBox = await Hive.openBox<String>(ScanCache.boxName);
  } on Object catch (e) {
    // A second copy of the app can't open the data files the first one holds
    // locked; without this the window would just stay black.
    await Hive.close();
    runApp(StartupProblemApp(alreadyRunning: isLockError(e), error: e));
    return;
  }
  final downloads = await getDownloadsDirectory();
  final defaultTarget = p.join(downloads?.path ?? support, 'HK Tools', 'IPSW');

  runApp(
    ProviderScope(
      overrides: [
        appSupportDirProvider.overrideWithValue(support),
        downloadsDirProvider.overrideWithValue(downloads?.path ?? support),
        catalogBoxProvider.overrideWithValue(catalogBox),
        scanBoxProvider.overrideWithValue(scanBox),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(settingsBox, defaultTargetDirectory: defaultTarget),
        ),
      ],
      child: HkIpswManagerApp(),
    ),
  );
}

/// `true` for the file-lock failure Hive reports when another copy of the
/// app already has its data files open.
bool isLockError(Object e) =>
    e is FileSystemException &&
    (e.message.contains('lock failed') ||
        e.osError?.errorCode == 35 || // EAGAIN (macOS)
        e.osError?.errorCode == 11 || // EAGAIN (Linux)
        e.osError?.errorCode == 33); // ERROR_LOCK_VIOLATION (Windows)

/// Shown instead of a blank window when the app can't start.
class StartupProblemApp extends StatelessWidget {
  const StartupProblemApp({
    super.key,
    required this.alreadyRunning,
    required this.error,
  });

  final bool alreadyRunning;
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: Branding.appName,
    debugShowCheckedModeBanner: false,
    theme: HudTheme.dark(),
    home: Scaffold(
      body: HudBackground(
        child: Stack(
          children: [
            Positioned.fill(child: WindowDragArea(child: SizedBox.expand())),
            if (useCustomWindowChrome)
              Positioned(top: 0, right: 0, child: WindowControls()),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480),
                child: GlassPanel(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        alreadyRunning
                            ? Icons.open_in_new_rounded
                            : Icons.error_outline_rounded,
                        size: 44,
                        color: alreadyRunning
                            ? HudColors.cyan
                            : HudColors.danger,
                      ),
                      SizedBox(height: 14),
                      Text(
                        alreadyRunning
                            ? '${Branding.appName} is already running'
                            : '${Branding.appName} could not start',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 10),
                      SelectableText(
                        alreadyRunning
                            ? trf(
                                'Another {0} window is open (check the Dock / taskbar). Only one copy can run at a time because they share the same settings and downloads.',
                                [Branding.appName],
                              )
                            : '$error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 18),
                      NeonButton(
                        label: tr('Quit'),
                        icon: Icons.close_rounded,
                        onPressed: () => exit(0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Follows the computer's light/dark mode and language unless Settings
/// picks one, and switches live when either changes.
class HkIpswManagerApp extends ConsumerStatefulWidget {
  const HkIpswManagerApp({super.key});

  @override
  ConsumerState<HkIpswManagerApp> createState() => _HkIpswManagerAppState();
}

class _HkIpswManagerAppState extends ConsumerState<HkIpswManagerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply(ref.read(settingsProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _refresh();

  @override
  void didChangeLocales(List<Locale>? locales) => _refresh();

  void _refresh() {
    if (_apply(ref.read(settingsProvider)) && mounted) {
      // Colours and strings are read straight from HudColors / tr(), so
      // every widget has to rebuild, not only the ones that watch Theme.
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
      setState(() {});
    }
  }

  /// Sets the palette and language; `true` when either changed.
  static bool _firstApply = true;

  static bool _apply(AppSettings s) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    // QA: --dart-define=HK_APPEARANCE=light|dark, HK_LANGUAGE=arabic|english
    final appearance =
        AppearanceMode.values
            .where(
              (m) => m.name == const String.fromEnvironment('HK_APPEARANCE'),
            )
            .firstOrNull ??
        s.appearance;
    final language =
        AppLanguage.values
            .where((m) => m.name == const String.fromEnvironment('HK_LANGUAGE'))
            .firstOrNull ??
        s.language;
    final light = switch (appearance) {
      AppearanceMode.light => true,
      AppearanceMode.dark => false,
      AppearanceMode.system =>
        dispatcher.platformBrightness == Brightness.light,
    };
    final arabic = switch (language) {
      AppLanguage.arabic => true,
      AppLanguage.english => false,
      AppLanguage.system => L10n.systemPrefersArabic,
    };
    final palette = light ? HudPalette.light : HudPalette.dark;
    // Native translucent sidebar (macOS sidebar material, Windows 11 Mica)
    // unless "Reduced visual effects" is on.
    final glass =
        (Platform.isMacOS || Platform.isWindows) && !s.effectiveReducedEffects;
    final glassChanged =
        glass != HudColors.translucent || (glass && light != HudColors.isLight);
    HudColors.translucent = glass;
    if (glassChanged || _firstApply) {
      _firstApply = false;
      unawaited(applyWindowEffect(glass: glass, dark: !light));
    }
    if (Platform.isMacOS) {
      // Native title bar follows the app's choice (system = follow macOS).
      const MethodChannel('hk_tools/window')
          .invokeMethod<void>(
            'setAppearance',
            appearance == AppearanceMode.system
                ? 'system'
                : (light ? 'light' : 'dark'),
          )
          .catchError((_) {});
    }
    final changed =
        palette != HudColors.current || arabic != L10n.arabic || glassChanged;
    HudColors.current = palette;
    L10n.arabic = arabic;
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select(
        (s) => (s.appearance, s.language, s.effectiveReducedEffects),
      ),
      (_, _) => _refresh(),
    );
    final scale = ref.watch(settingsProvider.select((s) => s.effectiveUiScale));
    final reduced = ref.watch(
      settingsProvider.select((s) => s.effectiveReducedEffects),
    );
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      theme: HudTheme.build(HudColors.current),
      locale: L10n.locale,
      supportedLocales: [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Wraps the Navigator too, so dialogs and snackbars scale with the app.
      builder: (context, child) => HudEffects(
        reduced: reduced,
        child: UiScale(scale: scale, child: child!),
      ),
      home: const AppShell(),
    );
  }
}
