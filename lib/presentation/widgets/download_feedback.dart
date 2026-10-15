import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hud_theme.dart';
import '../../core/utils/folder_access.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/ipsw_release.dart';
import '../providers/download_providers.dart';
import '../providers/ui_providers.dart';

/// Queues IPSW downloads; when the download folder is unusable (drive
/// unplugged, no permission) shows why, with a shortcut to Settings, and
/// returns `null`.
Future<List<DownloadTask>?> queueIpswDownloads(
  BuildContext context,
  WidgetRef ref,
  Iterable<IpswGroup> groups,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await ref.read(downloadActionsProvider).queue(groups);
  } on FolderAccessException catch (e) {
    showFolderError(messenger, ref, e.message);
    return null;
  }
}

void showFolderError(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  String message,
) => messenger.showSnackBar(
  SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 8),
    backgroundColor: HudColors.danger.withValues(alpha: 0.9),
    action: SnackBarAction(
      label: 'SETTINGS',
      textColor: Colors.white,
      onPressed: () =>
          ref.read(sectionProvider.notifier).set(AppSection.settings),
    ),
  ),
);
