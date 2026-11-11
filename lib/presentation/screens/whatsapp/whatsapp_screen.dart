import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../core/utils/byte_format.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/whatsapp/wa_export.dart';
import '../../../services/whatsapp/wa_parser.dart';
import '../../providers/device_providers.dart';
import '../../providers/whatsapp_android_providers.dart';
import '../../providers/whatsapp_providers.dart';
import '../../widgets/hud_widgets.dart';
import '../devices/device_widgets.dart';
import 'whatsapp_android_source.dart';
import '../../../core/l10n/l10n.dart';

/// Decrypts a WhatsApp `.crypt15` backup with its key, reads the chats, and
/// exports them to a readable HTML page or CSV. Entirely local — nothing is
/// uploaded. (Inspired by wa-transfer; this is the archive/read half, which
/// works reliably, not the fragile "inject into an iPhone backup" half.)
class WhatsAppScreen extends ConsumerWidget {
  const WhatsAppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(waSourceModeProvider);
    final inputs = ref.watch(waInputsProvider);
    final archive = ref.watch(waArchiveProvider);
    final hasSource = switch (mode) {
      WaSourceMode.file => inputs.ready,
      WaSourceMode.android =>
        inputs.ready && ref.watch(waAndroidProvider).step == WaAndroidStep.done,
      WaSourceMode.iphone => ref.watch(waBackupDirProvider) != null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SourceToggle(),
          const SizedBox(height: 10),
          // The Android guide is tall: it scrolls on its own, and takes the
          // whole page until the chats are ready.
          if (mode == WaSourceMode.android && !hasSource)
            const Expanded(
              child: SingleChildScrollView(child: WaAndroidSource()),
            )
          else ...[
            switch (mode) {
              WaSourceMode.file => const _InputCard(),
              WaSourceMode.android => ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: const SingleChildScrollView(child: WaAndroidSource()),
              ),
              WaSourceMode.iphone => const _IphoneSource(),
            },
            const SizedBox(height: 14),
            Expanded(
              child: !hasSource
                  ? GlassPanel(
                      child: EmptyState(
                        icon: Icons.chat_rounded,
                        title: switch (mode) {
                          WaSourceMode.file => tr(
                            'Decrypt and read WhatsApp chats',
                          ),
                          WaSourceMode.android => tr(
                            'Get WhatsApp straight from an Android phone',
                          ),
                          WaSourceMode.iphone => tr(
                            'Read WhatsApp from an iPhone',
                          ),
                        },
                        message: switch (mode) {
                          WaSourceMode.file => tr(
                            'Pick a WhatsApp backup (msgstore.db.crypt15) and its key file. Everything is processed on this computer — nothing is uploaded. You can then browse the chats and export them to HTML or CSV.',
                          ),
                          WaSourceMode.android => tr(
                            'Connect the phone with USB debugging on. We read the 64-digit backup key from its screen, copy the encrypted backup over USB and decrypt it here. Nothing is uploaded.',
                          ),
                          WaSourceMode.iphone => tr(
                            'Back up the connected iPhone, then read its WhatsApp chats straight from the backup. Nothing is uploaded.',
                          ),
                        },
                      ),
                    )
                  : archive.when(
                      loading: () => GlassPanel(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(
                                tr('Decrypting and reading chats…'),
                                style: TextStyle(color: HudColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      error: (e, _) => GlassPanel(
                        child: DeviceError(
                          e,
                          onRetry: () => ref.invalidate(waArchiveProvider),
                        ),
                      ),
                      data: (a) => a == null
                          ? const SizedBox.shrink()
                          : _Browser(archive: a),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceToggle extends ConsumerWidget {
  const _SourceToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(waSourceModeProvider);
    return Row(
      children: [
        HudChipTab(
          label: tr('From file'),
          active: mode == WaSourceMode.file,
          onTap: () =>
              ref.read(waSourceModeProvider.notifier).set(WaSourceMode.file),
        ),
        HudChipTab(
          label: tr('From Android'),
          active: mode == WaSourceMode.android,
          onTap: () =>
              ref.read(waSourceModeProvider.notifier).set(WaSourceMode.android),
        ),
        HudChipTab(
          label: tr('From iPhone'),
          active: mode == WaSourceMode.iphone,
          onTap: () =>
              ref.read(waSourceModeProvider.notifier).set(WaSourceMode.iphone),
        ),
      ],
    );
  }
}

/// Reads WhatsApp straight from a connected iPhone's local backup.
class _IphoneSource extends ConsumerWidget {
  const _IphoneSource();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref
        .watch(devicesProvider)
        .devices
        .where((d) => d.mode.isBooted && d.pairState == PairState.paired)
        .toList();
    if (devices.isEmpty) {
      return GlassPanel(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.phone_iphone_rounded,
              size: 18,
              color: HudColors.textMuted,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Connect and trust an iPhone to read its WhatsApp chats.'),
                style: TextStyle(color: HudColors.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    // Default to the first usable device.
    final device = devices.first;
    final job = ref.watch(backupJobProvider);
    final backingUp = job.status == JobStatus.running;
    final sources = ref.watch(waBackupSourcesProvider(device.udid!));
    final selected = ref.watch(waBackupDirProvider);

    Future<void> backup() async {
      final root = p.join(ref.read(deviceDataDirProvider), 'Backups');
      await ref
          .read(backupJobProvider.notifier)
          .run(
            trf('Backup of {0}', [device.displayName]),
            () => ref.read(deviceServiceProvider).startBackup(device, root),
          );
      ref.invalidate(waBackupSourcesProvider(device.udid!));
    }

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone_rounded, size: 18, color: HudColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: HudLabel(
                  device.displayName,
                  color: HudColors.textPrimary,
                ),
              ),
              NeonButton(
                label: backingUp ? tr('Backing up…') : tr('Back up now'),
                icon: Icons.backup_rounded,
                variant: NeonVariant.ghost,
                compact: true,
                onPressed: backingUp ? null : backup,
              ),
            ],
          ),
          if (backingUp) ...[
            const SizedBox(height: 8),
            GlowProgressBar(value: job.progress ?? 0, height: 4),
          ],
          const SizedBox(height: 10),
          sources.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => DeviceError(e),
            data: (list) => list.isEmpty
                ? Text(
                    tr(
                      'No backup with WhatsApp yet. Press "Back up now" (make sure backup encryption is off, in Devices → Backup).',
                    ),
                    style: TextStyle(
                      color: HudColors.textMuted,
                      fontSize: 12.5,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in list)
                        HudChipTab(
                          label: s.date == null
                              ? s.origin
                              : '${s.origin} · ${_fmtDate(s.date!)}',
                          active: s.directory == selected,
                          onTap: () => ref
                              .read(waBackupDirProvider.notifier)
                              .set(s.directory),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _InputCard extends ConsumerWidget {
  const _InputCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inputs = ref.watch(waInputsProvider);
    final ctl = ref.read(waInputsProvider.notifier);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.chat_rounded, size: 18, color: HudColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: HudLabel(
                  tr('WhatsApp chat archive'),
                  color: HudColors.textPrimary,
                ),
              ),
              if (inputs.dbPath != null)
                NeonButton(
                  label: tr('Clear'),
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: () {
                    ctl.clear();
                    ref.read(waSelectedChatProvider.notifier).set(null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _FileRow(
            label: tr('Backup'),
            hint: tr('msgstore.db.crypt15 (or a decrypted msgstore.db)'),
            value: inputs.dbPath,
            onPick: () async {
              final f = await openFile(
                acceptedTypeGroups: [
                  XTypeGroup(
                    label: tr('WhatsApp database'),
                    extensions: ['crypt15', 'crypt14', 'crypt12', 'db'],
                  ),
                ],
              );
              if (f != null) {
                ctl.setDb(f.path);
                ref.read(waSelectedChatProvider.notifier).set(null);
              }
            },
          ),
          if (inputs.encrypted) ...[
            const SizedBox(height: 8),
            _FileRow(
              label: tr('Key file'),
              hint: inputs.keyHex?.length == 64
                  ? tr('Using the pasted 64-character key')
                  : tr('The WhatsApp "key" file, or paste a 64-char key →'),
              value: inputs.keyHex?.length == 64 ? null : inputs.keyPath,
              onPick: () async {
                final f = await openFile();
                if (f != null) {
                  ctl.setKey(f.path);
                  ctl.setKeyHex(null);
                }
              },
              trailing: SizedBox(
                width: 150,
                height: 34,
                child: TextField(
                  onChanged: (v) {
                    final hex = v.trim().toLowerCase();
                    ctl.setKeyHex(
                      hex.length == 64 ? hex : (hex.isEmpty ? null : hex),
                    );
                  },
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('or hex key'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'The key file is at /data/data/com.whatsapp/files/key on the phone (needs root), or shown as a 64-digit code under WhatsApp → Chats → Chat backup → End-to-end encrypted backup.',
              ),
              style: TextStyle(
                color: HudColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onPick,
    this.trailing,
  });

  final String label;
  final String hint;
  final String? value;
  final VoidCallback onPick;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
      Expanded(
        child: Container(
          height: 34,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: HudColors.overlay.withValues(alpha: 0.03),
            border: Border.all(
              color: HudColors.overlay.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            value ?? hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: value == null
                  ? HudColors.textMuted
                  : HudColors.textPrimary,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      NeonButton(
        label: tr('Choose…'),
        icon: Icons.folder_open_rounded,
        variant: NeonVariant.ghost,
        compact: true,
        onPressed: onPick,
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class _Browser extends ConsumerWidget {
  const _Browser({required this.archive});

  final WaArchive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(waSelectedChatProvider);
    final chat =
        archive.chats.where((c) => c.jid == selected).firstOrNull ??
        archive.chats.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryBar(archive: archive),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 300,
                child: _ChatList(archive: archive, selected: chat?.jid),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: chat == null
                    ? GlassPanel(
                        child: EmptyState(
                          icon: Icons.chat_outlined,
                          title: tr('No chats'),
                        ),
                      )
                    : _Thread(
                        key: ValueKey(chat.jid),
                        chat: chat,
                        messages: archive.messagesFor(chat.jid),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.archive});

  final WaArchive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassPanel(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            trf('{0} chats · {1} messages · {2} media', [
              archive.chatCount,
              archive.messageCount,
              archive.mediaCount,
            ]),
            style: HudTheme.telemetry(size: 12.5, color: HudColors.textPrimary),
          ),
        ),
        NeonButton(
          label: tr('Export HTML'),
          icon: Icons.html_rounded,
          compact: true,
          onPressed: () => _export(context, archive, html: true),
        ),
        const SizedBox(width: 8),
        NeonButton(
          label: tr('Export CSV'),
          icon: Icons.table_chart_rounded,
          variant: NeonVariant.ghost,
          compact: true,
          onPressed: () => _export(context, archive, html: false),
        ),
      ],
    ),
  );

  Future<void> _export(
    BuildContext context,
    WaArchive archive, {
    required bool html,
  }) async {
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final loc = await getSaveLocation(
      suggestedName: 'WhatsApp_$stamp.${html ? 'html' : 'csv'}',
      acceptedTypeGroups: [
        html
            ? XTypeGroup(label: tr('HTML'), extensions: ['html'])
            : XTypeGroup(label: tr('CSV'), extensions: ['csv']),
      ],
    );
    if (loc == null || !context.mounted) return;
    final ok = await runDeviceAction(
      context,
      trf('Exported {0} messages to {1}', [
        archive.messageCount,
        p.basename(loc.path),
      ]),
      () => File(loc.path).writeAsString(
        html ? WaExport.toHtml(archive) : WaExport.toCsv(archive),
      ),
    );
    if (ok) revealPath(loc.path);
  }
}

class _ChatList extends ConsumerStatefulWidget {
  const _ChatList({required this.archive, required this.selected});

  final WaArchive archive;
  final String? selected;

  @override
  ConsumerState<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<_ChatList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.archive.chats
        .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q))
        .toList();
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('Search chats'),
              prefixIcon: Icon(Icons.search_rounded, size: 16),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final c = shown[i];
                final sel = c.jid == widget.selected;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      ref.read(waSelectedChatProvider.notifier).set(c.jid),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: sel
                          ? HudColors.cyan.withValues(alpha: 0.09)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          c.isGroup
                              ? Icons.groups_rounded
                              : Icons.person_rounded,
                          size: 24,
                          color: HudColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                trf('{0} messages', [c.messageCount]),
                                style: HudTheme.telemetry(
                                  size: 11,
                                  color: HudColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  const _Thread({super.key, required this.chat, required this.messages});

  final WaChat chat;
  final List<WaMessage> messages;

  String _day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    String? lastDay;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: HudColors.glassBorder)),
            ),
            child: Row(
              children: [
                Text(
                  chat.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                if (chat.isGroup) HudPill(tr('Group'), color: HudColors.purple),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_rounded,
                    title: tr('No messages'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final day = _day(m.timestampMs);
                      final showDay = day != lastDay;
                      lastDay = day;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDay)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    color: HudColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          _Bubble(
                            message: m,
                            isGroup: chat.isGroup,
                            time: _time(m.timestampMs),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isGroup,
    required this.time,
  });

  final WaMessage message;
  final bool isGroup;
  final String time;

  String get _body {
    final t = message.text;
    if (t != null && t.trim().isNotEmpty) return t;
    final label = switch (message.kind) {
      WaMediaKind.image => tr('📷 Photo'),
      WaMediaKind.video => tr('🎬 Video'),
      WaMediaKind.voice => tr('🎙️ Voice message'),
      WaMediaKind.audio => tr('🎵 Audio'),
      WaMediaKind.document => tr('📄 Document'),
      WaMediaKind.sticker => tr('Sticker'),
      WaMediaKind.gif => tr('GIF'),
      WaMediaKind.contact => tr('👤 Contact'),
      WaMediaKind.location => tr('📍 Location'),
      WaMediaKind.none => tr('(no text)'),
    };
    final name = message.mediaName == null ? '' : '\n${message.mediaName}';
    final size = message.mediaSize == null
        ? ''
        : ' · ${formatBytes(message.mediaSize!, decimals: 1)}';
    return '$label$size$name';
  }

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: me
              ? const Color(0xFF075E54).withValues(alpha: 0.55)
              : HudColors.overlay.withValues(alpha: 0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isGroup && !me && message.sender != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '+${message.sender!.split('@').first}',
                  style: TextStyle(
                    color: HudColors.cyan,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(_body, style: const TextStyle(fontSize: 13.5, height: 1.3)),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                time,
                style: TextStyle(color: HudColors.textMuted, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
