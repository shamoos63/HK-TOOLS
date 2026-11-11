import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/platform_type.dart';
import 'core_providers.dart';
import '../../core/l10n/l10n.dart';

/// Sidebar groups, in display order.
enum SectionGroup {
  device('Device'),
  firmware('Firmware'),
  apps('Apps'),
  app('');

  const SectionGroup(this._label);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);
}

/// App sections in sidebar order. The connected device comes first: it is
/// what the app opens on.
enum AppSection {
  devices('My Device', Icons.phone_iphone_rounded, SectionGroup.device),
  whatsapp('WhatsApp', Icons.chat_rounded, SectionGroup.device),
  library('IPSW Library', Icons.grid_view_rounded, SectionGroup.firmware),
  queue('Downloads', Icons.downloading_rounded, SectionGroup.firmware),
  repository('Repository', Icons.storage_rounded, SectionGroup.firmware),
  appStore('App Store', Icons.storefront_rounded, SectionGroup.apps),
  ipaLibrary('IPA Library', Icons.inventory_2_rounded, SectionGroup.apps),
  settings('Settings', Icons.tune_rounded, SectionGroup.app);

  const AppSection(this._label, this.icon, this.group);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);
  final IconData icon;
  final SectionGroup group;
}

/// Dev launch options, e.g. `--dart-define=HK_START_SECTION=repository`
/// `--dart-define=HK_START_SEARCH="is:signed platform:ios"` (screenshots, QA).
const _startSection = String.fromEnvironment('HK_START_SECTION');
const startSearch = String.fromEnvironment('HK_START_SEARCH');

final sectionProvider =
    NotifierProvider<ValueController<AppSection>, AppSection>(
      () => ValueController(
        AppSection.values.where((s) => s.name == _startSection).firstOrNull ??
            AppSection.devices,
      ),
    );

final libraryCategoryProvider =
    NotifierProvider<ValueController<LibraryCategory>, LibraryCategory>(
      () => ValueController(LibraryCategory.iPhone),
    );

final selectedDeviceProvider =
    NotifierProvider<ValueController<String?>, String?>(
      () => ValueController(null),
    );

final signedOnlyProvider = NotifierProvider<ValueController<bool>, bool>(
  () => ValueController(false),
);

/// Payload keys ticked in the catalog for bulk queuing.
class SelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) =>
      state = state.contains(key) ? ({...state}..remove(key)) : {...state, key};

  void addAll(Iterable<String> keys) => state = {...state, ...keys};

  void clear() => state = const {};
}

final selectionProvider = NotifierProvider<SelectionController, Set<String>>(
  SelectionController.new,
);

enum QueueFilter { all, active, queued, paused, completed, failed }

final queueFilterProvider =
    NotifierProvider<ValueController<QueueFilter>, QueueFilter>(
      () => ValueController(QueueFilter.all),
    );

/// Version facets ticked on the search page (empty = all versions).
final versionFacetProvider =
    NotifierProvider<ValueController<Set<String>>, Set<String>>(
      () => ValueController(const {}),
    );
