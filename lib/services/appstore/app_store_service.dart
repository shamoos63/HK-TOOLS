import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../device/device_toolchain.dart';

/// App Store access through [ipatool](https://github.com/majd/ipatool) (MIT),
/// run as a separate process.
///
/// The Apple ID password is handed to `ipatool auth login` once and never
/// stored by this app; ipatool keeps only its session token, in the macOS
/// Keychain or (Windows/Linux) in an encrypted file unlocked with
/// [keychainPassphrase].
class StoreAccount {
  const StoreAccount({required this.email, this.name});

  final String email;
  final String? name;
}

class StoreApp {
  const StoreApp({
    required this.id,
    required this.bundleId,
    required this.name,
    this.version,
    this.price = 0,
  });

  final int id;
  final String bundleId;
  final String name;
  final String? version;
  final double price;

  bool get isFree => price == 0;

  // Used as a provider family key.
  @override
  bool operator ==(Object other) =>
      other is StoreApp && other.id == id && other.bundleId == bundleId;

  @override
  int get hashCode => Object.hash(id, bundleId);
}

class StoreVersion {
  const StoreVersion({
    required this.externalId,
    this.displayVersion,
    this.releaseDate,
  });

  final String externalId;
  final String? displayVersion;
  final DateTime? releaseDate;
}

enum StorePlatform {
  iphone('iPhone'),
  ipad('iPad');

  const StorePlatform(this.label);

  final String label;
}

class AppStoreException implements Exception {
  AppStoreException(this.raw);

  final String raw;

  bool get notSignedIn =>
      raw.contains('failed to get account') ||
      raw.contains('could not be found in the keyring') ||
      raw.contains('password token is expired') ||
      raw.contains('token expired');

  /// Human-readable message for the UI.
  String get message {
    final r = raw.toLowerCase();
    if (notSignedIn) {
      return 'Sign in to the App Store first (or sign in again: the session expired).';
    }
    if (r.contains('invalid credentials') || r.contains('bad login')) {
      return 'Apple ID or password is incorrect.';
    }
    if (r.contains('auth code') ||
        r.contains('2fa') ||
        r.contains('did not complete verification')) {
      return 'The two-factor code was wrong or expired. Request a new one.';
    }
    if (r.contains('failed to purchase app')) {
      return 'Could not claim the app. Paid apps must be bought on a device first; '
          'then they can be downloaded here.';
    }
    if (r.contains('subscription required')) {
      return 'This app needs an active subscription on this Apple ID.';
    }
    if (r.contains('app not found')) {
      return 'App not found in this Apple ID\'s store.';
    }
    if (r.contains('license is required')) {
      return 'This Apple ID does not own the app. Free apps are claimed automatically; buy paid apps first.';
    }
    if (r.contains('item is temporarily unavailable') ||
        r.contains('not available')) {
      return 'The app is not available in this Apple ID\'s country/region.';
    }
    return raw;
  }

  @override
  String toString() => message;
}

sealed class LoginResult {
  const LoginResult();
}

class LoginSucceeded extends LoginResult {
  const LoginSucceeded(this.account);

  final StoreAccount account;
}

/// Apple sent a code to the account's trusted devices; call login again with
/// `authCode`.
class LoginNeedsCode extends LoginResult {
  const LoginNeedsCode();
}

sealed class StoreDownloadEvent {
  const StoreDownloadEvent();
}

class StoreDownloadProgress extends StoreDownloadEvent {
  const StoreDownloadProgress(this.fraction, {this.detail});

  final double fraction;
  final String? detail;
}

class StoreDownloadDone extends StoreDownloadEvent {
  const StoreDownloadDone(this.path, {required this.purchased});

  final String path;
  final bool purchased;
}

/// Parsing of ipatool's `--format json` output: one JSON object per line on
/// stdout/stderr, plus progress-bar text when interactive.
abstract final class IpatoolOutput {
  static List<Map<String, dynamic>> objects(String output) {
    final out = <Map<String, dynamic>>[];
    for (final raw in output.split(RegExp(r'[\r\n]+'))) {
      final line = stripAnsi(raw).trim();
      final start = line.indexOf('{');
      if (start < 0) continue;
      try {
        final v = jsonDecode(line.substring(start));
        if (v is Map<String, dynamic>) out.add(v);
      } on FormatException {
        // Not JSON (progress bar text).
      }
    }
    return out;
  }

