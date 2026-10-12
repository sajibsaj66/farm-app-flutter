import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'auth_controller.dart';

/// State of the sign-in form: chosen role, fields, errors and progress.
class LoginController extends ChangeNotifier {
  LoginController({AuthController? auth}) : _auth = auth ?? AuthController.instance {
    _fillSaved();
  }

  final AuthController _auth;

  final formKey = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();

  UserRole role = UserRole.owner;
  bool obscurePassword = true;

  /// Remember this role's username and password on this device after a
  /// successful sign-in (on by default).
  bool remember = true;
  bool busy = false;
  String? error;

  void selectRole(UserRole value) {
    if (value == role) return;
    role = value;
    error = null;
    _fillSaved();
    notifyListeners();
  }

  /// Each role shows its own remembered (or demo) username and password.
  void _fillSaved() {
    final (user, pass) = _auth.savedLoginFor(role);
    username.text = user;
    password.text = pass;
  }

  void setRemember(bool value) {
    remember = value;
    notifyListeners();
  }

  void toggleObscure() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  /// Fills the form with the demo account for the selected role.
  void fillDemoAccount() {
    final account = _auth.demoAccountFor(role);
    if (account == null) return;
    username.text = account.username;
    password.text = account.password;
    error = null;
    notifyListeners();
  }

  String? validateUsername(String? v) => (v == null || v.trim().isEmpty) ? 'Please enter your username' : null;

  String? validatePassword(String? v) => (v == null || v.isEmpty) ? 'Please enter your password' : null;

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    busy = true;
    error = null;
    notifyListeners();
    // Remembered (or forgotten) inside login, before the app switches screens.
    final result = await _auth.login(role: role, username: username.text, password: password.text, remember: remember);
    if (_disposed) return;
    error = result;
    busy = false;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    username.dispose();
    password.dispose();
    super.dispose();
  }
}
