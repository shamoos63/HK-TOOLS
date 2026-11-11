import 'dart:ui';

import 'strings_ar.dart';

/// Interface language. English text is the key; [arabicStrings] maps it to
/// Arabic. Strings without a translation fall back to English.
abstract final class L10n {
  static bool arabic = false;

  static Locale get locale => arabic ? const Locale('ar') : const Locale('en');

  /// `true` when the computer's preferred language is Arabic.
  static bool get systemPrefersArabic =>
      PlatformDispatcher.instance.locales.firstOrNull?.languageCode == 'ar';
}

/// [en] in the current interface language.
String tr(String en) => L10n.arabic ? (arabicStrings[en] ?? en) : en;

/// Like [tr] for text with values: `trf('{0} of {1}', [a, b])`.
String trf(String en, List<Object?> args) {
  var s = tr(en);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
