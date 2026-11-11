import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// AFC file explorer. The root is the device's media partition
/// (`/private/var/mobile/Media`: DCIM, Downloads, Books, …), or with
/// [documentsOf] the Documents folder of a file-sharing app.
class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key, required this.device, this.documentsOf});

  final ConnectedDevice device;
  final String? documentsOf;

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<FilesTab> {
  late String _path = widget.documentsOf == null ? '/' : '/Documents';
  String? _selected;
  String? _busy;

  (String, String, String?) get _key =>
      (widget.device.id, _path, widget.documentsOf);

  void _reload() => ref.invalidate(deviceDirectoryProvider(_key));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deviceDirectoryProvider(_key));
    final segments = _path.split('/').where((s) => s.isNotEmpty).toList();
    return DeviceCard(
      title: widget.documentsOf == null
          ? tr('Files')
          : trf('Documents · {0}', [widget.documentsOf]),
      icon: Icons.folder_rounded,
      fill: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HudIconButton(
            icon: Icons.create_new_folder_outlined,
            tooltip: tr('New folder'),
            onPressed: _busy == null ? _mkdir : null,
          ),
          HudIconButton(
            icon: Icons.upload_rounded,
            tooltip: tr('Upload files here'),
            onPressed: _busy == null ? _upload : null,
          ),
          HudIconButton(
            icon: Icons.refresh_rounded,
            tooltip: tr('Reload'),
            onPressed: _reload,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Crumb(
                label: widget.documentsOf == null ? 'Media' : tr('App'),
                onTap: () => setState(
                  () => _path = widget.documentsOf == null ? '/' : '/Documents',
                ),
              ),
              for (var i = 0; i < segments.length; i++) ...[
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: HudColors.textMuted,
                ),
                _Crumb(
                  label: segments[i],
                  onTap: () => setState(
                    () => _path = '/${segments.sublist(0, i + 1).join('/')}',
                  ),
                ),
              ],
            ],
          ),
          if (_busy != null) ...[
            const SizedBox(height: 8),
            Text(_busy!, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => DeviceError(e, onRetry: _reload),
              data: (entries) => entries.isEmpty
                  ? EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: tr('Empty folder'),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (_, i) => _EntryRow(
                        entry: entries[i],
                        selected: entries[i].path == _selected,
                        onTap: () =>
                            setState(() => _selected = entries[i].path),
                        onOpen: entries[i].isDirectory
                            ? () => setState(() {
                                _path = entries[i].path;
                                _selected = null;
                              })
                            : null,
                        onDownload: () => _download(entries[i]),
                        onRename: () => _rename(entries[i]),
                        onDelete: () => _delete(entries[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _job(
    String label,
    String done,
    Future<void> Function() f,
  ) async {
    setState(() => _busy = label);
    await runDeviceAction(context, done, f);
    if (!mounted) return;
    setState(() => _busy = null);
    _reload();
  }

  Future<void> _download(AfcEntry e) async {
    final dest = await getDirectoryPath(
      initialDirectory: deviceFolder(
        ref.read(deviceDataDirProvider),
        widget.device,
        tr('Files'),
      ),
      confirmButtonText: tr('Save here'),
    );
    if (dest == null) return;
    await _job(
      trf('Downloading {0}…', [e.name]),
      trf('Saved {0} to {1}', [e.name, dest]),
      () => ref
          .read(deviceServiceProvider)
          .pull(
            widget.device,
            e.path,
            p.join(dest, e.name),
            documentsOf: widget.documentsOf,
            recursive: e.isDirectory,
          ),
    );
  }

  Future<void> _upload() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    await _job(
      trf('Uploading {0} file(s)…', [files.length]),
      trf('Uploaded {0} file(s)', [files.length]),
      () async {
        for (final f in files) {
          await ref
              .read(deviceServiceProvider)
              .push(
                widget.device,
                f.path,
                _path,
                documentsOf: widget.documentsOf,
              );
        }
      },
    );
  }

  Future<void> _mkdir() async {
    final name = await promptText(
      context,
      title: tr('New folder'),
      confirmLabel: tr('Create'),
    );
    if (name == null || name.trim().isEmpty) return;
    await _job(
      tr('Creating folder…'),
      trf('Created {0}', [name.trim()]),
      () => ref
          .read(deviceServiceProvider)
          .makeDirectory(
            widget.device,
            p.posix.join(_path, name.trim()),
            documentsOf: widget.documentsOf,
          ),
    );
  }

  Future<void> _rename(AfcEntry e) async {
    final name = await promptText(
      context,
      title: tr('Rename'),
      initial: e.name,
    );
    if (name == null || name.trim().isEmpty || name.trim() == e.name) return;
    await _job(
      tr('Renaming…'),
      trf('Renamed to {0}', [name.trim()]),
      () => ref
          .read(deviceServiceProvider)
          .movePath(
            widget.device,
            e.path,
            p.posix.join(p.posix.dirname(e.path), name.trim()),
            documentsOf: widget.documentsOf,
          ),
    );
  }

  Future<void> _delete(AfcEntry e) async {
    final ok = await confirmDialog(
      context,
      title: trf('Delete {0}?', [e.name]),
      message: e.isDirectory
          ? tr(
              'The folder must be empty. Files deleted from the device cannot be recovered.',
            )
          : tr('Files deleted from the device cannot be recovered.'),
      confirmLabel: tr('Delete'),
      danger: true,
    );
    if (!ok) return;
    await _job(
      tr('Deleting…'),
      trf('Deleted {0}', [e.name]),
      () => ref
          .read(deviceServiceProvider)
          .deletePath(widget.device, e.path, documentsOf: widget.documentsOf),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        label,
        style: HudTheme.telemetry(size: 12.5, color: HudColors.cyan),
      ),
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.onRename,
    required this.onDelete,
    this.onOpen,
  });

  final AfcEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onOpen;
  final VoidCallback onDownload;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return InkWell(
      onTap: onTap,
      onDoubleTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: selected ? HudColors.cyan.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            Icon(
              e.isDirectory
                  ? Icons.folder_rounded
                  : e.isLink
                  ? Icons.link_rounded
                  : _fileIcon(e.name),
              size: 18,
              color: e.isDirectory ? HudColors.cyan : HudColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                e.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                e.modified == null ? '' : _date(e.modified!),
                style: HudTheme.telemetry(
                  size: 11.5,
                  color: HudColors.textMuted,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                e.isDirectory ? '' : formatBytes(e.size, decimals: 1),
                textAlign: TextAlign.right,
                style: HudTheme.telemetry(
                  size: 11.5,
                  color: HudColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (onOpen != null)
              HudIconButton(
                icon: Icons.arrow_forward_rounded,
                tooltip: tr('Open'),
                onPressed: onOpen,
              ),
            HudIconButton(
              icon: Icons.download_rounded,
              tooltip: tr('Download'),
              onPressed: onDownload,
            ),
            HudIconButton(
              icon: Icons.drive_file_rename_outline_rounded,
              tooltip: tr('Rename'),
              onPressed: onRename,
            ),
            HudIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: tr('Delete'),
              color: HudColors.danger,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${_pad2(d.month)}-${_pad2(d.day)} ${_pad2(d.hour)}:${_pad2(d.minute)}';
  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static IconData _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' || '.png' || '.heic' || '.gif' => Icons.image_outlined,
      '.mov' || '.mp4' || '.m4v' => Icons.movie_outlined,
      '.mp3' || '.m4a' || '.aac' || '.wav' => Icons.audiotrack_outlined,
      '.pdf' || '.epub' => Icons.menu_book_outlined,
      '.plist' ||
      '.json' ||
      '.xml' ||
      '.txt' ||
      '.log' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}
