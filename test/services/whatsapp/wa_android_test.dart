import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_android.dart';

void main() {
  const key =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  group('parseDevices', () {
    test('reads serial, state and model', () {
      final list = WaAndroidClient.parseDevices(
        'List of devices attached\n'
        'R58M123ABC             device usb:1-1 product:beyond1 model:SM_G973F device:beyond1 transport_id:3\n'
        'emulator-5554          unauthorized transport_id:4\n',
      );
      expect(list, hasLength(2));
      expect(list[0].serial, 'R58M123ABC');
      expect(list[0].state, AndroidDeviceState.ready);
      expect(list[0].displayName, 'SM G973F');
      expect(list[1].state, AndroidDeviceState.unauthorized);
    });

    test('ignores daemon start-up lines', () {
      expect(
        WaAndroidClient.parseDevices(
          '* daemon not running; starting now at tcp:5037\n'
          '* daemon started successfully\nList of devices attached\n\n',
        ),
        isEmpty,
      );
    });
  });

  group('extractKeyFromUiDump', () {
    test('key in 16 groups of four, mixed with other text', () {
      final groups = [for (var i = 0; i < 64; i += 4) key.substring(i, i + 4)];
      final xml = StringBuffer();
      xml.write('<hierarchy><node text="Your 64-digit encryption key"/>');
      for (final g in groups) {
        xml.write('<node text="$g" content-desc=""/>');
      }
      xml.write('<node text="Continue"/></hierarchy>');
      expect(WaAndroidClient.extractKeyFromUiDump(xml.toString()), key);
    });

    test('key in one node with spaces and line breaks', () {
      final spaced = [for (var i = 0; i < 64; i += 4) key.substring(i, i + 4)]
          .join(' ')
          .toUpperCase()
          .replaceFirst(' ', '&#10;');
      expect(
        WaAndroidClient.extractKeyFromUiDump(
          '<hierarchy><node text="$spaced"/></hierarchy>',
        ),
        key,
      );
    });

    test('no key on screen', () {
      expect(
        WaAndroidClient.extractKeyFromUiDump(
          '<hierarchy><node text="Chats"/><node text="Back up"/></hierarchy>',
        ),
        isNull,
      );
    });
  });

  test('parseStat reads size, mtime and paths with spaces', () {
    final list = WaAndroidClient.parseStat(
      '52428800|1762844400|/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business/Databases/msgstore.db.crypt15\n'
      '1024|1762758000|/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business/Databases/msgstore-2025-11-10.1.db.crypt15\n',
      WaFlavor.business,
    );
    expect(list, hasLength(2));
    expect(list[0].size, 52428800);
    expect(list[0].isLatest, isTrue);
    expect(list[1].isLatest, isFalse);
    expect(list[0].remotePath, contains('WhatsApp Business/Databases'));
    expect(list[0].modified.millisecondsSinceEpoch, 1762844400000);
  });
}
