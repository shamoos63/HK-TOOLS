import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../widgets/hud_widgets.dart';

const _videoExtensions = {'.mov', '.mp4', '.m4v'};

/// Formats Flutter decodes itself; others (HEIC, HEIF, DNG) are converted.
const _flutterDecodable = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};

bool isVideoName(String name) =>
    _videoExtensions.contains(p.extension(name).toLowerCase());

/// Fetches originals into a local cache and makes them viewable.
class GalleryOriginals {
  GalleryOriginals({required this.pull, required this.cacheDir});

  final Future<void> Function(String remote, String local) pull;
  final String cacheDir;
  final Map<String, Future<File>> _originals = {};
  final Map<String, Future<File?>> _viewable = {};

  /// The original file, copied from the device once.
  Future<File> original(AfcEntry e) => _originals.putIfAbsent(e.path, () async {
    final f = File(p.join(cacheDir, 'originals', e.path.replaceAll('/', '_')));
    if (f.existsSync() && f.lengthSync() == e.size) return f;
    await f.parent.create(recursive: true);
    await pull(e.path, f.path);
    if (!f.existsSync()) {
      throw const FileSystemException('Copy from device failed');
    }
    return f;
  });

  /// A file Flutter can display: the original, or a JPEG converted from it.
  /// `null` when this computer can't decode the format.
  Future<File?> viewable(AfcEntry e) => _viewable.putIfAbsent(e.path, () async {
    final src = await original(e);
    final ext = p.extension(e.name).toLowerCase();
    if (_flutterDecodable.contains(ext)) return src;
    final out = File('${src.path}.view.jpg');
    if (out.existsSync() && out.lengthSync() > 0) return out;
    return await convertToJpeg(src.path, out.path) ? out : null;
  });

  /// HEIC / HEIF / DNG → JPEG with the OS image codecs: `sips` on macOS,
  /// Windows Imaging Component (needs the HEIF / HEVC extensions for HEIC)
  /// on Windows.
  static Future<bool> convertToJpeg(String input, String output) async {
    try {
      final ProcessResult r;
      if (Platform.isMacOS) {
        r = await Process.run('sips', [
          '-s', 'format', 'jpeg', //
          '-s', 'formatOptions', '90',
          input,
          '--out',
          output,
        ]);
      } else if (Platform.isWindows) {
        String q(String s) => "'${s.replaceAll("'", "''")}'";
        final script =
            'Add-Type -AssemblyName PresentationCore; '
            '\$i=[IO.File]::OpenRead(${q(input)}); '
            '\$d=[Windows.Media.Imaging.BitmapDecoder]::Create(\$i,'
            "[Windows.Media.Imaging.BitmapCreateOptions]::None,"
            "[Windows.Media.Imaging.BitmapCacheOption]::OnLoad); "
            '\$e=New-Object Windows.Media.Imaging.JpegBitmapEncoder; '
            '\$e.QualityLevel=90; \$e.Frames.Add(\$d.Frames[0]); '
            '\$o=[IO.File]::Create(${q(output)}); \$e.Save(\$o); '
            '\$o.Close(); \$i.Close()';
        r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]);
      } else {
        return false;
      }
      return r.exitCode == 0 &&
          File(output).existsSync() &&
          File(output).lengthSync() > 0;
    } on Object {
      return false;
    }
  }
}

