import 'package:flutter_test/flutter_test.dart';
import 'package:hk_ipsw_manager/services/whatsapp/wa_ios_backup.dart';

void main() {
  // `pymobiledevice3 apps query` output (shape from a real iPhone).
  const json = '''
{
  "net.whatsapp.WhatsAppSMB": {
    "Container": "/private/var/mobile/Containers/Data/Application/2DB8E4F8-5995-40A5-9594-E78882796106",
    "GroupContainers": {
      "group.com.facebook.family": "/private/var/mobile/Containers/Shared/AppGroup/164D868D-1D3D-4ACB-A9F2-A35CA3CCB764",
      "group.net.whatsapp.WhatsAppSMB.shared": "/private/var/mobile/Containers/Shared/AppGroup/1A1D9DA7-018A-4DCF-B7ED-2B6C8714C4C7",
      "group.net.whatsapp.family": "/private/var/mobile/Containers/Shared/AppGroup/944CDBE2-2F49-4FEA-8BAE-E8C93B50DF7F"
    }
  }
}''';

  test('finds the app and its WhatsApp group containers', () {
    final c = WaIosBackup.parseContainers(json, WaIosBackup.businessBundle);
    expect(c, hasLength(3)); // app + 2 whatsapp groups (not facebook)
    expect(c.any((x) => x.contains('164D868D')), isFalse);
    expect(
      WaIosBackup.parseContainers(json, WaIosBackup.whatsAppBundle),
      isEmpty,
    );
  });

  test('filter keeps WhatsApp files by container, both path spellings', () {
    final c = WaIosBackup.parseContainers(json, WaIosBackup.businessBundle);
    final re = RegExp(WaIosBackup.filterRegex(c, business: true));
    expect(
      re.hasMatch(
        '/var/mobile/Containers/Shared/AppGroup/1A1D9DA7-018A-4DCF-B7ED-2B6C8714C4C7/ChatStorage.sqlite',
      ),
      isTrue,
    );
    expect(
      re.hasMatch(
        '/private/var/mobile/Containers/Data/Application/2DB8E4F8-5995-40A5-9594-E78882796106/Library/x',
      ),
      isTrue,
    );
    expect(
      re.hasMatch(
        'AppDomainGroup-group.net.whatsapp.WhatsAppSMB.shared/Media/a.jpg',
      ),
      isTrue,
    );
    expect(
      re.hasMatch('/var/mobile/Media/DCIM/100APPLE/IMG_0001.HEIC'),
      isFalse,
    );
    expect(re.hasMatch('HomeDomain/Library/SMS/sms.db'), isFalse);

    final wa = RegExp(WaIosBackup.filterRegex(const [], business: false));
    expect(
      wa.hasMatch(
        'AppDomainGroup-group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite',
      ),
      isTrue,
    );
    expect(
      wa.hasMatch(
        'AppDomainGroup-group.net.whatsapp.WhatsAppSMB.shared/ChatStorage.sqlite',
      ),
      isFalse,
    );
  });
}
