import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'device_toolchain.dart';

/// A phone number or email address of a [DeviceContact].
class ContactField {
  const ContactField({this.id = '', required this.value, this.label = ''});

  /// Device record id; empty for a new one.
  final String id;
  final String value;
  final String label;

  factory ContactField.fromJson(Map<String, dynamic> j) => ContactField(
    id: '${j['id'] ?? ''}',
    value: '${j['value'] ?? ''}',
    label: '${j['label'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {'id': id, 'value': value, 'label': label};
}

/// A contact as stored on the iPhone (read and written live).
class DeviceContact {
  const DeviceContact({
    this.id = '',
    this.first = '',
    this.last = '',
    this.middle = '',
    this.company = '',
    this.note = '',
    this.phones = const [],
    this.emails = const [],
  });

  /// Device record id; empty for a contact that is not on the iPhone yet.
  final String id;
  final String first;
  final String last;
  final String middle;
  final String company;
  final String note;
  final List<ContactField> phones;
  final List<ContactField> emails;

  String get displayName {
    final n = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
    return n.isNotEmpty ? n : (company.isNotEmpty ? company : '—');
  }

  factory DeviceContact.fromJson(Map<String, dynamic> j) => DeviceContact(
    id: '${j['id'] ?? ''}',
    first: '${j['first'] ?? ''}',
    last: '${j['last'] ?? ''}',
    middle: '${j['middle'] ?? ''}',
    company: '${j['company'] ?? ''}',
    note: '${j['note'] ?? ''}',
    phones: [
      for (final f in (j['phones'] as List? ?? const []))
        ContactField.fromJson((f as Map).cast()),
    ],
    emails: [
      for (final f in (j['emails'] as List? ?? const []))
        ContactField.fromJson((f as Map).cast()),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'first': first,
    'last': last,
    'middle': middle,
    'company': company,
    'note': note,
    'phones': [for (final f in phones) f.toJson()],
    'emails': [for (final f in emails) f.toJson()],
  };

  /// Same person, by name and any phone number / email (for imports).
  bool sameAs(DeviceContact o) {
    String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
    final name = displayName.toLowerCase() == o.displayName.toLowerCase();
    final phone = phones.any(
      (a) => o.phones.any((b) {
        final x = digits(a.value), y = digits(b.value);
        return x.length >= 7 &&
            y.length >= 7 &&
            (x.endsWith(y.substring(y.length - 7)) &&
                y.endsWith(x.substring(x.length - 7)));
      }),
    );
    final email = emails.any(
      (a) =>
          o.emails.any((b) => a.value.toLowerCase() == b.value.toLowerCase()),
    );
    return name && (phones.isEmpty && emails.isEmpty || phone || email) ||
        phone ||
        email;
  }
}

class ContactsSyncException implements Exception {
  ContactsSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the iPhone's contacts directly over its sync service
/// (`com.apple.mobilesync`, what Finder / iTunes contact sync and 3uTools
/// use). The protocol runs in `assets/scripts/hk_contacts.py` on the Python
/// that pymobiledevice3 is installed with.
class ContactsSyncService {
  ContactsSyncService(this.tools, {required this.workDir});

  final DeviceToolchain tools;
  final String workDir;

  /// The Python interpreter pymobiledevice3 runs on (pipx / uv / pip).
  String? python() {
    final exe = tools.resolve(DeviceTool.pymobiledevice3);
    if (exe == null) return null;
    final real = File(exe).resolveSymbolicLinksSync();
    final dir = p.dirname(real);
    final candidates = <String>[
      if (Platform.isWindows) ...[
        p.join(dir, 'python.exe'),
        // uv tool install: <base>/uv/tools/pymobiledevice3/Scripts/python.exe
        p.join(
          p.dirname(dir),
          'uv',
          'tools',
          'pymobiledevice3',
          'Scripts',
          'python.exe',
        ),
      ] else ...[
        p.join(dir, 'python3'),
        p.join(dir, 'python'),
      ],
    ];
    // Script shims name their interpreter on the first lines
    // (`#!/…/python` or pipx's `'''exec' "/…/python" "$0"`).
    if (!Platform.isWindows) {
      try {
        final head = File(real).readAsLinesSync().take(3).join('\n');
        final m =
            RegExp(r"exec'\s+\x22([^\x22]+)\x22").firstMatch(head) ??
            RegExp(r'^#!\s*(\S*python\S*)', multiLine: true).firstMatch(head);
        if (m != null) candidates.insert(0, m.group(1)!);
      } on Object {
        // Binary launcher.
      }
    }
    return candidates.where((c) => File(c).existsSync()).firstOrNull;
  }

  Future<String> _script() async {
    final f = File(p.join(workDir, 'scripts', 'hk_contacts.py'));
    final text = await rootBundle.loadString('assets/scripts/hk_contacts.py');
    if (!f.existsSync() || f.readAsStringSync() != text) {
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }
    return f.path;
  }