  /// The command's result object. Throws [AppStoreException] when ipatool
  /// reported an error.
  static Map<String, dynamic> result(String output) {
    final objs = objects(output);
    final err = objs.lastWhere(
      (o) => o['error'] != null || o['level'] == 'error',
      orElse: () => const {},
    );
    if (err.isNotEmpty) {
      throw AppStoreException(
        '${err['error'] ?? err['message'] ?? 'Unknown error'}',
      );
    }
    return objs.lastWhere(
      (o) => o.keys.any((k) => k != 'time' && k != 'message' && k != 'level'),
      orElse: () => objs.isEmpty ? const {} : objs.last,
    );
  }

  /// A short human-readable status from one ipatool log line, if any.
  static String? status(String line) {
    final objs = objects(line);
    if (objs.isEmpty) return null;
    final o = objs.first;
    final msg = o['message'] ?? o['error'];
    if (msg is! String || msg.isEmpty) return null;
    if (msg.contains('2FA code is required')) {
      return 'Waiting for the 2FA code…';
    }
    if (msg.startsWith('preparing authentication')) {
      return 'Preparing Apple sign-in (first time only, can take a few minutes)…';
    }
    if (msg == 'logging in') return 'Signing in to Apple…';
    return msg[0].toUpperCase() + msg.substring(1);
  }

  static bool needsAuthCode(String output) =>
      objects(output)
          .any((o) => '${o['message'] ?? ''}'.contains('2FA code is required'));

  static List<StoreApp> apps(Map<String, dynamic> result) => [
    for (final a in (result['apps'] as List? ?? const []))
      if (a is Map<String, dynamic> && a['bundleID'] != null)
        StoreApp(
          id: (a['id'] as num?)?.toInt() ?? 0,
          bundleId: a['bundleID'] as String,
          name: a['name'] as String? ?? a['bundleID'] as String,
          version: a['version'] as String?,
          price: (a['price'] as num?)?.toDouble() ?? 0,
        ),
  ];

  static final _percent = RegExp(r'(\d{1,3})%');

  /// Progress-bar text, e.g. `downloading  45% |█████     | (36/80 MB, 4.1 MB/s)`.
  static StoreDownloadProgress? progress(String line) {
    final l = stripAnsi(line);
    final m = _percent.firstMatch(l);
    if (m == null || l.trimLeft().startsWith('{')) return null;
    final paren = RegExp(r'\(([^)]*)\)').firstMatch(l)?.group(1);
    return StoreDownloadProgress(
      (int.parse(m.group(1)!) / 100).clamp(0.0, 1.0),
      detail: paren,
    );
  }
}

class AppStoreService {
  AppStoreService(this.tools, {this.keychainPassphrase});

  final DeviceToolchain tools;

  /// Needed on Windows/Linux, where ipatool stores the session in a file.
  final String? keychainPassphrase;

  List<String> _global({bool interactive = false}) => [
    '--format',
    'json',
    if (!interactive) '--non-interactive',
    if (keychainPassphrase != null) ...[
      '--keychain-passphrase',
      keychainPassphrase!,
    ],
  ];

  Future<String> _run(List<String> args, {Duration? timeout}) async {
    final r = await tools.run(DeviceTool.ipatool, [
      ...args,
      ..._global(),
    ], timeout: timeout ?? const Duration(seconds: 60));
    if (r.timedOut) {
      throw AppStoreException('Timed out talking to the App Store.');
    }
    return '${r.stdout}\n${r.stderr}';
  }

  /// Signed-in account, or `null`.
  Future<StoreAccount?> account() async {
    try {
      final res = IpatoolOutput.result(await _run(['auth', 'info']));
      final email = res['email'] as String?;
      return email == null
          ? null
          : StoreAccount(email: email, name: res['name'] as String?);
    } on AppStoreException catch (e) {
      if (e.notSignedIn) return null;
      rethrow;
    }
  }

