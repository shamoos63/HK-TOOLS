import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/download_task.dart';
import '../../../services/download/download_progress.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/ui_providers.dart';
import '../../widgets/hud_widgets.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  static bool _matches(QueueFilter f, DownloadTask t) => switch (f) {
    QueueFilter.all => true,
    QueueFilter.active => t.status.isActive,
    QueueFilter.queued => t.status == DownloadStatus.queued,
    QueueFilter.paused => t.status == DownloadStatus.paused,
    QueueFilter.completed => t.status == DownloadStatus.completed,
    QueueFilter.failed =>
      t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(downloadTasksProvider).value ?? const <DownloadTask>[];
    final filter = ref.watch(queueFilterProvider);
    final visible = [
      for (final t in tasks)
        if (_matches(filter, t)) t,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BandwidthPanel(),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final f in QueueFilter.values) ...[
                _FilterChip(
                  label: f.name,
                  count: tasks.where((t) => _matches(f, t)).length,
                  active: f == filter,
                  onTap: () => ref.read(queueFilterProvider.notifier).set(f),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              if (tasks.any(
                (t) => t.status.isActive || t.status == DownloadStatus.queued,
              ))
                NeonButton(
                  label: 'Pause all',
                  icon: Icons.pause_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: () => ref.read(downloadActionsProvider).run((m) {
                    for (final t in m.tasks) {
                      m.pause(t.id);
                    }
                  }),
                ),
              if (tasks.any((t) => t.status == DownloadStatus.paused)) ...[
                const SizedBox(width: 8),
                NeonButton(
                  label: 'Resume all',
                  icon: Icons.play_arrow_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: () => ref.read(downloadActionsProvider).run((m) {
                    for (final t in m.tasks) {
                      if (t.status == DownloadStatus.paused) m.resume(t.id);
                    }
                  }),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? GlassPanel(
                    child: EmptyState(
                      icon: Icons.download_done_rounded,
                      title: tasks.isEmpty
                          ? 'Queue is empty'
                          : 'Nothing in this view',
                      message: tasks.isEmpty
                          ? 'Pick firmware in the Library and press GET or Queue. '
                                'Shared payloads are only downloaded once.'
                          : null,
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _TaskCard(
                      key: ValueKey(visible[i].id),
                      task: visible[i],
                      isFirst: tasks.first.id == visible[i].id,
                      isLast: tasks.last.id == visible[i].id,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: active
              ? HudColors.cyan.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: active
                ? HudColors.cyan.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Text(
              label[0].toUpperCase() + label.substring(1),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? HudColors.textPrimary : HudColors.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: HudTheme.telemetry(
                size: 11,
                color: active ? HudColors.cyan : HudColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BandwidthPanel extends ConsumerWidget {
  const _BandwidthPanel();

  static const _caps = <int>[0, 1, 5, 10, 25, 50, 100];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(hudTelemetryProvider).value;
    final settings = ref.watch(settingsProvider);
    final tasks = ref.watch(downloadTasksProvider).value ?? const [];
    final done = tasks
        .where((t) => t.status == DownloadStatus.completed)
        .length;
    final capMb = settings.globalSpeedLimitBytesPerSecond ~/ (1024 * 1024);

    return GlassPanel(
      glow: (t?.bytesPerSecond ?? 0) > 0,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SizedBox(
        height: 82,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const HudLabel('Aggregate bandwidth'),
                  const SizedBox(height: 6),
                  Text(
                    formatRate(t?.bytesPerSecond ?? 0),
                    style: HudTheme.telemetry(size: 26)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(child: Sparkline(values: t?.history ?? const [])),
            const SizedBox(width: 24),
            _Stat(
              label: 'Active',
              value: '${t?.active ?? 0}',
              color: HudColors.cyan,
            ),
            _Stat(
              label: 'Queued',
              value: '${t?.queued ?? 0}',
              color: HudColors.purple,
            ),
            _Stat(label: 'Stored', value: '$done', color: HudColors.success),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const HudLabel('Speed cap'),
                const SizedBox(height: 4),
                DropdownButton<int>(
                  value: _caps.contains(capMb) ? capMb : 0,
                  dropdownColor: HudColors.surface,
                  underline: const SizedBox(),
                  isDense: true,
                  style: HudTheme.telemetry(
                    size: 13,
                    color: HudColors.textPrimary,
                  ),
                  items: [
                    for (final c in _caps)
                      DropdownMenuItem(
                        value: c,
                        child: Text(c == 0 ? 'Unlimited' : '$c MB/s'),
                      ),
                  ],
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .update(
                        (s) => s.copyWith(
                          globalSpeedLimitBytesPerSecond:
                              (v ?? 0) * 1024 * 1024,
                        ),
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: HudTheme.telemetry(
            size: 22,
            color: color,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        HudLabel(label),
      ],
    ),
  );
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.isFirst,
    required this.isLast,
  });

  final DownloadTask task;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    final index = ref.watch(catalogIndexProvider);
    final running =
        t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.connecting ||
        t.status == DownloadStatus.refreshingLink;
    final progress = running
        ? ref.watch(downloadProgressProvider(t.id)).value
        : null;
    final actions = ref.read(downloadActionsProvider);
    final names = t.deviceIdentifiers.map(index.displayName).toSet().toList();
    final (statusLabel, statusColor) = _status(t);
    final downloaded = progress?.downloadedBytes ?? t.downloadedBytes;
    final total = progress?.totalBytes ?? t.knownSize;
    final fraction = total > 0 ? downloaded / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        borderColor: running ? HudColors.cyan.withValues(alpha: 0.35) : null,
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${t.platform.label} ${t.version}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.buildId,
                            style: HudTheme.telemetry(
                              size: 12,
                              color: HudColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          HudPill(statusLabel, color: statusColor),
                          if (t.deviceIdentifiers.length > 1) ...[
                            const SizedBox(width: 6),
                            HudPill(
                              'SHARED ×${t.deviceIdentifiers.length}',
                              color: HudColors.purple,
                              icon: Icons.link_rounded,
                            ),
                          ],
                          if (t.linkRefreshCount > 0) ...[
                            const SizedBox(width: 6),
                            HudPill(
                              'LINK ↻${t.linkRefreshCount}',
                              color: HudColors.warning,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudTheme.telemetry(
                          size: 11.5,
                          color: HudColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        names.length <= 4
                            ? names.join(' · ')
                            : '${names.take(4).join(' · ')} · +${names.length - 4}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: HudColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._controls(t, actions, context),
              ],
            ),
            const SizedBox(height: 12),
            if (progress != null && progress.chunks.length > 1)
              _ThreadVisualizer(progress: progress)
            else
              GlowProgressBar(
                value: t.status == DownloadStatus.completed ? 1 : fraction,
                dimmed: !running,
                colors: t.status == DownloadStatus.failed
                    ? const [HudColors.danger, HudColors.purple]
                    : t.status == DownloadStatus.completed
                    ? const [HudColors.success, HudColors.cyan]
                    : const [HudColors.cyan, HudColors.purple],
              ),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: HudTheme.telemetry(size: 11.5, color: HudColors.textMuted),
              child: Row(
                children: [
                  Text('${formatBytes(downloaded)} / ${formatBytes(total)}'),
                  _sep(),
                  Text('${(fraction * 100).toStringAsFixed(1)}%'),
                  if (progress != null) ...[
                    _sep(),
                    Text(
                      formatRate(progress.bytesPerSecond),
                      style: HudTheme.telemetry(size: 11.5),
                    ),
                    _sep(),
                    Text('ETA ${formatEta(progress.eta)}'),
                    _sep(),
                    Text('${progress.activeThreads}/${t.threadCount} threads'),
                  ],
                  if (t.speedLimitBytesPerSecond > 0) ...[
                    _sep(),
                    Text('cap ${formatRate(t.speedLimitBytesPerSecond)}'),
                  ],
                  const Spacer(),
                  if (t.errorMessage != null)
                    Flexible(
                      child: Text(
                        t.errorMessage!,
                        overflow: TextOverflow.ellipsis,
                        style: HudTheme.telemetry(
                          size: 11.5,
                          color: HudColors.danger,
                        ),
                      ),
                    )
                  else if (t.sha1sum != null)
                    Text('SHA1 ${t.sha1sum!.substring(0, 12)}…'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Text('│', style: TextStyle(color: HudColors.glassBorder)),
  );

  List<Widget> _controls(
    DownloadTask t,
    DownloadActions actions,
    BuildContext context,
  ) {
    final s = t.status;
    return [
      HudIconButton(
        icon: Icons.keyboard_arrow_up_rounded,
        tooltip: 'Move up',
        onPressed: isFirst ? null : () => actions.run((m) => m.moveUp(t.id)),
      ),
      HudIconButton(
        icon: Icons.keyboard_arrow_down_rounded,
        tooltip: 'Move down',
        onPressed: isLast ? null : () => actions.run((m) => m.moveDown(t.id)),
      ),
      if (s.isActive || s == DownloadStatus.queued)
        HudIconButton(
          icon: Icons.pause_rounded,
          tooltip: 'Pause',
          color: HudColors.warning,
          onPressed: () => actions.run((m) => m.pause(t.id)),
        ),
      if (s == DownloadStatus.paused)
        HudIconButton(
          icon: Icons.play_arrow_rounded,
          tooltip: 'Resume',
          color: HudColors.cyan,
          onPressed: () => actions.run((m) => m.resume(t.id)),
        ),
      if (s == DownloadStatus.failed || s == DownloadStatus.cancelled) ...[
        HudIconButton(
          icon: Icons.replay_rounded,
          tooltip: 'Retry',
          color: HudColors.cyan,
          onPressed: () => actions.run((m) => m.retry(t.id)),
        ),
        HudIconButton(
          icon: Icons.link_rounded,
          tooltip: 'Refresh link from IPSW.me',
          color: HudColors.warning,
          onPressed: () => actions.run((m) => m.refreshLink(t.id)),
        ),
      ],
      _SpeedCapMenu(task: t),
      if (s == DownloadStatus.completed)
        HudIconButton(
          icon: Icons.folder_open_rounded,
          tooltip: 'Reveal in folder',
          onPressed: () => _reveal(t.targetPath),
        ),
      HudIconButton(
        icon: s == DownloadStatus.completed || s == DownloadStatus.cancelled
            ? Icons.playlist_remove_rounded
            : Icons.close_rounded,
        tooltip: s == DownloadStatus.completed || s == DownloadStatus.cancelled
            ? 'Remove from list (keeps file)'
            : 'Cancel and delete partial data',
        color: HudColors.danger.withValues(alpha: 0.8),
        onPressed: () => actions.run(
          (m) => m.cancel(
            t.id,
            remove:
                s == DownloadStatus.completed || s == DownloadStatus.cancelled,
          ),
        ),
      ),
    ];
  }

  static void _reveal(String path) {
    if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      Process.run('explorer.exe', ['/select,', path]);
    }
  }

  static (String, Color) _status(DownloadTask t) => switch (t.status) {
    DownloadStatus.queued => ('QUEUED', HudColors.purple),
    DownloadStatus.connecting => ('CONNECTING', HudColors.cyan),
    DownloadStatus.downloading => ('DOWNLOADING', HudColors.cyan),
    DownloadStatus.refreshingLink => ('REFRESHING LINK', HudColors.warning),
    DownloadStatus.paused => ('PAUSED', HudColors.warning),
    DownloadStatus.verifying => ('VERIFYING SHA1', HudColors.cyan),
    DownloadStatus.completed => switch (t.verification) {
      VerificationState.passed => ('VERIFIED', HudColors.success),
      VerificationState.pending => ('VERIFY PENDING', HudColors.warning),
      VerificationState.unavailable => ('STORED · NO HASH', HudColors.success),
      _ => ('STORED', HudColors.success),
    },
    DownloadStatus.failed => (
      t.verification == VerificationState.failed ? 'HASH MISMATCH' : 'FAILED',
      HudColors.danger,
    ),
    DownloadStatus.cancelled => ('CANCELLED', HudColors.textMuted),
  };
}

class _SpeedCapMenu extends ConsumerWidget {
  const _SpeedCapMenu({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capMb = task.speedLimitBytesPerSecond ~/ (1024 * 1024);
    return PopupMenuButton<int>(
      tooltip: 'Per-download speed cap',
      color: HudColors.surface,
      icon: Icon(
        Icons.speed_rounded,
        size: 18,
        color: capMb > 0 ? HudColors.warning : HudColors.textMuted,
      ),
      onSelected: (v) => ref
          .read(downloadActionsProvider)
          .run((m) => m.setTaskSpeedLimit(task.id, v * 1024 * 1024)),
      itemBuilder: (_) => [
        for (final c in const [0, 2, 5, 10, 25, 50])
          CheckedPopupMenuItem(
            value: c,
            checked: c == capMb,
            child: Text(
              c == 0 ? 'No cap' : '$c MB/s',
              style: HudTheme.telemetry(size: 12, color: HudColors.textPrimary),
            ),
          ),
      ],
    );
  }
}

/// Per-thread visualizer: the file's byte range with one segment per chunk,
/// each filled to its progress and lit by its current speed.
class _ThreadVisualizer extends StatelessWidget {
  const _ThreadVisualizer({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final peak = progress.chunks.fold<double>(
      1,
      (m, c) => c.bytesPerSecond > m ? c.bytesPerSecond : m,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 12,
          child: CustomPaint(painter: _ChunkPainter(progress, peak)),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: Row(
            children: [
              for (final c in progress.chunks.where((c) => c.active).take(16))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message:
                        'Thread ${c.index}: ${formatRate(c.bytesPerSecond)}\n'
                        '${formatBytes(c.downloaded)} / ${formatBytes(c.length)}',
                    child: Container(
                      width: 26,
                      alignment: Alignment.bottomCenter,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        heightFactor: (c.bytesPerSecond / peak).clamp(
                          0.08,
                          1.0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [HudColors.purple, HudColors.cyan],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                'per-thread',
                style: HudTheme.telemetry(size: 10, color: HudColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChunkPainter extends CustomPainter {
  _ChunkPainter(this.progress, this.peak);

  final DownloadProgress progress;
  final double peak;

  @override
  void paint(Canvas canvas, Size size) {
    final total = progress.totalBytes;
    if (total <= 0) return;
    final bg = Paint()..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      bg,
    );
    for (final c in progress.chunks) {
      final x0 = c.start / total * size.width;
      final w = c.length / total * size.width;
      final filled = w * c.fraction.clamp(0, 1);
      final heat = c.active
          ? (0.55 + 0.45 * (c.bytesPerSecond / peak)).clamp(0.0, 1.0)
          : 0.55;
      final color = c.fraction >= 1
          ? HudColors.cyan.withValues(alpha: 0.55)
          : Color.lerp(HudColors.purple, HudColors.cyan, heat)!;
      canvas.drawRect(
        Rect.fromLTWH(x0, 0, filled, size.height),
        Paint()..color = color,
      );
      if (c.active && c.fraction < 1) {
        // Glowing write head.
        canvas.drawRect(
          Rect.fromLTWH(x0 + filled - 1.5, -1, 3, size.height + 2),
          Paint()
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
      // Chunk boundary.
      canvas.drawRect(
        Rect.fromLTWH(x0, 0, 1, size.height),
        Paint()..color = HudColors.background.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChunkPainter old) => old.progress != progress;
}
