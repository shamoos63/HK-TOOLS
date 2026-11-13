import 'package:path/path.dart' as p;

import '../../core/l10n/l10n.dart';
import '../../domain/entities/ios_device.dart';
import '../../services/device/device_service.dart';
import '../../services/device/device_toolchain.dart';
import '../../services/whatsapp/wa_ios_backup.dart';
import 'device_providers.dart';

/// Backs up only WhatsApp (or WhatsApp Business) from [device] into a new
/// `<device name> <date>` folder under [backupsRoot], with progress on
/// [job]. Falls back to a whole-phone backup when pymobiledevice3 isn't set
/// up. Returns the backup folder (`…/<udid>`); throws when the backup fails.
Future<String> backUpWhatsAppOnly({
  required BackupJobController job,
  required JobState Function() jobState,
  required DeviceToolchain tools,
  required DeviceService service,
  required ConnectedDevice device,
  required String backupsRoot,
  required bool business,
}) async {
  final udid = device.udid!;
  final root = namedBackupDir(backupsRoot, device);
  final app = business ? tr('WhatsApp Business') : tr('WhatsApp');
  var containers = const <String>[];
  if (WaIosBackup.available(tools)) {
    containers = await WaIosBackup.containers(tools, udid, business: business);
  }
  if (containers.isNotEmpty) {
    await job.run(
      trf('Backing up {0} from {1}', [app, device.displayName]),
      () => WaIosBackup.start(
        tools,
        udid,
        root,
        containers: containers,
        business: business,
      ),
    );
  } else {
    await job.run(
      trf('Backup of {0}', [device.displayName]),
      () => service.startBackup(device, root),
    );
  }
  final done = jobState();
  if (done.status != JobStatus.succeeded) {
    throw Exception(
      trf('The iPhone backup failed: {0}', [
        done.log.isEmpty ? tr('unknown error') : done.log.last,
      ]),
    );
  }
  return p.join(root, udid);
}
