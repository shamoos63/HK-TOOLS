import 'package:url_launcher/url_launcher.dart';

/// App identity and author credit, shown in the sidebar and Settings › About.
abstract final class Branding {
  static const appName = 'HK Tools';
  static const version = '3.0.0';
  static const author = 'Hisham Khateeb';
  static const credit = 'Made By Hisham Khateeb for the Community.';

  static const telegramLabel = 't.me/xavior963';
  static final telegramUrl = Uri.parse('https://t.me/xavior963');
  static const websiteLabel = 'Hishamkhateeb.com';
  static final websiteUrl = Uri.parse('https://hishamkhateeb.com');

  static const logo = 'assets/branding/logo.png';
  static const logoMark = 'assets/branding/logo_mark.png';

  static Future<void> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
