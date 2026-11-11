import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/device/contacts_service.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Backups of a device that may hold its contacts, newest first.
final contactsSourcesProvider = FutureProvider.autoDispose
    .family<List<ContactsSource>, String>((ref, udid) async {
      final root = p.join(ref.watch(deviceDataDirProvider), 'Backups');
      return BackupContacts.sourcesFor(udid, appBackupRoot: root);
    });

final contactsProvider = FutureProvider.autoDispose
    .family<List<Contact>, String>(
      (ref, backupDir) => BackupContacts.load(backupDir),
    );

enum _Filter { all, duplicates, noPhone }

/// Contacts from the device's local backups: browse, search, find duplicates,
/// export to vCard / CSV.
class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String? _source;
  String _query = '';
  _Filter _filter = _Filter.all;
  int? _selected;
  final Set<int> _checked = {};

  String get _udid => widget.device.udid!;

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(contactsSourcesProvider(_udid));
    final job = ref.watch(backupJobProvider);
    final backingUp = job.status == JobStatus.running;

    return sources.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => DeviceError(e),
      data: (list) {
        final source =
            list.where((s) => s.directory == _source).firstOrNull ??
            list.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SourceBar(
              sources: list,
              source: source,
              backingUp: backingUp,
              progress: job.progress,
              onPick: (s) => setState(() {
                _source = s.directory;
                _selected = null;
                _checked.clear();
              }),
              onBackup: _backup,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: source == null
                  ? GlassPanel(
                      child: EmptyState(
                        icon: Icons.contacts_rounded,
                        title: tr('No backup of this device yet'),
                        message: tr(
                          'Contacts are read from a local backup. Press "Back up now" to make one (it is also useful on its own).',
                        ),
                      ),
                    )
                  : _ContactsBody(
                      key: ValueKey(source.directory),
                      source: source,
                      query: _query,
                      filter: _filter,
                      selected: _selected,
                      checked: _checked,
                      onQuery: (q) => setState(() => _query = q),
                      onFilter: (f) => setState(() => _filter = f),
                      onSelect: (id) => setState(() => _selected = id),
                      onCheck: (id) => setState(
                        () => _checked.contains(id)
                            ? _checked.remove(id)
                            : _checked.add(id),
                      ),
                      onCheckAll: (ids) => setState(() {
                        if (ids.every(_checked.contains)) {
                          _checked.removeAll(ids);
                        } else {
                          _checked.addAll(ids);
                        }
                      }),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _backup() async {
    final root = p.join(ref.read(deviceDataDirProvider), 'Backups');
    await ref
        .read(backupJobProvider.notifier)
        .run(
          trf('Backup of {0}', [widget.device.displayName]),
          () =>
              ref.read(deviceServiceProvider).startBackup(widget.device, root),
        );
    if (!mounted) return;
    setState(() => _source = null);
    ref.invalidate(contactsSourcesProvider(_udid));
    ref.invalidate(contactsProvider);
  }
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({
    required this.sources,
    required this.source,
    required this.backingUp,
    required this.progress,
    required this.onPick,
    required this.onBackup,
  });

  final List<ContactsSource> sources;
  final ContactsSource? source;
  final bool backingUp;
  final double? progress;
  final ValueChanged<ContactsSource> onPick;
  final VoidCallback onBackup;

  static String label(ContactsSource s) {
    final d = s.date;
    final when = d == null
        ? tr('unknown date')
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return trf('{0} backup · {1}{2}', [
      s.origin,
      when,
      s.encrypted ? ' · encrypted' : '',
    ]);
  }

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.contacts_rounded, size: 18, color: HudColors.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: source == null
                  ? Text(
                      tr('No backup found'),
                      style: TextStyle(color: HudColors.textMuted),
                    )
                  : PopupMenuButton<ContactsSource>(
                      tooltip: tr('Choose backup'),
                      onSelected: onPick,
                      itemBuilder: (_) => [
                        for (final s in sources)
                          PopupMenuItem(value: s, child: Text(label(s))),
                      ],
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              label(source!),
                              overflow: TextOverflow.ellipsis,
                              style: HudTheme.telemetry(
                                size: 12.5,
                                color: HudColors.textPrimary,
                              ),
                            ),
                          ),
                          if (sources.length > 1)
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: HudColors.textMuted,
                            ),
                        ],
                      ),
                    ),
            ),
            NeonButton(
              label: backingUp ? tr('Backing up…') : tr('Back up now'),
              icon: Icons.backup_rounded,
              variant: NeonVariant.ghost,
              compact: true,
              onPressed: backingUp ? null : onBackup,
            ),
          ],
        ),
        if (backingUp) ...[
          const SizedBox(height: 8),
          GlowProgressBar(value: progress ?? 0, height: 4),
        ],
        const SizedBox(height: 6),
        Text(
          tr(
            'Read-only view of the contacts saved in the device\'s local backup. Nothing on the device is changed.',
          ),
          style: TextStyle(color: HudColors.textMuted, fontSize: 11.5),
        ),
      ],
    ),
  );
}

