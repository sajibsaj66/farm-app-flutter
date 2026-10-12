import 'package:url_launcher/url_launcher.dart';

/// Opens a web page, WhatsApp chat or email in another app. Returns false
/// when the device cannot open it (the caller then offers to copy it).
class LinkService {
  LinkService._();

  static Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No platform support (e.g. tests) or no app for this link.
      return false;
    }
  }

  static Future<bool> website(String url) => open(Uri.parse(url));

  static Future<bool> email(String address) => open(Uri(scheme: 'mailto', path: address));
}
