import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/utils/plist.dart';

/// Contacts read from a local iOS backup (`AddressBook.sqlitedb`).
///
/// iOS exposes the address book to a computer only through backups (or the
/// MobileSync protocol). Reading a backup is side-effect free: nothing on the
/// device changes.
class Contact {
  const Contact({
    required this.id,
    this.first,
    this.last,
    this.middle,
    this.prefix,
    this.suffix,
    this.nickname,
    this.organization,
    this.department,
    this.jobTitle,
    this.note,
    this.birthday,
    this.phones = const [],
    this.emails = const [],
    this.urls = const [],
    this.addresses = const [],
    this.created,
    this.modified,
    this.photo,
  });

  final int id;
  final String? first;
  final String? last;
  final String? middle;
  final String? prefix;
  final String? suffix;
  final String? nickname;
  final String? organization;
  final String? department;
  final String? jobTitle;
  final String? note;
  final DateTime? birthday;
  final List<LabeledValue> phones;
  final List<LabeledValue> emails;
  final List<LabeledValue> urls;
  final List<PostalAddress> addresses;
  final DateTime? created;
  final DateTime? modified;

  /// JPEG thumbnail from AddressBookImages.sqlitedb.
  final Uint8List? photo;

  String get displayName {
    final name = [
      ?prefix,
      ?first,
      ?middle,
      ?last,
      ?suffix,
    ].where((s) => s.trim().isNotEmpty).join(' ');
    if (name.isNotEmpty) return name;
    if (organization?.isNotEmpty ?? false) return organization!;
    if (phones.isNotEmpty) return phones.first.value;
    if (emails.isNotEmpty) return emails.first.value;
    return 'No name';
  }

  String get sortKey =>
      (last?.isNotEmpty ?? false ? '$last $first' : displayName).toLowerCase();

  String get initials {
    final parts = [?first, ?last].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return displayName.characters1;
    return parts.map((s) => s.characters1).join();
  }

  Contact withPhoto(Uint8List? photo) => Contact(
    id: id,
    first: first,
    last: last,
    middle: middle,
    prefix: prefix,
    suffix: suffix,
    nickname: nickname,
    organization: organization,
    department: department,
    jobTitle: jobTitle,
    note: note,
    birthday: birthday,
    phones: phones,
    emails: emails,
    urls: urls,
    addresses: addresses,
    created: created,
    modified: modified,
    photo: photo,
  );
}

extension on String {
  String get characters1 =>
      isEmpty ? '?' : String.fromCharCode(runes.first).toUpperCase();
}

class LabeledValue {
  const LabeledValue(this.label, this.value);

  final String? label;
  final String value;
}

class PostalAddress {
  const PostalAddress({
    this.label,
    this.street,
    this.city,
    this.state,
    this.zip,
    this.country,
  });

  final String? label;
  final String? street;
  final String? city;
  final String? state;
  final String? zip;
  final String? country;

  String get oneLine => [
    ?street,
    ?city,
    ?state,
    ?zip,
    ?country,
  ].where((s) => s.trim().isNotEmpty).join(', ');
}

class ContactsException implements Exception {
  ContactsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A local backup that may hold contacts.
class ContactsSource {
  const ContactsSource({
    required this.directory,
    required this.origin,
    this.date,
    this.encrypted = false,
    this.deviceName,
    this.udid,
    this.productType,
  });

  /// `<backup root>/<udid>` (or `<root>/<name date>/<udid>`).
  final String directory;

  /// Device the backup was made from.
  final String? udid;
  final String? productType;

  /// "HK Tools" or "Finder / iTunes".
  final String origin;
  final DateTime? date;
  final bool encrypted;
  final String? deviceName;
}

abstract final class BackupContacts {
  /// Backup file id: SHA-1 of `<domain>-<relative path>`.
  static String fileId(String domain, String relativePath) =>
      sha1.convert(utf8.encode('$domain-$relativePath')).toString();

  static const _addressBook = 'Library/AddressBook/AddressBook.sqlitedb';
  static const _images = 'Library/AddressBook/AddressBookImages.sqlitedb';