  /// Signs in. The very first sign-in on a computer makes ipatool download
  /// and prepare Apple's request-signing component (cached afterwards), which
  /// can take several minutes on a slow connection, so this allows up to
  /// [timeout] and reports ipatool's status lines through [onStatus].
  /// Kill the process passed to [onStarted] to cancel.
  Future<LoginResult> login(
    String email,
    String password, {
    String? authCode,
    void Function(String status)? onStatus,
    void Function(Process process)? onStarted,
    Duration timeout = const Duration(minutes: 20),
  }) async {
    final process = await tools.start(DeviceTool.ipatool, [
      'auth',
      'login',
      '--email',
      email,
      '--password',
      password,
      if (authCode != null && authCode.isNotEmpty) ...['--auth-code', authCode],
      '--verbose',
      ..._global(),
    ]);
    onStarted?.call(process);
    await process.stdin.close();
    final all = StringBuffer();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      process.kill();
    });
    try {
      await for (final line in DeviceToolchain.lines(process)) {
        all.writeln(line);
        final status = IpatoolOutput.status(line);
        if (status != null) onStatus?.call(status);
      }
      final code = await process.exitCode;
      if (timedOut) {
        throw AppStoreException(
          'Sign-in took longer than ${timeout.inMinutes} minutes. Check the internet '
          'connection and try again; finished preparation steps are kept.',
        );
      }
      final out = all.toString();
      if (IpatoolOutput.needsAuthCode(out)) return const LoginNeedsCode();
      final res = IpatoolOutput.result(out);
      if (res['email'] == null) {
        throw AppStoreException(
          code < 0 ? 'Sign-in was cancelled.' : 'Sign-in did not complete.',
        );
      }
      return LoginSucceeded(
        StoreAccount(
          email: res['email'] as String,
          name: res['name'] as String?,
        ),
      );
    } finally {
      timer.cancel();
    }
  }

  Future<void> logout() async =>
      IpatoolOutput.result(await _run(['auth', 'revoke']));

  Future<List<StoreApp>> search(
    String term, {
    StorePlatform platform = StorePlatform.iphone,
    int limit = 25,
  }) async => IpatoolOutput.apps(
    IpatoolOutput.result(
      await _run([
        'search',
        term,
        '--limit',
        '$limit',
        '--platform',
        platform.name,
      ]),
    ),
  );

  Future<List<StoreApp>> purchases({
    StorePlatform platform = StorePlatform.iphone,
    int page = 1,
  }) async => IpatoolOutput.apps(
    IpatoolOutput.result(
      await _run([
        'list-purchases',
        '--max-results',
        '50',
        '--page',
        '$page',
        '--platform',
        platform.name,
      ]),
    ),
  );

  /// External version ids, oldest first (as returned by the App Store).
  Future<List<String>> versionIds(StoreApp app, StorePlatform platform) async {
    final res = IpatoolOutput.result(
      await _run([
        'list-versions',
        '--app-id',
        '${app.id}',
        '--bundle-identifier',
        app.bundleId,
        '--platform',
        platform.name,
      ]),
    );
    return [
      for (final v in (res['externalVersionIdentifiers'] as List? ?? const []))
        '$v',
    ];
  }

  Future<StoreVersion> versionMetadata(
    StoreApp app,
    String externalId,
    StorePlatform platform,
  ) async {
    final res = IpatoolOutput.result(
      await _run([
        'get-version-metadata',
        '--app-id',
        '${app.id}',
        '--bundle-identifier',
        app.bundleId,
        '--external-version-id',
        externalId,
        '--platform',
        platform.name,
      ]),
    );
    return StoreVersion(
      externalId: externalId,
      displayVersion: res['displayVersion'] as String?,
      releaseDate: DateTime.tryParse('${res['releaseDate'] ?? ''}'),
    );
  }

  static String fileNameFor(StoreApp app, {String? version}) =>
      '${app.bundleId}_${app.id}_${version ?? app.version ?? 'latest'}.ipa'
          .replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

  /// Downloads the `.ipa` into [directory]. Free apps the account does not own
  /// yet are claimed first (`--purchase`). Runs ipatool interactively (stdin
  /// closed) because only then does it print download progress.
  Stream<StoreDownloadEvent> download(
    StoreApp app,
    String directory, {
    StorePlatform platform = StorePlatform.iphone,
    String? externalVersionId,
    String? versionLabel,
    void Function(Process process)? onStarted,
  }) async* {
    await Directory(directory).create(recursive: true);
    final out = p.join(directory, fileNameFor(app, version: versionLabel));
    final process = await tools.start(DeviceTool.ipatool, [
      'download',
      '--app-id',
      '${app.id}',
      '--bundle-identifier',
      app.bundleId,
      '--platform',
      platform.name,
      '--purchase',
      '--output',
      out,
      if (externalVersionId != null) ...[
        '--external-version-id',
        externalVersionId,
      ],
      ..._global(interactive: true),
    ]);
    onStarted?.call(process);
    await process.stdin.close();
    final all = StringBuffer();
    await for (final line in DeviceToolchain.lines(process)) {
      all.writeln(line);
      final prog = IpatoolOutput.progress(line);
      if (prog != null) yield prog;
    }
    final code = await process.exitCode;
    final res = IpatoolOutput.result(all.toString());
    final path = res['output'] as String? ?? out;
    if (code != 0 || !File(path).existsSync()) {
      throw AppStoreException(
        res['error'] as String? ??
            'Download failed (ipatool exited with $code).',
      );
    }
    yield StoreDownloadDone(path, purchased: res['purchased'] == true);
  }
}
