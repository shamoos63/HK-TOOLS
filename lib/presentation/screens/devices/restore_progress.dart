import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/restore/restore_insight.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// A firmware restore in progress (or just finished): one big percentage,
/// the current step in plain words, the step list, and, on failure, what
/// went wrong and what to try. The raw idevicerestore output sits behind
/// "Show technical details".
class RestoreProgressView extends ConsumerStatefulWidget {
  const RestoreProgressView({super.key, required this.state});

  final RestoreState state;

  @override
  ConsumerState<RestoreProgressView> createState() =>
      _RestoreProgressViewState();
}

class _RestoreProgressViewState extends ConsumerState<RestoreProgressView> {
  bool _showLog = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps the elapsed time moving between progress updates.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.state.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final failure = state.status == JobStatus.failed
        ? RestoreInsight.explain(state.log, aborted: state.aborted)
        : null;
    return ListView(
      children: [
        _ProgressCard(state: state),
        if (failure != null) ...[
          const SizedBox(height: 14),
          _FailureCard(state: state, failure: failure),
        ],
        const SizedBox(height: 14),
        _StepList(state: state),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showLog = !_showLog),
            icon: Icon(
              _showLog
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.terminal_rounded,
              size: 18,
            ),
            label: Text(
              _showLog
                  ? tr('Hide technical details')
                  : tr('Show technical details'),
            ),
            style: TextButton.styleFrom(foregroundColor: HudColors.textMuted),
          ),
        ),
        if (_showLog) _LogView(state: state),
      ],
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.state});

  final RestoreState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(restoreProvider.notifier);
    final req = state.request!;
    final progress = state.shownProgress;
    final color = switch (state.status) {
      JobStatus.succeeded => HudColors.success,
      JobStatus.failed => HudColors.danger,
      _ => HudColors.cyan,
    };
    final elapsed = (state.finishedAt ?? DateTime.now()).difference(
      state.startedAt ?? DateTime.now(),
    );
    final step = state.step == null ? null : RestoreInsight.info(state.step!);
    final (title, subtitle) = switch (state.status) {
      JobStatus.succeeded => (
        tr('Restore complete'),
        tr('The device is restarting. Finish setting it up on the device.'),
      ),
      JobStatus.failed when state.aborted => (
        tr('Restore stopped'),
        step == null
            ? tr('Stopped before the restore began.')
            : trf('Stopped during "{0}".', [tr(step.title)]),
      ),
      JobStatus.failed => (
        tr('Restore failed'),
        step == null
            ? tr('It stopped before the restore began.')
            : trf('It stopped during "{0}".', [tr(step.title)]),
      ),
      _ => (
        step != null ? tr(step.title) : tr('Getting ready'),
        tr(state.activity ?? step?.description ?? 'Starting…'),
      ),
    };

    return GlassPanel(
      glow: true,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.erase ? tr('Erase and restore') : tr('Update'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: HudColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        subtitle,
                        key: ValueKey(subtitle),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: HudColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (state.status == JobStatus.failed)
                Icon(Icons.error_rounded, size: 44, color: HudColors.danger)
              else if (state.status == JobStatus.succeeded)
                Icon(
                  Icons.check_circle_rounded,
                  size: 44,
                  color: HudColors.success,
                )
              else
                Text(
                  '${(progress * 100).floor()}%',
                  style: HudTheme.telemetry(
                    size: 40,
                    color: HudColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w700, height: 1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          GlowProgressBar(
            value: progress,
            height: 10,
            colors: [color, color],
            dimmed: state.status == JobStatus.failed,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${req.device.displayName}  ·  ${p.basename(req.ipswPath)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: HudColors.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: HudColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                _clock(elapsed),
                style: HudTheme.telemetry(size: 12, color: HudColors.textMuted),
              ),
            ],
          ),
          if (state.status == JobStatus.succeeded &&
              state.activation != AutoActivation.none) ...[
            const SizedBox(height: 12),
            _ActivationLine(state: state),
          ],
          const SizedBox(height: 16),
          if (state.running)
            Row(
              children: [
                Icon(Icons.usb_rounded, size: 16, color: HudColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      'Keep the device connected and this computer awake until the restore finishes.',
                    ),
                    style: TextStyle(color: HudColors.warning, fontSize: 12.5),
                  ),
                ),
                NeonButton(
                  label: tr('Stop'),
                  variant: NeonVariant.danger,
                  compact: true,
                  onPressed: () async {
                    if (await confirmDialog(
                      context,
                      title: tr('Stop the restore?'),
                      message: tr(
                        'Stopping now can leave the device in Recovery mode with no working system. It will then need another restore.',
                      ),
                      confirmLabel: tr('Stop restore'),
                      danger: true,
                      typeToConfirm: 'STOP',
                    )) {
                      ctl.abort();
                    }
                  },
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (req.logFile != null)
                  NeonButton(
                    label: tr('Open log file'),
                    variant: NeonVariant.ghost,
                    compact: true,
                    onPressed: () => revealPath(req.logFile!),
                  ),
                if (state.status == JobStatus.failed) ...[
                  const SizedBox(width: 8),
                  if (!req.erase &&
                      RestoreInsight.explain(
                        state.log,
                        aborted: state.aborted,
                      ).needsErase)
                    NeonButton(
                      label: tr('Try again with erase'),
                      icon: Icons.delete_forever_rounded,
                      variant: NeonVariant.danger,
                      compact: true,
                      onPressed: () async {
                        if (await confirmDialog(
                          context,
                          title: tr('Erase and restore?'),
                          message: tr(
                            'Everything on the device is erased and a clean system is installed. This cannot be undone.',
                          ),
                          confirmLabel: tr('Erase and restore'),
                          danger: true,
                          typeToConfirm: 'ERASE',
                        )) {
                          await ctl.retry(erase: true);
                        }
                      },
                    )
                  else
                    NeonButton(
                      label: tr('Try again'),
                      icon: Icons.refresh_rounded,
                      variant: NeonVariant.ghost,
                      compact: true,
                      onPressed: ctl.retry,
                    ),
                ],
                const SizedBox(width: 8),
                NeonButton(
                  label: tr('Done'),
                  compact: true,
                  onPressed: ctl.reset,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s'
        : '${d.inMinutes}:$s';
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.state, required this.failure});

  final RestoreState state;
  final RestoreFailure failure;

  @override
  Widget build(BuildContext context) => GlassPanel(
    tint: HudColors.danger,
    borderColor: HudColors.danger.withValues(alpha: 0.35),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(failure.title),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          tr(failure.message),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: HudColors.textPrimary,
          ),
        ),
        if (failure.tips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            tr('What to try'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: HudColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          for (final (i, tip) in failure.tips.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 10, top: 1),
                    decoration: BoxDecoration(
                      color: HudColors.overlay.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tr(tip),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (failure.detail != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            trf('Reported by the restore tool: {0}', [failure.detail]),
            style: TextStyle(fontSize: 12, color: HudColors.textMuted),
          ),
        ],
      ],
    ),
  );
}

