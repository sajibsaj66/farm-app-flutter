import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's dialer with a number. Nothing is dialled automatically:
/// the user still presses call in the dialer. Uses the DIAL intent, so no
/// phone permission is needed.
class PhoneService {
  PhoneService._();

  /// A dialable number (digits with an optional leading +), or null when the
  /// text is not a valid phone number.
  static String? normalise(String? raw) {
    final text = (raw ?? '').trim();
    if (!RegExp(r'^\+?[0-9 -]{6,16}$').hasMatch(text)) return null;
    return text.replaceAll(RegExp(r'[ -]'), '');
  }

  /// Whether this device can open a dialer for [number].
  static Future<bool> canCall(String? number) async {
    final n = normalise(number);
    if (n == null) return false;
    try {
      return await canLaunchUrl(Uri(scheme: 'tel', path: n));
    } catch (_) {
      // No platform support (e.g. tests, desktop without a dialer).
      return false;
    }
  }

  /// Opens the dialer. Returns false when that is not possible.
  static Future<bool> call(String? number) async {
    final n = normalise(number);
    if (n == null) return false;
    try {
      return await launchUrl(Uri(scheme: 'tel', path: n));
    } catch (_) {
      return false;
    }
  }
}
