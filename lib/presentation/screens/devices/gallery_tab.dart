import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/core_providers.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import 'gallery_viewer.dart';

const _mediaExtensions = {
  '.jpg', '.jpeg', '.png', '.heic', '.heif', '.gif', '.dng', //
  '.mov', '.mp4', '.m4v',
};
const _decodable = {'.jpg', '.jpeg', '.png', '.gif'};

/// Every photo / video in the camera roll (all `/DCIM/<album>` folders).
final galleryItemsProvider = FutureProvider.autoDispose
    .family<List<AfcEntry>, String>((ref, deviceId) async {
      final device = ref.read(devicesProvider).byId(deviceId);
      if (device == null) throw StateError('Device disconnected');
      final svc = ref.watch(deviceServiceProvider);
      final albums = (await svc.listDirectory(
        device,
        '/DCIM',
      )).where((e) => e.isDirectory && !e.name.startsWith('.')).toList();
      final out = <AfcEntry>[];
      for (final a in albums) {
        out.addAll(
          (await svc.listDirectory(device, a.path)).where(
            (e) =>
                !e.isDirectory &&
                _mediaExtensions.contains(p.extension(e.name).toLowerCase()),
          ),
        );
      }
      return out;
    });

enum _Sort {
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name');

  const _Sort(this.label);

  final String label;
}

