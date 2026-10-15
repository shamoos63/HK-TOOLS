import 'dart:async';
import 'dart:collection';
import 'dart:io';

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

const _mediaExtensions = {
  '.jpg', '.jpeg', '.png', '.heic', '.heif', '.gif', '.dng', //
  '.mov', '.mp4', '.m4v',
};
const _decodable = {'.jpg', '.jpeg', '.png', '.gif'};

/// Camera roll browser over AFC (`/DCIM/<album>/`). Thumbnails come from the
/// Photos thumbnail cache (`/PhotoData/Thumbnails/V2/…/5005.JPG`) when present,
/// so HEIC photos preview without converting them.
class GalleryTab extends ConsumerStatefulWidget {
  const GalleryTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<GalleryTab> {
  String? _album;
  final Set<String> _picked = {};
  String? _busy;
  late final _thumbs = _ThumbnailLoader(
    pull: (remote, local) =>
        ref.read(deviceServiceProvider).pull(widget.device, remote, local),
    cacheDir: p.join(
      ref.read(appSupportDirProvider),
      'gallery_cache',
      widget.device.udid ?? widget.device.id,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(
      deviceDirectoryProvider((widget.device.id, '/DCIM', null)),
    );
    return DeviceCard(
      title: 'Gallery',
      icon: Icons.photo_library_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_picked.isNotEmpty)
            NeonButton(
              label: 'Import ${_picked.length}',
              icon: Icons.download_rounded,
              compact: true,
              onPressed: _busy == null ? _importPicked : null,
            ),
          const SizedBox(width: 8),
          NeonButton(
            label: 'Import all',
            icon: Icons.download_for_offline_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: _busy == null ? _importAll : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy != null) ...[
            Text(_busy!, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
          ],
          albums.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => DeviceError(e),
            data: (list) {
              final dirs = list.where((e) => e.isDirectory).toList();
              if (_album == null && dirs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) =>
                      mounted ? setState(() => _album = dirs.last.path) : null,
                );
              }
              return Wrap(
                children: [
                  for (final d in dirs)
                    HudChipTab(
                      label: d.name,
                      active: d.path == _album,
                      onTap: () => setState(() => _album = d.path),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _album == null
                ? const EmptyState(
                    icon: Icons.photo_outlined,
                    title: 'No photos',
                    message: 'The camera roll (DCIM) is empty.',
                  )
                : _AlbumGrid(
                    device: widget.device,
                    album: _album!,
                    picked: _picked,
                    thumbs: _thumbs,
                    onToggle: (path) => setState(
                      () => _picked.contains(path)
                          ? _picked.remove(path)
                          : _picked.add(path),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickDest() => getDirectoryPath(
    initialDirectory: deviceFolder(
      ref.read(deviceDataDirProvider),
      widget.device,
      'Photos',
    ),
    confirmButtonText: 'Import here',
  );

  Future<void> _importPicked() async {
    final dest = await _pickDest();
    if (dest == null || !mounted) return;
    final items = _picked.toList();
    setState(() => _busy = 'Importing ${items.length} item(s)…');
    await runDeviceAction(
      context,
      'Imported ${items.length} item(s) to $dest',
      () async {
        final svc = ref.read(deviceServiceProvider);
        for (var i = 0; i < items.length; i++) {
          if (mounted) {
            setState(() => _busy = 'Importing ${i + 1} / ${items.length}…');
          }
          await svc.pull(
            widget.device,
            items[i],
            p.join(dest, p.posix.basename(items[i])),
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

  Future<void> _importAll() async {
    final dest = await _pickDest();
    if (dest == null || !mounted) return;
    setState(() => _busy = 'Importing the whole camera roll…');
    await runDeviceAction(
      context,
      'Camera roll imported to $dest',
      () => ref
          .read(deviceServiceProvider)
          .pull(widget.device, '/DCIM', p.join(dest, 'DCIM'), recursive: true),
    );
    if (mounted) setState(() => _busy = null);
  }
}

class _AlbumGrid extends ConsumerWidget {
  const _AlbumGrid({
    required this.device,
    required this.album,
    required this.picked,
    required this.thumbs,
    required this.onToggle,
  });

  final ConnectedDevice device;
  final String album;
  final Set<String> picked;
  final _ThumbnailLoader thumbs;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deviceDirectoryProvider((device.id, album, null)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => DeviceError(e),
      data: (entries) {
        final media = entries
            .where(
              (e) =>
                  !e.isDirectory &&
                  _mediaExtensions.contains(p.extension(e.name).toLowerCase()),
            )
            .toList()
            .reversed
            .toList();
        if (media.isEmpty) {
          return const EmptyState(
            icon: Icons.photo_outlined,
            title: 'Empty album',
          );
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: media.length,
          itemBuilder: (_, i) => _Tile(
            entry: media[i],
            selected: picked.contains(media[i].path),
            thumb: thumbs.load(media[i]),
            onTap: () => onToggle(media[i].path),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.entry,
    required this.selected,
    required this.thumb,
    required this.onTap,
  });

  final AfcEntry entry;
  final bool selected;
  final Future<File?> thumb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(entry.name).toLowerCase();
    final video = ext == '.mov' || ext == '.mp4' || ext == '.m4v';
    return Tooltip(
      message: '${entry.name} · ${formatBytes(entry.size, decimals: 1)}',
      child: InkWell(
        onTap: onTap,
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
                builder: (_, snap) => snap.data != null
                    ? Image.file(
                        snap.data!,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, _, _) => _placeholder(video),
                      )
                    : _placeholder(video),
              ),
              Positioned(
                left: 6,
                bottom: 4,
                right: 6,
                child: Text(
                  entry.name,
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
