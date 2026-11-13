import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/hud_theme.dart';
import '../../../domain/entities/ios_device.dart';
import '../../../services/device/contacts_service.dart';
import '../../../services/device/contacts_sync_service.dart';
import '../../providers/core_providers.dart';
import '../../providers/device_providers.dart';
import '../../widgets/hud_widgets.dart';
import 'device_widgets.dart';

final contactsSyncServiceProvider = Provider<ContactsSyncService>(
  (ref) => ContactsSyncService(
    ref.watch(deviceToolchainProvider),
    workDir: ref.watch(appSupportDirProvider),
  ),
);

/// The iPhone's contacts, read live over its sync service.
final liveContactsProvider = FutureProvider.autoDispose
    .family<List<DeviceContact>, String>(
      (ref, udid) => ref.watch(contactsSyncServiceProvider).read(udid),
    );

/// Contacts read and written directly on the iPhone: browse, add, edit,
/// import a vCard or a backup's contacts onto the device.
class LiveContacts extends ConsumerStatefulWidget {
  const LiveContacts({super.key, required this.device});

  final ConnectedDevice device;

  @override
  ConsumerState<LiveContacts> createState() => _LiveContactsState();
}

class _LiveContactsState extends ConsumerState<LiveContacts> {
  String _query = '';
  String? _selected;
  bool _busy = false;

  /// Contacts ticked for a bulk action (delete, export).
  final Set<String> _checked = {};

  Future<void> _deleteChecked(List<DeviceContact> all) async {
    final ids = [
      for (final c in all)
        if (_checked.contains(c.id)) c.id,
    ];
    if (ids.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: trf('Delete {0} contacts from the iPhone?', [ids.length]),
      message: tr(
        'The contacts are removed from the iPhone. This cannot be undone.',
      ),
      confirmLabel: tr('Delete'),
      danger: true,
    );
    if (!ok) return;
    await _write(
      trf('{0} contacts deleted from the iPhone', [ids.length]),
      const [],
      delete: ids,
    );
    if (mounted) setState(_checked.clear);
  }

  Future<void> _exportChecked(List<DeviceContact> all) async {
    final list = [
      for (final c in all)
        if (_checked.contains(c.id)) c,
    ];
    if (list.isEmpty) return;
    final loc = await getSaveLocation(
      suggestedName: 'Contacts_${list.length}.vcf',
      acceptedTypeGroups: [
        XTypeGroup(label: tr('vCard'), extensions: const ['vcf']),
      ],
    );
    if (loc == null || !mounted) return;
    final ok = await runDeviceAction(
      context,
      trf('Exported {0} contact(s) to {1}', [
        list.length,
        p.basename(loc.path),
      ]),
      () => File(loc.path).writeAsString(deviceContactsToVCard(list)),
    );
    if (ok) revealPath(loc.path);
  }

  String get _udid => widget.device.udid!;