/// Every step in order: done, in progress, still to come.
class _StepList extends StatelessWidget {
  const _StepList({required this.state});

  final RestoreState state;

  @override
  Widget build(BuildContext context) {
    final current = state.step;
    final currentIndex = current == null
        ? -1
        : RestoreInsight.order.indexOf(current);
    // Skipped steps (e.g. no modem on Wi-Fi iPads) count as done once a
    // later one starts.
    final steps = [
      for (final s in RestoreInsight.order)
        if (state.stepsSeen.contains(s) ||
            s != RestoreStep.flashBaseband ||
            state.running)
          s,
    ];
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: HudLabel(tr('Steps')),
          ),
          for (final s in steps)
            _StepRow(
              info: RestoreInsight.info(s),
              status: _status(s, currentIndex),
            ),
        ],
      ),
    );
  }

  _StepStatus _status(RestoreStep s, int currentIndex) {
    final i = RestoreInsight.order.indexOf(s);
    if (state.status == JobStatus.succeeded) return _StepStatus.done;
    if (s == state.step) {
      return switch (state.status) {
        JobStatus.failed => _StepStatus.failed,
        _ => _StepStatus.active,
      };
    }
    if (i < currentIndex) return _StepStatus.done;
    return _StepStatus.pending;
  }
}

enum _StepStatus { done, active, failed, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.info, required this.status});

  final StepInfo info;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (status) {
      _StepStatus.done => Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: HudColors.success,
      ),
      _StepStatus.active => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: HudColors.cyan),
      ),
      _StepStatus.failed => Icon(
        Icons.cancel_rounded,
        size: 18,
        color: HudColors.danger,
      ),
      _StepStatus.pending => Icon(
        Icons.circle_outlined,
        size: 18,
        color: HudColors.textMuted.withValues(alpha: 0.5),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 20, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(info.title),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: status == _StepStatus.active
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: status == _StepStatus.pending
                    ? HudColors.textMuted
                    : HudColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.state});

  final RestoreState state;

  @override
  Widget build(BuildContext context) => Container(
    height: 320,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: HudColors.overlay.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HudColors.glassBorder),
    ),
    child: SelectionArea(
      child: ListView(
        reverse: true,
        children: [
          for (final l in state.log.reversed)
            Text(
              l.line,
              style: TextStyle(
                fontFamily: HudTheme.monoFamily,
                fontFamilyFallback: HudTheme.monoFallback,
                fontSize: 11.5,
                height: 1.35,
                color: l.isError ? HudColors.danger : HudColors.textPrimary,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Automatic activation after a successful restore.
class _ActivationLine extends StatelessWidget {
  const _ActivationLine({required this.state});

  final RestoreState state;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text, Color color) = switch (state.activation) {
      AutoActivation.waiting => (
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        tr('Waiting for the device to start, then activating it…'),
        HudColors.textPrimary,
      ),
      AutoActivation.activating => (
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        tr('Activating with Apple…'),
        HudColors.textPrimary,
      ),
      AutoActivation.done => (
        Icon(Icons.verified_rounded, size: 18, color: HudColors.success),
        tr('Activated. The device is ready to set up.'),
        HudColors.success,
      ),
      AutoActivation.failed || AutoActivation.skipped => (
        Icon(Icons.info_outline_rounded, size: 18, color: HudColors.warning),
        state.activationNote ?? tr('The device was not activated.'),
        HudColors.warning,
      ),
      AutoActivation.none => (const SizedBox.shrink(), '', HudColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}