class _ContactsBody extends ConsumerWidget {
  const _ContactsBody({
    super.key,
    required this.source,
    required this.query,
    required this.filter,
    required this.selected,
    required this.checked,
    required this.onQuery,
    required this.onFilter,
    required this.onSelect,
    required this.onCheck,
    required this.onCheckAll,
  });

  final ContactsSource source;
  final String query;
  final _Filter filter;
  final int? selected;
  final Set<int> checked;
  final ValueChanged<String> onQuery;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onCheck;
  final ValueChanged<List<int>> onCheckAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsProvider(source.directory));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GlassPanel(child: DeviceError(e)),
      data: (all) {
        final dupGroups = findDuplicates(all);
        final dupIds = {
          for (final g in dupGroups)
            for (final c in g) c.id,
        };
        final q = query.toLowerCase();
        final digits = query.replaceAll(RegExp(r'\D'), '');
        final shown = all.where((c) {
          final match =
              q.isEmpty ||
              c.displayName.toLowerCase().contains(q) ||
              (c.organization?.toLowerCase().contains(q) ?? false) ||
              c.emails.any((e) => e.value.toLowerCase().contains(q)) ||
              (digits.length >= 3 &&
                  c.phones.any(
                    (t) =>
                        t.value.replaceAll(RegExp(r'\D'), '').contains(digits),
                  ));
          return match &&
              switch (filter) {
                _Filter.all => true,
                _Filter.duplicates => dupIds.contains(c.id),
                _Filter.noPhone => c.phones.isEmpty,
              };
        }).toList();
        final detail = all.where((c) => c.id == selected).firstOrNull;
        final exportSet = checked.isEmpty
            ? shown
            : all.where((c) => checked.contains(c.id)).toList();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 340,
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: onQuery,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr('Search name, number, email'),
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: [
                        HudChipTab(
                          label: trf('All {0}', [all.length]),
                          active: filter == _Filter.all,
                          onTap: () => onFilter(_Filter.all),
                        ),
                        HudChipTab(
                          label: trf('Duplicates {0}', [dupIds.length]),
                          active: filter == _Filter.duplicates,
                          onTap: () => onFilter(_Filter.duplicates),
                        ),
                        HudChipTab(
                          label: tr('No phone'),
                          active: filter == _Filter.noPhone,
                          onTap: () => onFilter(_Filter.noPhone),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value:
                              shown.isNotEmpty &&
                              shown.every((c) => checked.contains(c.id)),
                          tristate: false,
                          onChanged: shown.isEmpty
                              ? null
                              : (_) =>
                                    onCheckAll([for (final c in shown) c.id]),
                        ),
                        Expanded(
                          child: Text(
                            checked.isEmpty
                                ? '${shown.length} shown'
                                : '${checked.length} selected',
                            style: TextStyle(
                              fontSize: 12,
                              color: HudColors.textMuted,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: tr('Export'),
                          enabled: exportSet.isNotEmpty,
                          onSelected: (fmt) => _export(context, exportSet, fmt),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'vcf',
                              child: Text(
                                trf('Export {0} as vCard (.vcf)', [
                                  exportSet.length,
                                ]),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'csv',
                              child: Text(
                                trf('Export {0} as CSV', [exportSet.length]),
                              ),
                            ),
                          ],
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.ios_share_rounded,
                                  size: 16,
                                  color: HudColors.cyan,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  tr('Export'),
                                  style: TextStyle(
                                    color: HudColors.cyan,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text(
                                tr('No contacts'),
                                style: TextStyle(color: HudColors.textMuted),
                              ),
                            )
                          : ListView.builder(
                              itemCount: shown.length,
                              itemExtent: 52,
                              itemBuilder: (_, i) => _ContactTile(
                                contact: shown[i],
                                selected: shown[i].id == selected,
                                checked: checked.contains(shown[i].id),
                                duplicate: dupIds.contains(shown[i].id),
                                onTap: () => onSelect(shown[i].id),
                                onCheck: () => onCheck(shown[i].id),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: detail == null
                  ? GlassPanel(
                      child: EmptyState(
                        icon: Icons.person_outline_rounded,
                        title: tr('Select a contact'),
                      ),
                    )
                  : _ContactDetail(
                      contact: detail,
                      duplicates:
                          dupGroups
                              .where((g) => g.any((c) => c.id == detail.id))
                              .firstOrNull
                              ?.where((c) => c.id != detail.id)
                              .toList() ??
                          const [],
                      onSelect: onSelect,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _export(
    BuildContext context,
    List<Contact> contacts,
    String fmt,
  ) async {
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final loc = await getSaveLocation(
      suggestedName: 'Contacts_$stamp.$fmt',
      acceptedTypeGroups: [
        fmt == 'vcf'
            ? XTypeGroup(label: tr('vCard'), extensions: ['vcf'])
            : XTypeGroup(label: tr('CSV'), extensions: ['csv']),
      ],
    );
    if (loc == null || !context.mounted) return;
    final ok = await runDeviceAction(
      context,
      trf('Exported {0} contact(s) to {1}', [
        contacts.length,
        p.basename(loc.path),
      ]),
      () => File(loc.path)
          .writeAsString(fmt == 'vcf' ? toVCard(contacts) : toCsv(contacts)),
    );
    if (ok) revealPath(loc.path);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.contact, this.size = 34});

  final Contact contact;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: contact.photo != null
        ? Image.memory(
            contact.photo!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _letters(),
          )
        : _letters(),
  );

  Widget _letters() => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          HudColors.cyan.withValues(alpha: 0.35),
          HudColors.purple.withValues(alpha: 0.35),
        ],
      ),
    ),
    child: Text(
      contact.initials,
      style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.36),
    ),
  );
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.selected,
    required this.checked,
    required this.duplicate,
    required this.onTap,
    required this.onCheck,
  });

  final Contact contact;
  final bool selected;
  final bool checked;
  final bool duplicate;
  final VoidCallback onTap;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: selected ? HudColors.cyan.withValues(alpha: 0.09) : null,
      ),
      child: Row(
        children: [
          Checkbox(value: checked, onChanged: (_) => onCheck()),
          _Avatar(contact: contact),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  contact.phones.firstOrNull?.value ??
                      contact.emails.firstOrNull?.value ??
                      contact.organization ??
                      '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.telemetry(
                    size: 11,
                    color: HudColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (duplicate)
            Tooltip(
              message: tr('Shares a number or email with another contact'),
              child: Icon(
                Icons.copy_all_rounded,
                size: 15,
                color: HudColors.warning,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ContactDetail extends StatelessWidget {
  const _ContactDetail({
    required this.contact,
    required this.duplicates,
    required this.onSelect,
  });

  final Contact contact;
  final List<Contact> duplicates;
  final ValueChanged<int> onSelect;

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = contact;
    String lbl(String kind, String? label) =>
        label == null ? kind : '$kind ($label)';
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: ListView(
        children: [
          Row(
            children: [
              _Avatar(contact: c, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (c.jobTitle != null || c.organization != null)
                      Text(
                        [
                          ?c.jobTitle,
                          ?c.organization,
                          ?c.department,
                        ].join(' · '),
                        style: TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    if (c.nickname != null)
                      Text(
                        '"${c.nickname}"',
                        style: TextStyle(
                          color: HudColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          InfoTable([
            for (final t in c.phones) (lbl(tr('Phone'), t.label), t.value),
            for (final e in c.emails) (lbl(tr('Email'), e.label), e.value),
            for (final a in c.addresses)
              (lbl(tr('Address'), a.label), a.oneLine),
            for (final u in c.urls) (lbl(tr('Website'), u.label), u.value),
            (tr('Birthday'), c.birthday == null ? null : _date(c.birthday!)),
            (tr('Note'), c.note),
            (
              tr('Created'),
              c.created == null ? null : _date(c.created!.toLocal()),
            ),
            (
              tr('Modified'),
              c.modified == null ? null : _date(c.modified!.toLocal()),
            ),
          ], labelWidth: 150),
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: 18),
            HudLabel(tr('Possible duplicates'), color: HudColors.warning),
            const SizedBox(height: 6),
            for (final d in duplicates)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _Avatar(contact: d, size: 28),
                title: Text(d.displayName),
                subtitle: Text(
                  d.phones.firstOrNull?.value ??
                      d.emails.firstOrNull?.value ??
                      '',
                ),
                onTap: () => onSelect(d.id),
              ),
          ],
        ],
      ),
    );
  }
}