  /// Path of a backed-up file (nested `ab/abcdef…` layout of iOS 10+, or the
  /// flat layout of older backups), or `null`.
  static String? backedUpFile(String backupDir, String relativePath) {
    final id = fileId('HomeDomain', relativePath);
    for (final candidate in [
      p.join(backupDir, id.substring(0, 2), id),
      p.join(backupDir, id),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Describes the backup in [dir] (`<root>/<udid>`), or `null` if it isn't
  /// one.
  static ContactsSource? describe(String dir, {required String origin}) {
    final info = File(p.join(dir, 'Info.plist'));
    if (!info.existsSync()) return null;
    Map<String, Object?> i = const {};
    Map<String, Object?> m = const {};
    try {
      final v = parsePlistBytes(info.readAsBytesSync());
      if (v is Map<String, Object?>) i = v;
      final mf = File(p.join(dir, 'Manifest.plist'));
      if (mf.existsSync()) {
        final mv = parsePlistBytes(mf.readAsBytesSync());
        if (mv is Map<String, Object?>) m = mv;
      }
    } on Object {
      // Unreadable metadata: still offer the folder.
    }
    final date = i['Last Backup Date'];
    return ContactsSource(
      directory: dir,
      origin: origin,
      date: date is DateTime ? date.toLocal() : null,
      encrypted: m.boolean('IsEncrypted') ?? false,
      deviceName: i.str('Device Name') ?? i.str('Display Name'),
      udid:
          i.str('Unique Identifier') ??
          i.str('Target Identifier') ??
          p.basename(dir),
      productType: i.str('Product Type'),
    );
  }

  /// Where Finder / iTunes keep backups on this computer.
  static List<String> systemBackupRoots() {
    final env = Platform.environment;
    if (Platform.isMacOS) {
      return [
        p.join(
          env['HOME'] ?? '',
          'Library',
          'Application Support',
          'MobileSync',
          'Backup',
        ),
      ];
    }
    if (Platform.isWindows) {
      return [
        p.join(env['APPDATA'] ?? '', 'Apple Computer', 'MobileSync', 'Backup'),
        p.join(env['USERPROFILE'] ?? '', 'Apple', 'MobileSync', 'Backup'),
      ];
    }
    return const [];
  }

  /// Where 3uTools keeps backups (it uses the iTunes format). The folder can
  /// be changed in 3uTools, so "Choose backup folder…" covers the rest.
  static List<String> threeUToolsBackupRoots() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    if (Platform.isWindows) {
      return [
        for (final drive in const ['C:', 'D:', 'E:'])
          p.join('$drive\\', '3uTools', 'Backup'),
        p.join(home, 'Documents', '3uTools', 'Backup'),
        p.join(env['APPDATA'] ?? '', '3uTools', 'Backup'),
      ];
    }
    if (Platform.isMacOS) {
      return [
        p.join(home, 'Documents', '3uTools', 'Backup'),
        p.join(home, 'Library', 'Application Support', '3uTools', 'Backup'),
      ];
    }
    return const [];
  }

  /// Every backup root this app knows about, with a label for its origin.
  static List<(String, String)> knownBackupRoots(String appBackupRoot) => [
    (appBackupRoot, 'HK Tools'),
    for (final r in systemBackupRoots()) (r, 'Finder / iTunes'),
    for (final r in threeUToolsBackupRoots()) (r, '3uTools'),
  ];

  /// `true` when [dir] holds an iTunes-format backup (`Info.plist` plus a
  /// manifest).
  static bool isBackupDir(String dir) =>
      File(p.join(dir, 'Info.plist')).existsSync() &&
      (File(p.join(dir, 'Manifest.db')).existsSync() ||
          File(p.join(dir, 'Manifest.plist')).existsSync());

  /// Backups at [root] or up to [depth] folders below it. HK Tools names its
  /// backups `<root>/<device name> <date>/<udid>`, iTunes uses
  /// `<root>/<udid>`, and 3uTools nests them by date.
  static List<ContactsSource> findBackups(
    String root, {
    required String origin,
    int depth = 3,
  }) {
    final out = <ContactsSource>[];
    void walk(String dir, int left) {
      try {
        if (isBackupDir(dir)) {
          final s = describe(dir, origin: origin);
          if (s != null) out.add(s);
          return;
        }
        if (left == 0) return;
        for (final d in Directory(dir).listSync().whereType<Directory>()) {
          final name = p.basename(d.path);
          if (name.startsWith('.')) continue;
          walk(d.path, left - 1);
        }
      } on FileSystemException {
        // e.g. macOS denies MobileSync without Full Disk Access.
      }
    }

    if (Directory(root).existsSync()) walk(root, depth);
    return out;
  }

  /// Every backup on this computer (HK Tools, Finder / iTunes, 3uTools and
  /// [extraRoots]), newest first.
  static List<ContactsSource> allBackups({
    required String appBackupRoot,
    List<String> extraRoots = const [],
  }) {
    final seen = <String>{};
    final out = <ContactsSource>[];
    for (final (root, origin) in [
      ...knownBackupRoots(appBackupRoot),
      for (final r in extraRoots) (r, 'Folder'),
    ]) {
      for (final s in findBackups(root, origin: origin)) {
        if (seen.add(p.normalize(s.directory))) out.add(s);
      }
    }
    out.sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );
    return out;
  }

  /// Backups of [udid] in the app's backup folder and the system locations,
  /// newest first.
  static List<ContactsSource> sourcesFor(
    String udid, {
    required String appBackupRoot,
  }) => [
    for (final s in allBackups(appBackupRoot: appBackupRoot))
      if (s.udid?.toLowerCase() == udid.toLowerCase()) s,
  ];

  /// Loads every contact from the backup in [backupDir] on a background
  /// isolate.
  static Future<List<Contact>> load(String backupDir) =>
      Isolate.run(() => loadSync(backupDir));

  static List<Contact> loadSync(String backupDir) {
    final src = describe(backupDir, origin: '');
    if (src?.encrypted ?? false) {
      throw ContactsException(
        'This backup is encrypted, so its contacts can\'t be read. Turn off backup '
        'encryption in the Backup tab, make a new backup, then reload.',
      );
    }
    final dbPath = backedUpFile(backupDir, _addressBook);
    if (dbPath == null) {
      throw ContactsException(
        'This backup has no address book. Contacts synced with iCloud may be '
        'left out of local backups.',
      );
    }
    // Work on a temporary copy: SQLite may create -wal/-shm files, and the
    // backup folder must stay untouched.
    final tmp = Directory.systemTemp.createTempSync('hk_contacts_');
    try {
      final copy = p.join(tmp.path, 'AddressBook.sqlitedb');
      File(dbPath).copySync(copy);
      final contacts = readAddressBook(copy);
      final imgPath = backedUpFile(backupDir, _images);
      if (imgPath == null) return contacts;
      final imgCopy = p.join(tmp.path, 'AddressBookImages.sqlitedb');
      File(imgPath).copySync(imgCopy);
      final photos = readThumbnails(imgCopy);
      return [for (final c in contacts) c.withPhoto(photos[c.id])];
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// SQLite values are loosely typed: accept ints, numeric text or null.
  static int? _int(Object? v) => switch (v) {
    int() => v,
    num() => v.toInt(),
    String() => int.tryParse(v),
    _ => null,
  };

  static String? _cleanLabel(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^_\$!<(.+)>!\$_$').firstMatch(raw);
    return m?.group(1) ?? raw;
  }

  static DateTime? _appleDate(Object? v) {
    final secs = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (secs == null) return null;
    return DateTime.utc(2001)
        .add(Duration(milliseconds: (secs * 1000).round()));
  }

  /// Parses an AddressBook.sqlitedb file.
  static List<Contact> readAddressBook(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      String? str(Row r, String col) {
        if (!r.keys.contains(col)) return null;
        final v = r[col];
        if (v == null) return null;
        final s = '$v'.trim();
        return s.isEmpty ? null : s;
      }

      // `rowid AS rid`: these tables declare no ROWID column, and SQLite then
      // reports the implicit one as lowercase "rowid".
      final labels = <int, String?>{
        for (final r in db.select(
          'SELECT rowid AS rid, value FROM ABMultiValueLabel',
        ))
          ?_int(r['rid']): _cleanLabel(r['value'] as String?),
      };
      final entryKeys = <int, String>{
        for (final r in db.select(
          'SELECT rowid AS rid, value FROM ABMultiValueEntryKey',
        ))
          ?_int(r['rid']): '${r['value']}',
      };
      final entries = <int, Map<String, String>>{};
      for (final r in db.select(
        'SELECT parent_id, key, value FROM ABMultiValueEntry',
      )) {
        final key = entryKeys[_int(r['key'])];
        final value = r['value'];
        final parent = _int(r['parent_id']);
        if (key == null || value == null || parent == null) continue;
        entries.putIfAbsent(parent, () => {})[key] = '$value';
      }

      final phones = <int, List<LabeledValue>>{};
      final emails = <int, List<LabeledValue>>{};
      final urls = <int, List<LabeledValue>>{};
      final addresses = <int, List<PostalAddress>>{};
      for (final r in db.select(
        'SELECT UID, record_id, property, label, value FROM ABMultiValue',
      )) {
        final rec = _int(r['record_id']);
        if (rec == null) continue;
        final label = labels[_int(r['label'])];
        final value = r['value'] == null ? null : '${r['value']}'.trim();
        switch (r['property']) {
          case 3 when value != null && value.isNotEmpty:
            phones.putIfAbsent(rec, () => []).add(LabeledValue(label, value));
          case 4 when value != null && value.isNotEmpty:
            emails.putIfAbsent(rec, () => []).add(LabeledValue(label, value));
          case 22 when value != null && value.isNotEmpty:
            urls.putIfAbsent(rec, () => []).add(LabeledValue(label, value));
          case 5:
            final e = entries[_int(r['UID'])] ?? const {};
            addresses
                .putIfAbsent(rec, () => [])
                .add(
                  PostalAddress(
                    label: label,
                    street: e['Street'],
                    city: e['City'],
                    state: e['State'],
                    zip: e['ZIP'],
                    country: e['Country'],
                  ),
                );
        }
      }

      final out = <Contact>[];
      for (final r in db.select('SELECT rowid AS rid, * FROM ABPerson')) {
        final id = _int(r['rid']);
        if (id == null) continue;
        out.add(
          Contact(
            id: id,
            first: str(r, 'First'),
            last: str(r, 'Last'),
            middle: str(r, 'Middle'),
            prefix: str(r, 'Prefix'),
            suffix: str(r, 'Suffix'),
            nickname: str(r, 'Nickname'),
            organization: str(r, 'Organization'),
            department: str(r, 'Department'),
            jobTitle: str(r, 'JobTitle'),
            note: str(r, 'Note'),
            birthday: _appleDate(
              r.keys.contains('Birthday') ? r['Birthday'] : null,
            ),
            created: _appleDate(
              r.keys.contains('CreationDate') ? r['CreationDate'] : null,
            ),
            modified: _appleDate(
              r.keys.contains('ModificationDate')
                  ? r['ModificationDate']
                  : null,
            ),
            phones: phones[id] ?? const [],
            emails: emails[id] ?? const [],
            urls: urls[id] ?? const [],
            addresses: addresses[id] ?? const [],
          ),
        );
      }
      out.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      return out;
    } on SqliteException catch (e) {
      throw ContactsException(
        'The address book could not be read: ${e.message}',
      );
    } finally {
      db.close();
    }
  }

  /// record id → JPEG thumbnail.
  static Map<int, Uint8List> readThumbnails(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final out = <int, Uint8List>{};
      for (final r in db.select(
        'SELECT record_id, data FROM ABThumbnailImage ORDER BY format',
      )) {
        final data = r['data'];
        final rec = _int(r['record_id']);
        if (rec != null && data is Uint8List && data.isNotEmpty) {
          out.putIfAbsent(rec, () => data);
        }
      }
      return out;
    } on SqliteException {
      return const {};
    } finally {
      db.close();
    }
  }
}

/// Groups contacts that share a phone number (last 9 digits) or an email.
List<List<Contact>> findDuplicates(List<Contact> contacts) {
  final byKey = <String, Set<int>>{};
  for (final c in contacts) {
    for (final ph in c.phones) {
      final digits = ph.value.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7) {
        final key = digits.length > 9
            ? digits.substring(digits.length - 9)
            : digits;
        byKey.putIfAbsent('t:$key', () => {}).add(c.id);
      }
    }
    for (final e in c.emails) {
      byKey.putIfAbsent('e:${e.value.toLowerCase()}', () => {}).add(c.id);
    }
  }
  // Merge overlapping groups (union-find over contact ids).
  final parent = <int, int>{};
  int find(int x) => parent[x] == x ? x : parent[x] = find(parent[x]!);
  for (final ids in byKey.values.where((s) => s.length > 1)) {
    for (final id in ids) {
      parent.putIfAbsent(id, () => id);
    }
    final first = find(ids.first);
    for (final id in ids.skip(1)) {
      parent[find(id)] = first;
    }
  }
  final groups = <int, List<Contact>>{};
  final byId = {for (final c in contacts) c.id: c};
  for (final id in parent.keys) {
    groups.putIfAbsent(find(id), () => []).add(byId[id]!);
  }
  return groups.values.where((g) => g.length > 1).toList();
}

String _vEscape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;');

String _vType(String? label) => label == null
    ? ''
    : ';TYPE=${label.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '')}';

/// vCard 3.0 (one card per contact, CRLF line endings, photos embedded).
String toVCard(List<Contact> contacts) {
  final b = StringBuffer();
  void line(String s) => b.write('$s\r\n');
  for (final c in contacts) {
    line('BEGIN:VCARD');
    line('VERSION:3.0');
    line(
      'N:${[c.last, c.first, c.middle, c.prefix, c.suffix].map((s) => _vEscape(s ?? '')).join(';')}',
    );
    line('FN:${_vEscape(c.displayName)}');
    if (c.nickname != null) line('NICKNAME:${_vEscape(c.nickname!)}');
    if (c.organization != null || c.department != null) {
      line(
        'ORG:${_vEscape(c.organization ?? '')};${_vEscape(c.department ?? '')}',
      );
    }
    if (c.jobTitle != null) line('TITLE:${_vEscape(c.jobTitle!)}');
    for (final t in c.phones) {
      line('TEL${_vType(t.label)}:${_vEscape(t.value)}');
    }
    for (final e in c.emails) {
      line('EMAIL${_vType(e.label)}:${_vEscape(e.value)}');
    }
    for (final a in c.addresses) {
      line(
        'ADR${_vType(a.label)}:;;${[a.street, a.city, a.state, a.zip, a.country].map((s) => _vEscape(s ?? '')).join(';')}',
      );
    }
    for (final u in c.urls) {
      line('URL:${_vEscape(u.value)}');
    }
    if (c.birthday != null) {
      final d = c.birthday!;
      line(
        'BDAY:${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
    if (c.note != null) line('NOTE:${_vEscape(c.note!)}');
    if (c.photo != null) {
      line('PHOTO;ENCODING=b;TYPE=JPEG:${base64.encode(c.photo!)}');
    }
    line('END:VCARD');
  }
  return b.toString();
}

/// CSV with one row per contact (spreadsheet friendly, UTF-8 with BOM).
String toCsv(List<Contact> contacts) {
  String cell(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
  final rows = <String>[
    [
      'First name', 'Last name', 'Organization', 'Job title', 'Phones', //
      'Emails', 'Addresses', 'Birthday', 'Note',
    ].map(cell).join(','),
    for (final c in contacts)
      [
        c.first,
        c.last,
        c.organization,
        c.jobTitle,
        c.phones
            .map((t) => t.label == null ? t.value : '${t.label}: ${t.value}')
            .join(' | '),
        c.emails.map((e) => e.value).join(' | '),
        c.addresses.map((a) => a.oneLine).join(' | '),
        c.birthday?.toIso8601String().split('T').first,
        c.note,
      ].map(cell).join(','),
  ];
  return '﻿${rows.join('\r\n')}\r\n';
}
