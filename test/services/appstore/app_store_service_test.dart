import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/appstore/app_store_service.dart';
import 'package:hk_ipsw_manager/services/device/device_toolchain.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ipatool output', () {
    test('search result and apps', () {
      const out =
          '{"count":2,"apps":[{"id":310633997,"bundleID":"net.whatsapp.WhatsApp",'
          '"name":"WhatsApp Messenger","version":"25.20.80","price":0},'
          '{"id":1,"bundleID":"com.paid.app","name":"Paid","version":"1.0","price":4.99}],'
          '"time":"2026-10-15T10:35:47+03:00"}';
      final apps = IpatoolOutput.apps(IpatoolOutput.result(out));
      expect(apps.map((a) => a.bundleId), [
        'net.whatsapp.WhatsApp',
        'com.paid.app',
      ]);
      expect(apps.first.id, 310633997);
      expect(apps.first.isFree, isTrue);
      expect(apps.last.price, 4.99);
    });

    test('errors become AppStoreException with friendly text', () {
      const out =
          '{"level":"error","error":"failed to get account: failed to get item: '
          'The specified item could not be found in the keyring","success":false}';
      expect(
        () => IpatoolOutput.result(out),
        throwsA(
          isA<AppStoreException>()
              .having((e) => e.notSignedIn, 'notSignedIn', isTrue)
              .having((e) => e.message, 'message', contains('Sign in')),
        ),
      );
      expect(
        AppStoreException('failed to purchase app').message,
        contains('Paid apps'),
      );
    });

    test('2FA prompt detection', () {
      const out =
          '{"message":"preparing authentication; the first login may take a few minutes"}\n'
          '{"message":"2FA code is required; run the command again and supply a code using the `--auth-code` flag"}';
      expect(IpatoolOutput.needsAuthCode(out), isTrue);
      expect(
        IpatoolOutput.needsAuthCode('{"email":"a@b.c","success":true}'),
        isFalse,
      );
    });

    test('progress bar parsing', () {
      final p1 = IpatoolOutput.progress(
        '\x1B[0mdownloading  45% |█████     | (36/80 MB, 4.1 MB/s)',
      )!;
      expect(p1.fraction, closeTo(0.45, 1e-9));
      expect(p1.detail, '36/80 MB, 4.1 MB/s');
      expect(IpatoolOutput.progress('{"output":"x 50%.ipa"}'), isNull);
      expect(IpatoolOutput.progress('preparing'), isNull);
    });

    test('file names are filesystem-safe', () {
      expect(
        AppStoreService.fileNameFor(
          const StoreApp(
            id: 7,
            bundleId: 'com.a/b',
            name: 'x',
            version: '1.0 beta',
          ),
        ),
        'com.a_b_7_1.0_beta.ipa',
      );
    });
  });

  group('fake ipatool process', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hk_ipatool_');
      final script = File(p.join(dir.path, 'ipatool'));
      await script.writeAsString(r'''#!/bin/sh
echo "$@" >> "$(dirname "$0")/calls.txt"
case "$1 $2" in
  "auth login")
    echo '{"message":"preparing authentication; the first login may take a few minutes"}'
    [ -f "$(dirname "$0")/slow" ] && sleep 5
    echo '{"level":"debug","message":"logging in"}'
    case "$*" in
      *--auth-code\ 123456*) echo '{"name":"Hisham","email":"h@example.com","success":true}' ;;
      *) echo '{"message":"2FA code is required; run the command again and supply a code using the `--auth-code` flag"}' ;;
    esac ;;
  "auth info") echo '{"name":"Hisham","email":"h@example.com","success":true}' ;;
  "auth revoke") echo '{"success":true}' ;;
  download*)
    out=""
    while [ $# -gt 0 ]; do [ "$1" = "--output" ] && out="$2"; shift; done
    printf 'downloading  10%% | (1/10 MB)\rdownloading  60%% | (6/10 MB)\r'
    echo payload > "$out"
    echo "{\"output\":\"$out\",\"purchased\":true,\"success\":true}" ;;
  search*) echo '{"count":1,"apps":[{"id":5,"bundleID":"com.x","name":"X","version":"2","price":0}]}' ;;
esac
''');
      await Process.run('chmod', ['+x', script.path]);
    });
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('login reports status and honours the time limit', () async {
      final svc = AppStoreService(DeviceToolchain(customDirectory: dir.path));
      final statuses = <String>[];
      final r = await svc.login(
        'h@example.com',
        'pw',
        authCode: '123456',
        onStatus: statuses.add,
      );
      expect(r, isA<LoginSucceeded>());
      expect(statuses.first, startsWith('Preparing Apple sign-in'));
      expect(statuses, contains('Signing in to Apple…'));

      File(p.join(dir.path, 'slow')).writeAsStringSync('');
      await expectLater(
        svc.login('h@example.com', 'pw', timeout: const Duration(seconds: 1)),
        throwsA(
          isA<AppStoreException>().having(
            (e) => e.message,
            'message',
            contains('longer than'),
          ),
        ),
      );
    });

    test('login with 2FA, search, download', () async {
      final svc = AppStoreService(
        DeviceToolchain(customDirectory: dir.path),
        keychainPassphrase: 'pp',
      );
      expect(await svc.login('h@example.com', 'pw'), isA<LoginNeedsCode>());
      final ok = await svc.login('h@example.com', 'pw', authCode: '123456');
      expect((ok as LoginSucceeded).account.name, 'Hisham');
      expect((await svc.account())!.email, 'h@example.com');

      final apps = await svc.search('x');
      expect(apps.single.bundleId, 'com.x');

      final events = await svc
          .download(apps.single, p.join(dir.path, 'out'))
          .toList();
      final progress = events.whereType<StoreDownloadProgress>().map(
        (e) => e.fraction,
      );
      expect(progress, [0.1, 0.6]);
      final done = events.last as StoreDownloadDone;
      expect(File(done.path).readAsStringSync().trim(), 'payload');
      expect(done.purchased, isTrue);

      final calls = File(p.join(dir.path, 'calls.txt')).readAsLinesSync();
      expect(calls.first, contains('--non-interactive'));
      expect(calls.first, contains('--keychain-passphrase pp'));
      // Download runs interactively so ipatool prints progress.
      expect(calls.last, isNot(contains('--non-interactive')));
      expect(calls.last, contains('--purchase'));
    });
  }, skip: Platform.isWindows ? 'shell-script fakes' : false);
}