  Future<Map<String, dynamic>> _run(List<String> args) async {
    final py = python();
    if (py == null) {
      throw ContactsSyncException(
        'pymobiledevice3 is needed to read and write contacts on the device. '
        'Install it from Settings › Device tools › Setup assistant.',
      );
    }
    final r = await Process.run(
      py,
      [await _script(), ...args],
      environment: const {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(minutes: 3));
    if (r.exitCode != 0) {
      final err = '${r.stderr}'
          .trim()
          .split('\n')
          .lastWhere(
            (l) => l.trim().isNotEmpty,
            orElse: () => 'exit code ${r.exitCode}',
          );
      throw ContactsSyncException(err.replaceFirst('ERROR: ', ''));
    }
    return jsonDecode('${r.stdout}') as Map<String, dynamic>;
  }

  Future<List<DeviceContact>> read(String udid) async {
    final out = await _run(['read', udid]);
    return [
      for (final c in (out['contacts'] as List? ?? const []))
        DeviceContact.fromJson((c as Map).cast()),
    ];
  }

  /// Adds new contacts (empty id), updates existing ones and deletes the
  /// records in [delete] (contact ids, or single phone / email ids).
  Future<int> write(
    String udid,
    List<DeviceContact> contacts, {
    List<String> delete = const [],
  }) async {
    final f = File(
      p.join(
        workDir,
        'scripts',
        'changes-${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode({
        'upsert': [for (final c in contacts) c.toJson()],
        'delete': delete,
      }),
    );
    try {
      final out = await _run(['write', udid, f.path]);
      return (out['written'] as num?)?.toInt() ?? contacts.length;
    } finally {
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// Contacts in a vCard file (2.1 / 3.0 / 4.0): names, organisation, note,
/// phone numbers and emails.
List<DeviceContact> parseVCards(String text) {
  final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  final out = <DeviceContact>[];
  for (final block
      in unfolded.split(RegExp(r'BEGIN:VCARD', caseSensitive: false)).skip(1)) {
    var first = '', last = '', middle = '', company = '', note = '', fn = '';
    final phones = <ContactField>[], emails = <ContactField>[];
    for (final raw in block.split(RegExp(r'\r?\n'))) {
      final i = raw.indexOf(':');
      if (i <= 0) continue;
      final head = raw.substring(0, i).toUpperCase();
      final rawValue = raw.substring(i + 1).trim();
      String unescape(String v) => v
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\,', ',')
          .replaceAll(r'\;', ';')
          .replaceAll(r'\\', r'\');
      // Structured values (N, ORG) split on unescaped semicolons.
      List<String> parts() =>
          rawValue.split(RegExp(r'(?<!\\);')).map(unescape).toList();
      final value = unescape(rawValue);
      final name = head.split(';').first.split('.').last;
      String label() {
        final m = RegExp(r'TYPE=([^;:]+)').firstMatch(head);
        final t = (m?.group(1) ?? head.split(';').skip(1).join(','))
            .toLowerCase()
            .split(',')
            .where((x) => x != 'pref' && x != 'voice' && x != 'internet')
            .firstOrNull;
        return switch (t) {
          'cell' => 'mobile',
          null || '' => '',
          _ => t,
        };
      }

      switch (name) {
        case 'N':
          final n = parts();
          last = n.isNotEmpty ? n[0] : '';
          first = n.length > 1 ? n[1] : '';
          middle = n.length > 2 ? n[2] : '';
        case 'FN':
          fn = value;
        case 'ORG':
          company = parts().first;
        case 'NOTE':
          note = value;
        case 'TEL':
          if (value.isNotEmpty) {
            phones.add(ContactField(value: value, label: label()));
          }
        case 'EMAIL':
          if (value.isNotEmpty) {
            emails.add(ContactField(value: value, label: label()));
          }
      }
    }
    if (first.isEmpty && last.isEmpty && fn.isNotEmpty && company != fn) {
      first = fn;
    }
    final c = DeviceContact(
      first: first,
      last: last,
      middle: middle,
      company: company,
      note: note,
      phones: phones,
      emails: emails,
    );
    if (c.displayName != '—' || phones.isNotEmpty || emails.isNotEmpty)
      out.add(c);
  }
  return out;
}

/// vCard 3.0 for [contacts] (CRLF line endings).
String deviceContactsToVCard(List<DeviceContact> contacts) {
  String esc(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');
  final b = StringBuffer();
  void line(String s) => b.write('$s\r\n');
  for (final c in contacts) {
    line('BEGIN:VCARD');
    line('VERSION:3.0');
    line('N:${esc(c.last)};${esc(c.first)};${esc(c.middle)};;');
    line('FN:${esc(c.displayName == '—' ? '' : c.displayName)}');
    if (c.company.isNotEmpty) line('ORG:${esc(c.company)}');
    for (final f in c.phones) {
      final t = f.label == 'mobile' ? 'CELL' : f.label.toUpperCase();
      line('TEL${t.isEmpty ? '' : ';TYPE=$t'}:${f.value}');
    }
    for (final f in c.emails) {
      final t = f.label.toUpperCase();
      line('EMAIL;TYPE=INTERNET${t.isEmpty ? '' : ',$t'}:${f.value}');
    }
    if (c.note.isNotEmpty) line('NOTE:${esc(c.note)}');
    line('END:VCARD');
  }
  return b.toString();
}
