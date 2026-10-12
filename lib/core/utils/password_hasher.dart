import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted SHA-256 so passwords are never stored as plain text on the device.
class PasswordHasher {
  PasswordHasher._();

  static final _random = Random.secure();

  static String newSalt() => base64Url.encode(List<int>.generate(16, (_) => _random.nextInt(256)));

  static String hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  static bool verify(String password, {required String salt, required String hash}) => PasswordHasher.hash(password, salt) == hash;
}
