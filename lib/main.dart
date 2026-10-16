import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/branding.dart';
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
      child: const HkIpswManagerApp(),
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
            const Positioned.fill(
              child: WindowDragArea(child: SizedBox.expand()),
            ),
            if (useCustomWindowChrome)
              const Positioned(top: 0, right: 0, child: WindowControls()),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GlassPanel(
                  padding: const EdgeInsets.all(24),
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
                      const SizedBox(height: 14),
                      Text(
                        alreadyRunning
                            ? '${Branding.appName} is already running'
                            : '${Branding.appName} could not start',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        alreadyRunning
                            ? 'Another ${Branding.appName} window is open (check the Dock / '
                                  'taskbar). Only one copy can run at a time because they '
                                  'share the same settings and downloads.'
                            : '$error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      NeonButton(
                        label: 'Quit',
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

class HkIpswManagerApp extends ConsumerWidget {
  const HkIpswManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.effectiveUiScale));
    final reduced = ref.watch(
      settingsProvider.select((s) => s.effectiveReducedEffects),
    );
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      theme: HudTheme.dark(),
      // Wraps the Navigator too, so dialogs and snackbars scale with the app.
      builder: (context, child) => HudEffects(
        reduced: reduced,
        child: UiScale(scale: scale, child: child!),
      ),
      home: const AppShell(),
    );
  }
}
