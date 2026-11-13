import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../services/whatsapp/wa_media_index.dart';
import '../../../services/whatsapp/wa_parser.dart';
import '../../providers/whatsapp_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/gallery_viewer.dart';

/// Media kinds that have a picture to show.
bool waHasPicture(WaMediaKind k) =>
    k == WaMediaKind.image ||
    k == WaMediaKind.video ||
    k == WaMediaKind.sticker ||
    k == WaMediaKind.gif;

/// Copies the message's file out of the backup (with its real extension)
/// and opens it in the default app.
Future<void> openWaMedia(WidgetRef ref, WaMediaIndex index, WaMessage m) async {
  final dir = p.join(ref.read(waWorkDirProvider), 'media-preview');
  final path = index.export(m.mediaPath, dir);
  if (path != null) await openWithSystem(path);
}

/// A photo / video / sticker preview inside a chat bubble or the media grid.
class WaMediaThumb extends ConsumerWidget {
  const WaMediaThumb({
    super.key,
    required this.message,
    required this.index,
    this.size = 220,
    this.square = false,
  });

  final WaMessage message;
  final WaMediaIndex index;
  final double size;

  /// Fill a square tile (grid) instead of keeping the picture's shape.
  final bool square;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = index.thumbnail(message.mediaPath);
    if (thumb == null) return const SizedBox.shrink();
    final video =
        message.kind == WaMediaKind.video || message.kind == WaMediaKind.gif;
    final sticker = message.kind == WaMediaKind.sticker;
    final image = Image.file(
      File(thumb),
      width: square ? size : null,
      height: square ? size : null,
      fit: square ? BoxFit.cover : BoxFit.contain,
      cacheWidth: (size * 2).round(),
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        width: square ? size : 120,
        height: square ? size : 80,
        alignment: Alignment.center,
        color: HudColors.overlay.withValues(alpha: 0.05),
        child: Icon(
          video ? Icons.movie_rounded : Icons.image_not_supported_outlined,
          color: HudColors.textMuted,
        ),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openWaMedia(ref, index, message),
        child: Tooltip(
          message: tr('Open in the default app'),
          waitDuration: const Duration(milliseconds: 600),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(sticker ? 0 : 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: square ? size : size * 1.2,
                maxHeight: square ? size : size,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  image,
                  if (video)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  if (video && message.mediaDurationSec != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _duration(message.mediaDurationSec!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _duration(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

enum _Kind { all, photos, videos, stickers }

/// Every photo, video and sticker of the backup (or of one chat), newest
/// first.
class WaMediaGallery extends ConsumerStatefulWidget {
  const WaMediaGallery({
    super.key,
    required this.archive,
    required this.index,
    this.chatJid,
  });

  final WaArchive archive;
  final WaMediaIndex index;

  /// Only this chat's media; `null` = the whole backup.
  final String? chatJid;

  @override
  ConsumerState<WaMediaGallery> createState() => _WaMediaGalleryState();
}

class _WaMediaGalleryState extends ConsumerState<WaMediaGallery> {
  _Kind _kind = _Kind.all;
  late List<WaMessage> _all = _collect();

  @override
  void didUpdateWidget(WaMediaGallery old) {
    super.didUpdateWidget(old);
    if (old.archive != widget.archive ||
        old.index != widget.index ||
        old.chatJid != widget.chatJid) {
      _all = _collect();
    }
  }

  List<WaMessage> _collect() {
    final list = [
      for (final m in widget.archive.messages)
        if (waHasPicture(m.kind) &&
            (widget.chatJid == null || m.chatJid == widget.chatJid) &&
            widget.index.thumbnail(m.mediaPath) != null)
          m,
    ]..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return list;
  }

  bool _keep(WaMessage m) => switch (_kind) {
    _Kind.all => true,
    _Kind.photos => m.kind == WaMediaKind.image,
    _Kind.videos => m.kind == WaMediaKind.video || m.kind == WaMediaKind.gif,
    _Kind.stickers => m.kind == WaMediaKind.sticker,
  };

  @override
  Widget build(BuildContext context) {
    final shown = _all.where(_keep).toList();
    String label(_Kind k) => switch (k) {
      _Kind.all => tr('All'),
      _Kind.photos => tr('Photos'),
      _Kind.videos => tr('Videos'),
      _Kind.stickers => tr('Stickers'),
    };
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final k in _Kind.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(label(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                    showCheckmark: false,
                  ),
                ),
              const Spacer(),
              Text(
                trf('{0} items', [shown.length]),
                style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: shown.isEmpty
                ? EmptyState(
                    icon: Icons.photo_library_outlined,
                    title: tr('No media in this backup'),
                    message: tr(
                      'Photos and videos only appear when they were included in the backup.',
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => LayoutBuilder(
                      builder: (_, c) => WaMediaThumb(
                        message: shown[i],
                        index: widget.index,
                        size: c.maxWidth,
                        square: true,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
