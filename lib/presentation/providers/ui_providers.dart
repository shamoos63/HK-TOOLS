import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/platform_type.dart';
import 'core_providers.dart';

enum AppSection {
  library('Library', Icons.grid_view_rounded),
  queue('Downloads', Icons.downloading_rounded),
  repository('Repository', Icons.storage_rounded),
  devices('Devices', Icons.phone_iphone_rounded),
  appStore('App Store', Icons.storefront_rounded),
  ipaLibrary('IPA Library', Icons.inventory_2_rounded),
  settings('Settings', Icons.tune_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Dev launch options, e.g. `--dart-define=HK_START_SECTION=repository`
/// `--dart-define=HK_START_SEARCH="is:signed platform:ios"` (screenshots, QA).
const _startSection = String.fromEnvironment('HK_START_SECTION');
const startSearch = String.fromEnvironment('HK_START_SEARCH');

final sectionProvider =
    NotifierProvider<ValueController<AppSection>, AppSection>(
      () => ValueController(
        AppSection.values.where((s) => s.name == _startSection).firstOrNull ??
            AppSection.library,
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
