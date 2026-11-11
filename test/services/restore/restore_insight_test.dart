import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/domain/entities/ios_device.dart';
import 'package:hk_ipsw_manager/services/device/device_parsers.dart';
import 'package:hk_ipsw_manager/services/restore/restore_insight.dart';

RestoreLogEvent _e(String l) => RestoreLogEvent(l, isError: true);

void main() {
  test('overall progress runs in restore order and stays below 100%', () {
    expect(RestoreInsight.overall(null, 0), 0);
    final upload = RestoreInsight.overall(RestoreStep.uploadImage, 1);
    final prepare = RestoreInsight.overall(RestoreStep.prepare, 0);
    expect(prepare, closeTo(upload, 1e-9));
    final fsHalf = RestoreInsight.overall(RestoreStep.uploadFilesystem, 0.5);
    expect(fsHalf, greaterThan(prepare));
    expect(RestoreInsight.overall(RestoreStep.firmwareUpdate, 1), lessThan(1));
  });

  test('activity lines turn into plain words', () {
    expect(
      RestoreInsight.activity('Waiting for device to enter restore mode...'),
      'Waiting for the device to restart…',
    );
    expect(RestoreInsight.activity('random noise'), isNull);
  });

  test('common failures are explained', () {
    expect(
      RestoreInsight.explain([_e('ERROR: Unable to get SHSH blobs')]).title,
      'Apple is not approving this firmware',
    );
    expect(
      RestoreInsight.explain([_e('ERROR: Device did not reconnect')]).title,
      'The device lost its connection',
    );
    expect(
      RestoreInsight.explain([_e('write failed: No space left on device')])
          .title,
      'Not enough disk space on this computer',
    );
    expect(
      RestoreInsight.explain([_e('IPSW not found: /x.ipsw')]).title,
      'The firmware file cannot be read',
    );
    expect(
      RestoreInsight.explain([], aborted: true).title,
      'The restore was stopped',
    );
    final unknown = RestoreInsight.explain([_e('ERROR: something odd')]);
    expect(unknown.title, 'The restore did not finish');
    expect(unknown.detail, 'ERROR: something odd');
  });

  test('a harmless early "baseband" line does not mislead', () {
    final log = [
      const RestoreLogEvent('Sending baseband firmware ticket'),
      for (var i = 0; i < 20; i++) RestoreLogEvent('progress line $i'),
      _e('ERROR: Device did not reconnect'),
    ];
    expect(RestoreInsight.explain(log).title, 'The device lost its connection');
  });

  test('update on a wiped device asks for an erase', () {
    final f = RestoreInsight.explain([
      const RestoreLogEvent('Unable to successfully restore device', isError: true),
      const RestoreLogEvent(
        'Checkpoint FAILURE id: 0x648 result=0: [0]D(Missing data volume on APFS formatted device, erase required)',
      ),
    ]);
    expect(f.title, 'This device has to be erased');
    expect(f.needsErase, isTrue);
  });

  test('Yonkers ticket failure points at the restore tools', () {
    final f = RestoreInsight.explain([
      _e('Unable to fetch Yonkers ticket'),
      _e("restore_send_firmware_updater_data: Couldn't get Yonkers firmware data"),
    ]);
    expect(f.title, 'The restore tools need an update for this iPhone');
  });
}
