import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_providers.dart';
import '../providers/download_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/ui_providers.dart';
import '../screens/appstore/app_store_screen.dart';
import '../screens/devices/devices_screen.dart';
import '../screens/ipa_library/ipa_library_screen.dart';
import '../screens/whatsapp/whatsapp_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/repository/repository_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/setup/setup_assistant.dart';
import '../widgets/hud_widgets.dart';
import 'hud_header.dart';
import 'sidebar.dart';
import 'window_chrome.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    // Check for the external device tools once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => runStartupToolCheck(context, ref),
    );
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start the download manager (and resume the persisted queue) at launch.
    ref.watch(downloadManagerProvider);
    // Background repository scan + hardlinks for finished downloads.
    ref.watch(repositoryProvider.select((s) => s.scannedAt));
    ref.watch(postDownloadHookProvider);
    // Device detection runs app-wide so the sidebar badge stays current.
    ref.watch(devicesProvider.select((s) => s.devices.length));
    final section = ref.watch(sectionProvider);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: HudBackground(
            child: Row(
              children: [
                Sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      // Windows: no system title bar. The header doubles as
                      // the drag area and carries the window buttons.
                      Stack(
                        children: [
                          WindowDragBackground(
                            child: HudHeader(searchFocus: _searchFocus),
                          ),
                          if (useCustomWindowChrome)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: WindowControls(),
                            ),
                        ],
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: Offset(0.015, 0),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(section),
                            child: switch (section) {
                              AppSection.library => LibraryScreen(),
                              AppSection.queue => QueueScreen(),
                              AppSection.repository => const RepositoryScreen(),
                              AppSection.devices => const DevicesScreen(),
                              AppSection.appStore => const AppStoreScreen(),
                              AppSection.ipaLibrary => const IpaLibraryScreen(),
                              AppSection.whatsapp => const WhatsAppScreen(),
                              AppSection.settings => const SettingsScreen(),
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