String _albumOf(AfcEntry e) => p.posix.basename(p.posix.dirname(e.path));

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Camera roll browser over AFC (`/DCIM/<album>/`). Thumbnails come from the
/// Photos thumbnail cache (`/PhotoData/Thumbnails/V2/…/5005.JPG`) when present,
/// so HEIC photos preview without converting them.
///
/// Dates are the files' dates on the device (when the photo or video was
/// saved there), which is what the year filter and sorting use.
class GalleryTab extends ConsumerStatefulWidget {
  const GalleryTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<GalleryTab> {
  /// `null` = all albums.
  String? _album;

  /// `null` = all years.
  int? _year;
  _Sort _sort = _Sort.newest;
  final Set<String> _picked = {};
  String? _busy;
  late final _originals = GalleryOriginals(
    pull: (remote, local) =>
        ref.read(deviceServiceProvider).pull(widget.device, remote, local),
    cacheDir: p.join(
      ref.read(appSupportDirProvider),
      'gallery_cache',
      widget.device.udid ?? widget.device.id,
    ),
  );
  late final _thumbs = _ThumbnailLoader(
    pull: (remote, local) =>
        ref.read(deviceServiceProvider).pull(widget.device, remote, local),
    cacheDir: p.join(
      ref.read(appSupportDirProvider),
      'gallery_cache',
      widget.device.udid ?? widget.device.id,
    ),
  );

  List<AfcEntry> _shown(List<AfcEntry> all) {
    final list = all
        .where(
          (e) =>
              (_album == null || _albumOf(e) == _album) &&
              (_year == null || e.modified?.year == _year),
        )
        .toList();
    final epoch = DateTime(0);
    switch (_sort) {
      case _Sort.newest:
        list.sort(
          (a, b) => (b.modified ?? epoch).compareTo(a.modified ?? epoch),
        );
      case _Sort.oldest:
        list.sort(
          (a, b) => (a.modified ?? epoch).compareTo(b.modified ?? epoch),
        );
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(galleryItemsProvider(widget.device.id));
    final privacy = ref.watch(
      settingsProvider.select((s) => s.galleryPrivacyMode),
    );
    return DeviceCard(
      title: 'Gallery',
      icon: Icons.photo_library_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            privacy ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 16,
            color: privacy ? HudColors.cyan : HudColors.textMuted,
          ),
          const SizedBox(width: 6),
          const Text('Privacy mode', style: TextStyle(fontSize: 12.5)),
          Switch(
            value: privacy,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(galleryPrivacyMode: v)),
          ),
          HudIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Reload',
            onPressed: () =>
                ref.invalidate(galleryItemsProvider(widget.device.id)),
          ),
        ],
      ),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => DeviceError(
          e,
          onRetry: () => ref.invalidate(galleryItemsProvider(widget.device.id)),
        ),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.photo_outlined,
              title: 'No photos',
              message: 'The camera roll (DCIM) is empty.',
            );
          }
          final albums = {for (final e in all) _albumOf(e)}.toList()..sort();
          final inAlbum = all
              .where((e) => _album == null || _albumOf(e) == _album)
              .toList();
          final years = <int, int>{};
          for (final e in inAlbum) {
            final y = e.modified?.year;
            if (y != null) years[y] = (years[y] ?? 0) + 1;
          }
          final yearList = years.keys.toList()..sort((a, b) => b - a);
          final shown = _shown(all);
          final picked = _picked
              .where((x) => all.any((e) => e.path == x))
              .length;
          final filtered = _album != null || _year != null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HudChipTab(
                    label: 'All albums',
                    active: _album == null,
                    onTap: () => setState(() {
                      _album = null;
                      _year = null;
                    }),
                  ),
                  for (final a in albums)
                    HudChipTab(
                      label: a,
                      active: a == _album,
                      onTap: () => setState(() {
                        _album = a;
                        _year = null;
                      }),
                    ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HudChipTab(
                    label: 'All years ${inAlbum.length}',
                    active: _year == null,
                    onTap: () => setState(() => _year = null),
                  ),
                  for (final y in yearList)
                    HudChipTab(
                      label: '$y  ${years[y]}',
                      active: y == _year,
                      onTap: () => setState(() => _year = y),
                    ),
                  const SizedBox(width: 10),
                  PopupMenuButton<_Sort>(
                    tooltip: 'Sort',
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      for (final s in _Sort.values)
                        CheckedPopupMenuItem(
                          value: s,
                          checked: s == _sort,
                          child: Text(s.label),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: HudPill(
                        _sort.label,
                        color: HudColors.cyan,
                        icon: Icons.sort_rounded,
                        mono: false,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text(
                    picked > 0
                        ? '$picked selected · ${shown.length} shown'
                        : '${shown.length} shown',
                    style: const TextStyle(
                      color: HudColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  TextButton(
                    onPressed: shown.isEmpty
                        ? null
                        : () => setState(() {
                            final paths = shown.map((e) => e.path);
                            if (paths.every(_picked.contains)) {
                              _picked.removeAll(paths);
                            } else {
                              _picked.addAll(paths);
                            }
                          }),
                    child: Text(
                      shown.isNotEmpty &&
                              shown.every((e) => _picked.contains(e.path))
                          ? 'Clear selection'
                          : 'Select shown',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (picked > 0) ...[
                    NeonButton(
                      label: 'Export selected ($picked)',
                      icon: Icons.ios_share_rounded,
                      compact: true,
                      onPressed: _busy == null
                          ? () => _export(
                              all
                                  .where((e) => _picked.contains(e.path))
                                  .toList(),
                              'selected',
                            )
                          : null,
                    ),
                  ],
                  NeonButton(
                    label: filtered
                        ? 'Export shown (${shown.length})'
                        : 'Export all (${all.length})',
                    icon: Icons.drive_folder_upload_rounded,
                    variant: NeonVariant.ghost,
                    compact: true,
                    onPressed: _busy != null || shown.isEmpty
                        ? null
                        : filtered
                        ? () => _export(
                            shown,
                            [?_album, ?_year?.toString()].join(' '),
                          )
                        : _exportAll,
                  ),
                ],
              ),
              if (_busy != null) ...[
                const SizedBox(height: 4),
                Text(_busy!, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 4),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? const EmptyState(
                        icon: Icons.photo_outlined,
                        title: 'Nothing matches these filters',
                      )
                    : _SelectableGrid(
                        items: shown,
                        selected: _picked,
                        onSelectionChanged: (sel) => setState(() {
                          _picked
                            ..clear()
                            ..addAll(sel);
                        }),
                        itemBuilder: (_, i) => _Tile(
                          entry: shown[i],
                          selected: _picked.contains(shown[i].path),
                          privacy: privacy,
                          thumb: _thumbs.load(shown[i]),
                          onTap: () => setState(
                            () => _picked.contains(shown[i].path)
                                ? _picked.remove(shown[i].path)
                                : _picked.add(shown[i].path),
                          ),
                          onOpen: () => showGalleryViewer(
                            context,
                            items: shown,
                            index: i,
                            originals: _originals,
                            thumbnail: _thumbs.load,
                            onExport: (e) => _export([e], e.name),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _pickDest() => getDirectoryPath(
    initialDirectory: deviceFolder(
      ref.read(deviceDataDirProvider),
      widget.device,
      'Photos',
    ),
    confirmButtonText: 'Export here',
  );

  /// Copies [items] to a chosen folder, one file at a time (keeps album
  /// sub-folders so equal names from different albums don't collide).
  Future<void> _export(List<AfcEntry> items, String what) async {
    final dest = await _pickDest();
    if (dest == null || !mounted) return;
    setState(() => _busy = 'Exporting ${items.length} item(s)…');
    await runDeviceAction(
      context,
      'Exported ${items.length} item(s) to $dest',
      () async {
        final svc = ref.read(deviceServiceProvider);
        for (var i = 0; i < items.length; i++) {
          if (mounted) {
            setState(
              () => _busy = 'Exporting $what: ${i + 1} / ${items.length}…',
            );
          }
          final folder = Directory(p.join(dest, _albumOf(items[i])));
          await folder.create(recursive: true);
          await svc.pull(
            widget.device,
            items[i].path,
            p.join(folder.path, items[i].name),
          );
        }
      },
    );
    if (mounted) {
      setState(() {
        _busy = null;
        _picked.clear();
      });
    }
  }

  Future<void> _exportAll() async {
    final dest = await _pickDest();
    if (dest == null || !mounted) return;
    setState(() => _busy = 'Exporting the whole camera roll…');
    await runDeviceAction(
      context,
      'Camera roll exported to $dest',
      () => ref
          .read(deviceServiceProvider)
          .pull(widget.device, '/DCIM', p.join(dest, 'DCIM'), recursive: true),
    );
    if (mounted) setState(() => _busy = null);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.entry,
    required this.selected,
    required this.privacy,
    required this.thumb,
    required this.onTap,
    required this.onOpen,
  });

  final AfcEntry entry;
  final bool selected;

  /// Blur the preview (Privacy mode).
  final bool privacy;
  final Future<File?> thumb;

  /// Click: toggle selection. Double-click: open the viewer.
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(entry.name).toLowerCase();
    final video = ext == '.mov' || ext == '.mp4' || ext == '.m4v';
    final d = entry.modified;
    return Tooltip(
      message: [
        entry.name,
        if (d != null) _date(d),
        formatBytes(entry.size, decimals: 1),
      ].join(' · '),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? HudColors.cyan
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<File?>(
                future: thumb,
                builder: (_, snap) {
                  if (snap.data == null) return _placeholder(video);
                  final image = Image.file(
                    snap.data!,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, _, _) => _placeholder(video),
                  );
                  return privacy
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: image,
                        )
                      : image;
                },
              ),
              if (privacy)
                Center(
                  child: Icon(
                    Icons.visibility_off_rounded,
                    size: 22,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              Positioned(
                left: 6,
                bottom: 4,
                right: 6,
                child: Text(
                  d == null ? entry.name : _date(d),
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.telemetry(size: 10, color: Colors.white70),
                ),
              ),
              if (video)
                const Positioned(
                  right: 6,
                  top: 6,
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              if (selected)
                const Positioned(
                  left: 6,
                  top: 6,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: HudColors.cyan,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(bool video) => Center(
    child: Icon(
      video ? Icons.movie_outlined : Icons.image_outlined,
      color: HudColors.textMuted.withValues(alpha: 0.5),
    ),
  );
}

/// Pulls thumbnails with at most 3 concurrent afcclient processes and caches
/// them on disk.
class _ThumbnailLoader {
  _ThumbnailLoader({required this.pull, required this.cacheDir});

  final Future<void> Function(String remote, String local) pull;
  final String cacheDir;
  final Map<String, Future<File?>> _cache = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  Future<File?> load(AfcEntry e) => _cache.putIfAbsent(e.path, () => _load(e));

  Future<File?> _load(AfcEntry e) async {
    final local = File(p.join(cacheDir, '${e.path.replaceAll('/', '_')}.jpg'));
    if (local.existsSync() && local.lengthSync() > 0) return local;
    await local.parent.create(recursive: true);
    await _acquire();
    try {
      // Photos keeps a JPEG preview of every asset, HEIC and video included.
      final cached = '/PhotoData/Thumbnails/V2${e.path}/5005.JPG';
      try {
        await pull(cached, local.path);
        if (local.existsSync() && local.lengthSync() > 0) return local;
      } on Object {
        // Fall through to the original file.
      }
      final ext = p.extension(e.name).toLowerCase();
      if (_decodable.contains(ext) && e.size < 25 * 1024 * 1024) {
        await pull(e.path, local.path);
        if (local.existsSync()) return local;
      }
      return null;
    } on Object {
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < 3) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }
}

/// Photo grid with mouse drag-to-select: dragging draws a selection box and
/// adds every tile it touches to the selection, auto-scrolling near the top
/// and bottom edges. Touch and trackpad keep scrolling normally.
///
/// Tile positions are computed from the grid geometry (not from built
/// widgets), so the box also covers rows scrolled out of view.
class _SelectableGrid extends StatefulWidget {
  const _SelectableGrid({
    required this.items,
    required this.selected,
    required this.onSelectionChanged,
    required this.itemBuilder,
  });

  final List<AfcEntry> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelectionChanged;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_SelectableGrid> createState() => _SelectableGridState();
}

class _SelectableGridState extends State<_SelectableGrid> {
  static const _maxExtent = 150.0;
  static const _spacing = 8.0;
  static const _edge = 48.0;

  final _scroll = ScrollController();
  Set<String> _base = const {};
  Offset? _start; // content coordinates
  Offset? _pointer; // viewport coordinates
  Timer? _autoScroll;
  double _tile = _maxExtent;
  int _columns = 1;
  double _viewportHeight = 0;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;
  double get _stride => _tile + _spacing;

  Rect? get _selectionRect => _start == null || _pointer == null
      ? null
      : Rect.fromPoints(_start!, _pointer! + Offset(0, _offset));

  void _apply() {
    final r = _selectionRect;
    if (r == null) return;
    final hits = <String>{};
    final firstRow = math.max(0, (r.top / _stride).floor());
    final lastRow = (r.bottom / _stride).floor();
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = 0; col < _columns; col++) {
        final i = row * _columns + col;
        if (i >= widget.items.length) break;
        final tile = Rect.fromLTWH(col * _stride, row * _stride, _tile, _tile);
        if (tile.overlaps(r)) hits.add(widget.items[i].path);
      }
    }
    widget.onSelectionChanged({..._base, ...hits});
    setState(() {});
  }

  void _tick(Timer _) {
    final y = _pointer?.dy;
    if (y == null || !_scroll.hasClients) return;
    double delta = 0;
    if (y < _edge) delta = -(_edge - y) / 2;
    if (y > _viewportHeight - _edge) {
      delta = (y - (_viewportHeight - _edge)) / 2;
    }
    if (delta == 0) return;
    final pos = _scroll.position;
    final next = (_scroll.offset + delta).clamp(0.0, pos.maxScrollExtent);
    if (next != _scroll.offset) {
      _scroll.jumpTo(next);
      _apply();
    }
  }

  void _end() {
    _autoScroll?.cancel();
    _autoScroll = null;
    setState(() {
      _start = null;
      _pointer = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Same arithmetic as SliverGridDelegateWithMaxCrossAxisExtent.
      _columns = math.max(1, (c.maxWidth / (_maxExtent + _spacing)).ceil());
      _tile = (c.maxWidth - _spacing * (_columns - 1)) / _columns;
      _viewportHeight = c.maxHeight;
      final r = _selectionRect;
      return GestureDetector(
        supportedDevices: const {PointerDeviceKind.mouse},
        onPanStart: (d) {
          _base = {...widget.selected};
          _start = d.localPosition + Offset(0, _offset);
          _pointer = d.localPosition;
          _autoScroll ??= Timer.periodic(
            const Duration(milliseconds: 16),
            _tick,
          );
          _apply();
        },
        onPanUpdate: (d) {
          _pointer = d.localPosition;
          _apply();
        },
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: Stack(
          children: [
            GridView.builder(
              controller: _scroll,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
              ),
              itemCount: widget.items.length,
              itemBuilder: widget.itemBuilder,
            ),
            if (r != null)
              Positioned(
                left: r.left,
                top: r.top - _offset,
                width: r.width,
                height: r.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: HudColors.cyan.withValues(alpha: 0.12),
                      border: Border.all(color: HudColors.cyan, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