/// Opens a file with the system's default app (videos, or "Open in…").
Future<void> openWithSystem(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

/// Full-screen viewer over [items], starting at [index]. ← / → move,
/// Esc closes, scroll or pinch zooms.
Future<void> showGalleryViewer(
  BuildContext context, {
  required List<AfcEntry> items,
  required int index,
  required GalleryOriginals originals,
  Future<File?> Function(AfcEntry e)? thumbnail,
  Future<void> Function(AfcEntry e)? onExport,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.92),
  builder: (_) => _Viewer(
    items: items,
    initial: index,
    originals: originals,
    thumbnail: thumbnail,
    onExport: onExport,
  ),
);

class _Viewer extends StatefulWidget {
  const _Viewer({
    required this.items,
    required this.initial,
    required this.originals,
    this.thumbnail,
    this.onExport,
  });

  final List<AfcEntry> items;
  final int initial;
  final GalleryOriginals originals;
  final Future<File?> Function(AfcEntry e)? thumbnail;
  final Future<void> Function(AfcEntry e)? onExport;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _i = widget.initial;
  final _zoom = TransformationController();
  final _focus = FocusNode();

  AfcEntry get _e => widget.items[_i];

  @override
  void initState() {
    super.initState();
    _prefetch(_i + 1);
  }

  @override
  void dispose() {
    _zoom.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _prefetch(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final e = widget.items[i];
    if (!isVideoName(e.name)) widget.originals.viewable(e).ignore();
  }

  void _go(int delta) {
    final next = _i + delta;
    if (next < 0 || next >= widget.items.length) return;
    setState(() {
      _i = next;
      _zoom.value = Matrix4.identity();
    });
    _prefetch(next + delta);
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final d = e.modified;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowRight:
            _go(1);
          case LogicalKeyboardKey.arrowLeft:
            _go(-1);
          case LogicalKeyboardKey.escape:
            Navigator.pop(context);
          default:
            return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned.fill(
              top: 56,
              bottom: 56,
              child: KeyedSubtree(
                key: ValueKey(e.path),
                child: isVideoName(e.name)
                    ? _VideoCard(entry: e, originals: widget.originals)
                    : _ImageView(
                        entry: e,
                        originals: widget.originals,
                        thumbnail: widget.thumbnail,
                        zoom: _zoom,
                      ),
              ),
            ),
            // Top bar: name, date, size, actions.
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        e.name,
                        if (d != null)
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                        formatBytes(e.size, decimals: 1),
                        '${_i + 1} / ${widget.items.length}',
                      ].join('   ·   '),
                      overflow: TextOverflow.ellipsis,
                      style: HudTheme.telemetry(
                        size: 12.5,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (widget.onExport != null)
                    HudIconButton(
                      icon: Icons.ios_share_rounded,
                      tooltip: 'Export this file',
                      color: Colors.white70,
                      onPressed: () => widget.onExport!(e),
                    ),
                  HudIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Open in the default app',
                    color: Colors.white70,
                    onPressed: () async => openWithSystem(
                      (await widget.originals.original(e)).path,
                    ),
                  ),
                  HudIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close (Esc)',
                    color: Colors.white70,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_i > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous (←)',
                    onPressed: () => _go(-1),
                  ),
                ),
              ),
            if (_i < widget.items.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next (→)',
                    onPressed: () => _go(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({
    required this.entry,
    required this.originals,
    required this.zoom,
    this.thumbnail,
  });

  final AfcEntry entry;
  final GalleryOriginals originals;
  final TransformationController zoom;
  final Future<File?> Function(AfcEntry e)? thumbnail;

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: originals.viewable(entry),
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'Loading original from the device…',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ),
        );
      }
      final file = snap.data;
      if (file == null) {
        // Undecodable on this computer: fall back to the Photos preview.
        return FutureBuilder<File?>(
          future: thumbnail?.call(entry),
          builder: (_, t) => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (t.data != null)
                Flexible(child: Image.file(t.data!, fit: BoxFit.contain)),
              const SizedBox(height: 10),
              Text(
                snap.hasError
                    ? 'Could not copy the original: ${snap.error}'
                    : 'This computer can\'t display ${p.extension(entry.name).toUpperCase().substring(1)} '
                          'images; showing the preview. Use "Open in the default app".',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ),
        );
      }
      return InteractiveViewer(
        transformationController: zoom,
        minScale: 1,
        maxScale: 8,
        child: Center(
          child: Image.file(
            file,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const Text(
              'This image could not be decoded.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    },
  );
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({required this.entry, required this.originals});

  final AfcEntry entry;
  final GalleryOriginals originals;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _busy = false;
  String? _error;

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await openWithSystem(
        (await widget.originals.original(widget.entry)).path,
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.movie_rounded, size: 64, color: Colors.white54),
        const SizedBox(height: 14),
        _busy
            ? const Text(
                'Copying video from the device…',
                style: TextStyle(color: Colors.white70),
              )
            : NeonButton(
                label: 'Play in the default player',
                icon: Icons.play_arrow_rounded,
                onPressed: _play,
              ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: HudColors.danger)),
        ],
      ],
    ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 30, color: Colors.white),
        ),
      ),
    ),
  );
}
