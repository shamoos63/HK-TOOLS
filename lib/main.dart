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
import 'presentation/widgets/ui_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = (await getApplicationSupportDirectory()).path;
  Hive.init(p.join(support, 'hive'));
  final catalogBox = await Hive.openBox<String>(CatalogCache.boxName);
  final settingsBox = await Hive.openBox<String>(SettingsStore.boxName);
  final scanBox = await Hive.openBox<String>(ScanCache.boxName);
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

class HkIpswManagerApp extends ConsumerWidget {
  const HkIpswManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.effectiveUiScale));
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      theme: HudTheme.dark(),
      // Wraps the Navigator too, so dialogs and snackbars scale with the app.
      builder: (context, child) => UiScale(scale: scale, child: child!),
      home: const AppShell(),
    );
  }
}
