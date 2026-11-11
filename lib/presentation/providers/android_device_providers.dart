import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../services/android/android_catalog_service.dart';
import '../../services/whatsapp/wa_android.dart';
import 'core_providers.dart';
import 'whatsapp_android_providers.dart';

final androidCatalogProvider = Provider<AndroidCatalogService>(
  (ref) => AndroidCatalogService(
    cacheDir: p.join(ref.watch(appSupportDirProvider), 'android_catalog'),
  ),
);

/// Everything shown on the Android device card.
class AndroidDeviceDetails {
  const AndroidDeviceDetails({required this.info, this.name, this.photo});

  final AndroidDeviceInfo info;

  /// "Samsung Galaxy A53 5G" when the catalog knows the model.
  final String? name;

  /// Local product photo, if one was found.
  final String? photo;

  String get displayName =>
      name ??
      [
        if (info.manufacturer != null) _cap(info.manufacturer!),
        info.marketName ?? info.model ?? info.serial,
      ].join(' ');

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// adb details of a phone (fast: one shell round trip per source).
final androidDeviceInfoProvider = FutureProvider.autoDispose
    .family<AndroidDeviceInfo, String>(
      (ref, serial) => ref.watch(waAndroidClientProvider).deviceInfo(serial),
    );

/// The phone's friendly name and photo; slower (catalog download on first
/// use), so the card shows the adb details first.
final androidDeviceDetailsProvider = FutureProvider.autoDispose
    .family<AndroidDeviceDetails, String>((ref, serial) async {
      final info = await ref.watch(androidDeviceInfoProvider(serial).future);
      final catalog = ref.watch(androidCatalogProvider);
      String? name = info.marketName;
      if (name != null &&
          info.manufacturer != null &&
          !name.toLowerCase().startsWith(info.manufacturer!.toLowerCase())) {
        name = '${AndroidDeviceDetails._cap(info.manufacturer!)} $name';
      }
      name ??= await catalog.marketingName(
        model: info.model,
        codename: info.codename,
      );
      final photo = name == null ? null : await catalog.photoFor(name);
      return AndroidDeviceDetails(info: info, name: name, photo: photo);
    });