  Future<void> _write(
    String done,
    List<DeviceContact> contacts, {
    List<String> delete = const [],
  }) async {
    if (contacts.isEmpty && delete.isEmpty) return;
    setState(() => _busy = true);
    try {
      await runDeviceAction(
        context,
        done,
        () => ref
            .read(contactsSyncServiceProvider)
            .write(_udid, contacts, delete: delete),
      );
      ref.invalidate(liveContactsProvider(_udid));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([DeviceContact? c]) async {
    final result = await showDialog<DeviceContact>(
      context: context,
      builder: (_) => _ContactEditor(contact: c),
    );
    if (result == null || !mounted) return;
    // Numbers / addresses cleared in the editor are deleted on the iPhone.
    final kept = {
      for (final f in [...result.phones, ...result.emails]) f.id,
    };
    final removed = [
      for (final f in [...?c?.phones, ...?c?.emails])
        if (f.id.isNotEmpty && !kept.contains(f.id)) f.id,
    ];
    await _write(
      c == null
          ? trf('{0} added to the iPhone', [result.displayName])
          : trf('{0} updated on the iPhone', [result.displayName]),
      [result],
      delete: removed,
    );
  }

  Future<void> _delete(DeviceContact c) async {
    final ok = await confirmDialog(
      context,
      title: trf('Delete {0} from the iPhone?', [c.displayName]),
      message: tr(
        'The contact is removed from the iPhone. This cannot be undone.',
      ),
      confirmLabel: tr('Delete'),
      danger: true,
    );
    if (!ok) return;
    await _write(
      trf('{0} deleted from the iPhone', [c.displayName]),
      const [],
      delete: [c.id],
    );
  }

  /// Adds the [incoming] contacts the iPhone doesn't have yet.
  Future<void> _import(
    List<DeviceContact> incoming,
    List<DeviceContact> existing,
  ) async {
    final fresh = [
      for (final c in incoming)
        if (!existing.any(c.sameAs)) c,
    ];
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: trf('Add {0} contacts to the iPhone?', [fresh.length]),
      message: trf(
        '{0} of {1} contacts are new; the other {2} are already on the iPhone and are skipped. Nothing on the iPhone is deleted.',
        [fresh.length, incoming.length, incoming.length - fresh.length],
      ),
      confirmLabel: tr('Add'),
    );
    if (!ok || fresh.isEmpty) return;
    await _write(
      trf('{0} contacts added to the iPhone', [fresh.length]),
      fresh,
    );
  }

  Future<void> _importVcf(List<DeviceContact> existing) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('vCard'), extensions: const ['vcf']),
      ],
    );
    if (file == null) return;
    final cards = parseVCards(await File(file.path).readAsString());
    if (cards.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('No contacts found in that file.'))),
        );
      }
      return;
    }
    await _import(cards, existing);
  }

  Future<void> _importBackup(List<DeviceContact> existing) async {
    final root = p.join(ref.read(deviceDataDirProvider), 'Backups');
    final sources = BackupContacts.sourcesFor(
      _udid,
      appBackupRoot: root,
    ).where((s) => !s.encrypted).toList();
    if (sources.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              tr('No unencrypted backup of this iPhone with contacts.'),
            ),
          ),
        );
      }
      return;
    }
    final list = await BackupContacts.load(sources.first.directory);
    await _import([
      for (final c in list)
        DeviceContact(
          first: c.first ?? '',
          last: c.last ?? '',
          middle: c.middle ?? '',
          company: c.organization ?? '',
          note: c.note ?? '',
          phones: [
            for (final v in c.phones)
              ContactField(value: v.value, label: v.label ?? ''),
          ],
          emails: [
            for (final v in c.emails)
              ContactField(value: v.value, label: v.label ?? ''),
          ],
        ),
    ], existing);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(liveContactsProvider(_udid));
    return async.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              tr('Reading contacts from the iPhone…'),
              style: TextStyle(color: HudColors.textMuted),
            ),
          ],
        ),
      ),
      error: (e, _) => DeviceCard(
        title: tr('Contacts on the iPhone'),
        icon: Icons.contacts_rounded,
        child: DeviceError(
          e,
          onRetry: () => ref.invalidate(liveContactsProvider(_udid)),
        ),
      ),
      data: (all) {
        final q = _query.toLowerCase();
        final shown = [
          for (final c in all)
            if (q.isEmpty ||
                c.displayName.toLowerCase().contains(q) ||
                c.phones.any((f) => f.value.contains(q)) ||
                c.emails.any((f) => f.value.toLowerCase().contains(q)))
              c,
        ];
        final selected =
            all.where((c) => c.id == _selected).firstOrNull ??
            shown.firstOrNull;
        _checked.removeWhere((id) => !all.any((c) => c.id == id));
        final allShownChecked =
            shown.isNotEmpty && shown.every((c) => _checked.contains(c.id));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: tr('Search name, number, email'),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Text(
                  trf('{0} contacts on the iPhone', [all.length]),
                  style: HudTheme.telemetry(
                    size: 12.5,
                    color: HudColors.textMuted,
                  ),
                ),
                NeonButton(
                  label: tr('Add contact'),
                  icon: Icons.person_add_alt_1_rounded,
                  compact: true,
                  onPressed: _busy ? null : () => _edit(),
                ),
                NeonButton(
                  label: tr('Import vCard'),
                  icon: Icons.upload_file_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: _busy ? null : () => _importVcf(all),
                ),
                NeonButton(
                  label: tr('Restore from backup'),
                  icon: Icons.settings_backup_restore_rounded,
                  variant: NeonVariant.ghost,
                  compact: true,
                  onPressed: _busy ? null : () => _importBackup(all),
                ),
                HudIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: tr('Reload'),
                  onPressed: _busy
                      ? null
                      : () => ref.invalidate(liveContactsProvider(_udid)),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: GlassPanel(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Select all + the bulk actions for the ticked ones.
                          Row(
                            children: [
                              Checkbox(
                                value: _checked.isEmpty
                                    ? false
                                    : (allShownChecked ? true : null),
                                tristate: true,
                                onChanged: shown.isEmpty
                                    ? null
                                    : (_) => setState(() {
                                        if (allShownChecked) {
                                          _checked.removeAll(
                                            shown.map((c) => c.id),
                                          );
                                        } else {
                                          _checked.addAll(
                                            shown.map((c) => c.id),
                                          );
                                        }
                                      }),
                              ),
                              Expanded(
                                child: Text(
                                  _checked.isEmpty
                                      ? tr('Select all')
                                      : trf('{0} selected', [_checked.length]),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_checked.isNotEmpty) ...[
                                HudIconButton(
                                  icon: Icons.ios_share_rounded,
                                  tooltip: tr('Export selected as vCard'),
                                  onPressed: () => _exportChecked(all),
                                ),
                                HudIconButton(
                                  icon: Icons.delete_outline_rounded,
                                  tooltip: tr('Delete selected'),
                                  color: HudColors.danger,
                                  onPressed: _busy
                                      ? null
                                      : () => _deleteChecked(all),
                                ),
                                HudIconButton(
                                  icon: Icons.close_rounded,
                                  tooltip: tr('Clear selection'),
                                  onPressed: () => setState(_checked.clear),
                                ),
                              ],
                            ],
                          ),
                          Divider(height: 1, color: HudColors.glassBorder),
                          Expanded(
                            child: shown.isEmpty
                                ? EmptyState(
                                    icon: Icons.contacts_outlined,
                                    title: tr('No contacts'),
                                  )
                                : ListView.builder(
                                    itemCount: shown.length,
                                    itemBuilder: (_, i) {
                                      final c = shown[i];
                                      final sel = c.id == selected?.id;
                                      return ListTile(
                                        dense: true,
                                        selected: sel,
                                        selectedTileColor: HudColors.cyan
                                            .withValues(alpha: 0.12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        leading: Checkbox(
                                          value: _checked.contains(c.id),
                                          onChanged: (v) => setState(
                                            () => v == true
                                                ? _checked.add(c.id)
                                                : _checked.remove(c.id),
                                          ),
                                        ),
                                        title: Text(
                                          c.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: c.phones.isEmpty
                                            ? null
                                            : Text(
                                                c.phones.first.value,
                                                textDirection:
                                                    TextDirection.ltr,
                                              ),
                                        onTap: () =>
                                            setState(() => _selected = c.id),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: selected == null
                        ? const SizedBox.shrink()
                        : _Details(
                            contact: selected,
                            onEdit: _busy ? null : () => _edit(selected),
                            onDelete: _busy ? null : () => _delete(selected),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  final DeviceContact contact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return DeviceCard(
      title: c.displayName,
      icon: Icons.person_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeonButton(
            label: tr('Edit'),
            icon: Icons.edit_rounded,
            variant: NeonVariant.ghost,
            compact: true,
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),
          HudIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: tr('Delete'),
            color: HudColors.danger,
            onPressed: onDelete,
          ),
        ],
      ),
      child: InfoTable([
        if (c.company.isNotEmpty) (tr('Company'), c.company),
        for (final f in c.phones)
          (f.label.isEmpty ? tr('Phone') : tr(_cap(f.label)), f.value),
        for (final f in c.emails)
          (f.label.isEmpty ? tr('Email') : tr(_cap(f.label)), f.value),
        if (c.note.isNotEmpty) (tr('Note'), c.note),
      ]),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Add or edit a contact (names, company, phones, emails, note).
class _ContactEditor extends StatefulWidget {
  const _ContactEditor({this.contact});

  final DeviceContact? contact;

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  late final _first = TextEditingController(text: widget.contact?.first);
  late final _last = TextEditingController(text: widget.contact?.last);
  late final _company = TextEditingController(text: widget.contact?.company);
  late final _note = TextEditingController(text: widget.contact?.note);
  late final List<(String, TextEditingController)> _phones = [
    for (final f in widget.contact?.phones ?? const <ContactField>[])
      (f.id, TextEditingController(text: f.value)),
  ];
  late final List<(String, TextEditingController)> _emails = [
    for (final f in widget.contact?.emails ?? const <ContactField>[])
      (f.id, TextEditingController(text: f.value)),
  ];

  @override
  void initState() {
    super.initState();
    if (_phones.isEmpty) _phones.add(('', TextEditingController()));
    if (_emails.isEmpty) _emails.add(('', TextEditingController()));
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _company, _note]) {
      c.dispose();
    }
    for (final (_, c) in [..._phones, ..._emails]) {
      c.dispose();
    }
    super.dispose();
  }

  DeviceContact _result() {
    final old = widget.contact;
    List<ContactField> fields(
      List<(String, TextEditingController)> rows,
      List<ContactField> before,
      String label,
    ) => [
      for (final (id, c) in rows)
        if (c.text.trim().isNotEmpty)
          ContactField(
            id: id,
            value: c.text.trim(),
            label:
                before
                    .where((f) => f.id == id && id.isNotEmpty)
                    .firstOrNull
                    ?.label ??
                label,
          ),
    ];
    return DeviceContact(
      id: old?.id ?? '',
      first: _first.text.trim(),
      last: _last.text.trim(),
      middle: old?.middle ?? '',
      company: _company.text.trim(),
      note: _note.text.trim(),
      phones: fields(_phones, old?.phones ?? const [], 'mobile'),
      emails: fields(_emails, old?.emails ?? const [], 'home'),
    );
  }

  Widget _field(TextEditingController c, String label, {bool ltr = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(isDense: true, labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.contact != null;
    return AlertDialog(
      title: Text(editing ? tr('Edit contact') : tr('New contact')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _field(_first, tr('First name'))),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_last, tr('Last name'))),
                ],
              ),
              _field(_company, tr('Company')),
              for (final (_, c) in _phones) _field(c, tr('Phone'), ltr: true),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _phones.add(('', TextEditingController())),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(tr('Add phone')),
                ),
              ),
              for (final (_, c) in _emails) _field(c, tr('Email'), ltr: true),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _emails.add(('', TextEditingController())),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(tr('Add email')),
                ),
              ),
              _field(_note, tr('Note')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final r = _result();
            if (r.displayName == '—' && r.phones.isEmpty && r.emails.isEmpty) {
              return;
            }
            Navigator.pop(context, r);
          },
          child: Text(editing ? tr('Save') : tr('Add to iPhone')),
        ),
      ],
    );
  }
}
