/// Activation and Setup Assistant helpers built on pymobiledevice3.
///
/// "Skip setup" writes an unsupervised cloud configuration through the
/// device's MCInstall service, the same mechanism Apple Configurator uses when
/// preparing devices: Setup Assistant then skips the listed panes. It applies
/// only to a device that is activated and still on the Setup Assistant; it
/// does not touch Activation Lock, which Apple enforces during activation.
library;

import '../../core/l10n/l10n.dart';

/// Panes the user may choose to keep; every other known pane is skipped.
enum SetupPaneGroup {
  languageRegion('Language & Region', [
    'Language',
    'Region',
    'LanguageAndLocale',
    'PreferredLanguage',
    'SpokenLanguage',
    'ExpressLanguage',
    'Keyboard',
  ]),
  wifi('Wi-Fi', ['WiFi']),
  appleId('Apple ID & iCloud', [
    'AppleID',
    'iCloudStorage',
    'iCloudDiagnostics',
    'CloudStorage',
    'AppleIDSubtitle',
  ]),
  passcode('Passcode, Face ID & Touch ID', [
    'Passcode',
    'Biometric',
    'TouchID',
    'DeviceProtection',
  ]),
  location('Location Services', ['Location']);

  const SetupPaneGroup(this._label, this.panes);

  final String _label;

  /// In the interface language.
  String get label => tr(_label);
  final List<String> panes;
}

/// Panes that are always skipped (welcome, legal, promos, migration…).
const _alwaysSkip = [
  'Welcome',
  'TOS',
  'Restore',
  'RestoreCompleted',
  'UpdateCompleted',
  'Android',
  'DeviceToDeviceMigration',
  'WatchMigration',
  'UnlockWithWatch',
  'SIMSetup',
  'IntendedUser',
  'Siri',
  'ScreenTime',
  'Diagnostics',
  'SoftwareUpdate',
  'Payment',
  'Zoom',
  'DisplayTone',
  'Display',
  'Tone',
  'TrueToneDisplay',
  'Appearance',
  'AccessibilityAppearance',
  'Accessibility',
  'MessagingActivationUsingPhoneNumber',
  'iMessageAndFaceTime',
  'HomeButtonSensitivity',
  'ScreenSaver',
  'TapToSetup',
  'OnBoarding',
  'Privacy',
  'PrivacySubtitle',
  'SecuritySubtitle',
  'DataSubtitle',
  'AppStore',
  'Safety',
  'Multitasking',
  'ActionButton',
  'TermsOfAddress',
  'Registration',
  'Avatar',
  'Wallpaper',
  'LockdownMode',
  'TVProviderSignIn',
  'TVHomeScreenSync',
  'TVRoom',
];

List<String> skipPanes({required Set<SetupPaneGroup> keep}) => [
  ..._alwaysSkip,
  for (final g in SetupPaneGroup.values)
    if (!keep.contains(g)) ...g.panes,
];

/// Unsupervised cloud configuration for
/// `pymobiledevice3 profile cloud-configuration <plist>`.
String cloudConfigurationPlist(List<String> skip) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String b(bool v) => v ? '<true/>' : '<false/>';
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AllowPairing</key>${b(true)}
  <key>CloudConfigurationUIComplete</key>${b(true)}
  <key>ConfigurationSource</key><integer>0</integer>
  <key>ConfigurationWasApplied</key>${b(true)}
  <key>IsMDMUnremovable</key>${b(false)}
  <key>IsMandatory</key>${b(false)}
  <key>IsMultiUser</key>${b(false)}
  <key>IsSupervised</key>${b(false)}
  <key>PostSetupProfileWasInstalled</key>${b(true)}
  <key>SkipSetup</key>
  <array>
${skip.map((k) => '    <string>${esc(k)}</string>').join('\n')}
  </array>
</dict>
</plist>
''';
}

/// Friendly text for pymobiledevice3 activation / configuration errors.
String friendlySetupError(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('icloud locked')) {
    return 'Activation Lock is on. Enter the owner\'s Apple ID and password on the '
        'device\'s Activation Lock screen (or remove the device from the owner\'s '
        'iCloud account). HK Tools cannot bypass Activation Lock.';
  }
  if (r.contains('already activated')) {
    return 'The device is already activated.';
  }
  if (r.contains('already present') ||
      r.contains('cloudconfigurationalreadypresent')) {
    return 'A configuration is already applied. Erase the device (Restore tab) to start '
        'Setup Assistant over, then try again.';
  }
  if (r.contains('not connected')) return 'Device is not connected.';
  if (r.contains('imei') || r.contains('meid')) {
    return 'The device did not report its IMEI/MEID; insert a SIM or check the baseband.';
  }
  return raw;
}

/// Explains a pymobiledevice3 failure from its whole output, or `null` when
/// nothing specific is recognised.
///
/// pymobiledevice3 sometimes stops to ask a question in its terminal. HK
/// Tools runs it without one, so that shows up as NoConsoleScreenBufferError
/// (Windows) or an end-of-input / "Aborted!" error (macOS). During activation
/// the only such question is Apple's request for the owner's Apple ID, i.e.
/// the device is Activation Locked.
String? describeSetupFailure(String output, {required String command}) {
  final o = output.toLowerCase();
  final askedQuestion =
      o.contains('noconsolescreenbuffer') ||
      o.contains('eoferror') ||
      o.contains('aborted!') ||
      o.contains('not a terminal') ||
      o.contains('x-buddyml');
  if (command == 'activation' &&
      (askedQuestion ||
          o.contains('icloud locked') ||
          o.contains('activation lock'))) {
    return friendlySetupError('Device is iCloud locked');
  }
  if (askedQuestion) {
    return 'pymobiledevice3 asked for input that HK Tools cannot answer. Unlock '
        'the device, tap Trust if asked, and try again.';
  }
  return null;
}
