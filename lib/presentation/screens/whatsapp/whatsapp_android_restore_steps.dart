import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../services/whatsapp/wa_android.dart';
import '../../providers/whatsapp_android_providers.dart';
import '../../providers/whatsapp_android_restore_providers.dart';
import '../../providers/whatsapp_backup_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';

/// "Restore to Android" as four big numbered steps. The step being worked on
/// is highlighted; finished steps fold up, fade back and show a check, and
/// can be reopened with a tap.
class WaAndroidRestoreSteps extends ConsumerStatefulWidget {
  const WaAndroidRestoreSteps({super.key, required this.backupDir});

  final String backupDir;

  @override
  ConsumerState<WaAndroidRestoreSteps> createState() => _State();
}

class _State extends ConsumerState<WaAndroidRestoreSteps> {
  final _number = TextEditingController();
  bool _appPicked = false;
  bool _numberConfirmed = false;

  /// A finished step the user tapped to change.
  int? _reopened;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  int get _digits => _number.text.replaceAll(RegExp(r'\D'), '').length;

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(waAndroidProvider);
    final ctl = ref.read(waAndroidProvider.notifier);
    final restore = ref.watch(waAndroidRestoreProvider);
    final flavors =
        ref.watch(waBackupFlavorsProvider(widget.backupDir)).value ??
        const <bool>[];
    final devices = (ref.watch(androidDevicesProvider).value ?? const [])
        .where((d) => d.state == AndroidDeviceState.ready)
        .toList();
    final phone =
        devices.where((d) => d.serial == flow.serial).firstOrNull ??
        devices.firstOrNull;
    if (phone != null && phone.serial != flow.serial) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ctl.selectDevice(phone.serial),
      );
    }
    final available = [
      for (final f in WaFlavor.values)
        if (flavors.isEmpty || flavors.contains(f == WaFlavor.business)) f,
    ];
    // A backup with only one of the two apps: nothing to choose.
    if (available.length == 1 && flow.flavor != available.single) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ctl.setFlavor(available.single),
      );
    }
    final busy = restore.running;
    final finished = restore.phase == WaAndroidRestorePhase.done;
    final app = flow.flavor == WaFlavor.business
        ? tr('WhatsApp Business')
        : tr('WhatsApp');

    final done1 = _appPicked || available.length == 1;
    final done2 = done1 && phone != null;
    final done3 = done2 && _numberConfirmed && _digits >= 6;
    final active = !done1
        ? 1
        : !done2
        ? 2
        : !done3
        ? 3
        : 4;
    bool open(int n) => !busy && !finished && (_reopened == n || active == n);
    void reopen(int n) {
      if (busy || finished) return;
      setState(() => _reopened = n);
    }

    final keepsChats = flow.step == WaAndroidStep.done && flow.keyHex != null;

    Future<void> start() async {
      final ok = await confirmDialog(
        context,
        title: trf('Restore {0} to {1}?', [app, phone!.displayName]),
        message: keepsChats
            ? trf(
                '{0} is removed from {1} and installed again, then the chats from this iPhone backup and the phone\'s own chats are put back. Keep the phone unlocked and connected.',
                [app, phone.displayName],
              )
            : trf(
                '{0} is removed from {1} and installed again, so the chats now on that phone are replaced by the ones from this iPhone backup. To keep them, first copy the phone\'s backup in "From Android". Keep the phone unlocked and connected.',
                [app, phone.displayName],
              ),
        confirmLabel: tr('Restore'),
      );
      if (!ok) return;
      await ref
          .read(waAndroidRestoreProvider.notifier)
          .restore(
            iphoneBackupDir: widget.backupDir,
            phoneNumber: _number.text,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.android_rounded, size: 22, color: HudColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Restore WhatsApp from this backup to an Android phone'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── 1. Which app ──
        _StepCard(
          number: 1,
          title: tr('Choose the app to move'),
          summary: app,
          done: done1 && !open(1),
          active: open(1),
          onReopen: () => reopen(1),
          child: Row(
            children: [
              for (final f in available) ...[
                if (f != available.first) const SizedBox(width: 12),
                Expanded(
                  child: _AppTile(
                    business: f == WaFlavor.business,
                    selected: flow.flavor == f && done1,
                    onTap: () {
                      ctl.setFlavor(f);
                      setState(() {
                        _appPicked = true;
                        _reopened = null;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── 2. Phone ──
        _StepCard(
          number: 2,
          title: tr('Connect the Android phone'),
          summary: phone?.displayName ?? '',
          done: done2 && !open(2),
          active: open(2),
          enabled: done1,
          onReopen: () => reopen(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hint(
                trf(
                  'Install {0} from Google Play and register it with your number. Then connect the phone with a USB cable and turn on USB debugging (Settings → About phone → tap Build number 7 times → Developer options → USB debugging).',
                  [app],
                ),
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      tr('Waiting for the phone…'),
                      style: TextStyle(color: HudColors.warning),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final d in devices)
                      _PhoneTile(
                        name: d.displayName,
                        selected: d.serial == phone?.serial,
                        onTap: () {
                          ctl.selectDevice(d.serial);
                          setState(() => _reopened = null);
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),

        // ── 3. Number ──
        _StepCard(
          number: 3,
          title: trf('The number {0} is registered with', [app]),
          summary: _number.text.trim(),
          done: done3 && !open(3),
          active: open(3),
          enabled: done2,
          onReopen: () => reopen(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hint(
                tr(
                  'With the country code. WhatsApp checks that the backup belongs to this number.',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _number,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: tr('e.g. +961 3 123456'),
                        prefixIcon: const Icon(Icons.phone_rounded),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (_digits >= 6) {
                          setState(() {
                            _numberConfirmed = true;
                            _reopened = null;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  NeonButton(
                    label: tr('Next'),
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _digits >= 6
                        ? () => setState(() {
                            _numberConfirmed = true;
                            _reopened = null;
                          })
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 4. Restore ──
        _StepCard(
          number: 4,
          title: tr('Restore'),
          summary: '',
          done: finished,
          active: done3 && !finished && _reopened == null || busy,
          enabled: done3 || busy || finished,
          // A finished restore keeps its instructions visible.
          forceOpen: finished || restore.phase == WaAndroidRestorePhase.failed,
          child: _RestorePanel(
            app: app,
            phoneName: phone?.displayName ?? '',
            keepsChats: keepsChats,
            onStart: phone == null ? null : start,
          ),
        ),
      ],
    );
  }
}

/// One numbered step: a big card when active, a faded one-line summary with
/// a check when done, dimmed when not reached yet.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.summary,
    required this.done,
    required this.active,
    required this.child,
    this.enabled = true,
    this.onReopen,
    this.forceOpen = false,
  });

  final int number;
  final String title;
  final String summary;
  final bool done;
  final bool active;
  final bool enabled;
  final bool forceOpen;
  final VoidCallback? onReopen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = done ? HudColors.success : HudColors.cyan;
    final showBody = active || forceOpen;
    final opacity = !enabled
        ? 0.35
        : done && !forceOpen
        ? 0.6
        : 1.0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: opacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(showBody ? 18 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: active
              ? accent.withValues(alpha: 0.07)
              : HudColors.overlay.withValues(alpha: 0.03),
          border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.6)
                : HudColors.glassBorder,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: done && !active ? onReopen : null,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done || active
                          ? accent
                          : HudColors.overlay.withValues(alpha: 0.08),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: done
                          ? const Icon(
                              Icons.check_rounded,
                              key: ValueKey('done'),
                              size: 20,
                              color: Colors.white,
                            )
                          : Text(
                              '$number',
                              key: const ValueKey('n'),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: active
                                    ? Colors.white
                                    : HudColors.textMuted,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: showBody ? 16 : 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (done && !showBody && summary.isNotEmpty) ...[
                    Flexible(
                      child: Text(
                        summary,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: HudColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: HudColors.textMuted,
                    ),
                  ],
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: showBody && enabled
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 48,
                        top: 14,
                      ),
                      child: child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.business,
    required this.selected,
    required this.onTap,
  });

  final bool business;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF25D366);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? green.withValues(alpha: 0.12)
              : HudColors.overlay.withValues(alpha: 0.04),
          border: Border.all(
            color: selected ? green : HudColors.glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: green,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    business ? Icons.storefront_rounded : Icons.chat_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                if (selected)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: HudColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: green,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              business ? tr('WhatsApp Business') : tr('WhatsApp'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              business
                  ? tr('The business app (green "B" icon)')
                  : tr('The regular app'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: HudColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected
            ? HudColors.success.withValues(alpha: 0.1)
            : HudColors.overlay.withValues(alpha: 0.04),
        border: Border.all(
          color: selected ? HudColors.success : HudColors.glassBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.phone_android_rounded,
            size: 26,
            color: selected ? HudColors.success : HudColors.textMuted,
          ),
          const SizedBox(width: 10),
          Text(
            name,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: HudColors.success,
            ),
          ],
        ],
      ),
    ),
  );
}

class _RestorePanel extends ConsumerWidget {
  const _RestorePanel({
    required this.app,
    required this.phoneName,
    required this.keepsChats,
    required this.onStart,
  });

  final String app;
  final String phoneName;
  final bool keepsChats;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restore = ref.watch(waAndroidRestoreProvider);
    final phases = [
      (
        WaAndroidRestorePhase.preparing,
        tr('Build the Android backup from the iPhone chats'),
      ),
      (
        WaAndroidRestorePhase.reinstalling,
        trf('Reinstall {0} on the phone', [app]),
      ),
      (
        WaAndroidRestorePhase.pushing,
        tr('Copy the backup and media to the phone'),
      ),
    ];
    final current = phases.indexWhere((x) => x.$1 == restore.phase);

    if (restore.phase == WaAndroidRestorePhase.done) {
      return _Done(app: app, installFailed: restore.installFailed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!restore.running) ...[
          _Hint(
            keepsChats
                ? tr('The chats already on the Android phone will be kept.')
                : trf(
                    '{0} on the phone is reinstalled, so its current chats are replaced. To keep them, copy the phone\'s backup in "From Android" first.',
                    [app],
                  ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: onStart,
              icon: const Icon(Icons.restore_rounded),
              label: Text(trf('Restore to {0}', [phoneName])),
            ),
          ),
        ] else
          for (var i = 0; i < phases.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: i < current
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: HudColors.success,
                            size: 22,
                          )
                        : i == current
                        ? const CircularProgressIndicator(strokeWidth: 2.5)
                        : Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: HudColors.textMuted,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: i < current ? 0.55 : (i == current ? 1 : 0.4),
                      child: Text(
                        phases[i].$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == current
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (restore.phase == WaAndroidRestorePhase.failed) ...[
          const SizedBox(height: 12),
          SelectableText(
            restore.error ?? tr('The restore failed.'),
            style: TextStyle(fontSize: 13, color: HudColors.danger),
          ),
        ],
      ],
    );
  }
}

/// What to do on the phone, with the key to type.
class _Done extends StatelessWidget {
  const _Done({required this.app, required this.installFailed});

  final String app;
  final bool installFailed;

  @override
  Widget build(BuildContext context) {
    final steps = [
      if (installFailed) trf('Install {0} from Google Play.', [app]),
      trf('Open {0} on the phone and tap Agree.', [app]),
      tr('Confirm your phone number.'),
      tr('When it finds the backup, tap Restore.'),
      tr('When it asks for the 64-digit key, enter 64 zeros:'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.celebration_rounded, color: HudColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('The backup is on the phone. Finish on the phone:'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: HudColors.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: HudColors.success),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 12, color: HudColors.success),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(steps[i], style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: HudColors.success.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  List.filled(16, '0000').join(' '),
                  style: HudTheme.telemetry(
                    size: 14,
                    color: HudColors.textPrimary,
                  ),
                ),
              ),
              HudIconButton(
                icon: Icons.copy_rounded,
                tooltip: tr('Copy key'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: '0' * 64)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13.5, height: 1.45, color: HudColors.textMuted),
  );
}
