import 'package:flutter/material.dart';

import '../models/access_policy.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import 'auth_controller.dart';

/// Owner-only: the list of farm accounts.
class UsersController {
  UsersController({AuthController? auth}) : auth = auth ?? AuthController.instance;

  final AuthController auth;

  List<AppUser> get users {
    final list = [...auth.users];
    list.sort((a, b) => a.role.index != b.role.index ? a.role.index.compareTo(b.role.index) : a.name.compareTo(b.name));
    return list;
  }

  bool isMe(AppUser u) => u.username == auth.currentUser?.username;

  int countFor(UserRole role) => auth.users.where((u) => u.role == role && u.active).length;

  Future<String?> delete(AppUser u) => auth.deleteUser(u.username);
}

/// Add or edit one account. Passwords are only set on create or reset.
class UserFormController extends ChangeNotifier {
  UserFormController({this.existing, AuthController? auth}) : _auth = auth ?? AuthController.instance {
    name.text = existing?.name ?? '';
    username.text = existing?.username ?? '';
    phone.text = existing?.phone ?? '';
    role = existing?.role ?? UserRole.manager;
    active = existing?.active ?? true;
    grants = {...?existing?.grants};
  }

  final AppUser? existing;
  final AuthController _auth;

  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final username = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();

  late UserRole role;
  late bool active;

  /// What this manager may do beyond daily operations (ignored for owners).
  late Set<ManagerGrant> grants;
  bool busy = false;
  String? error;

  bool get isEditing => existing != null;

  bool get isMe => existing?.username == _auth.currentUser?.username;

  String get title => isEditing ? 'Edit user' : 'Add user';

  void setRole(UserRole value) {
    role = value;
    notifyListeners();
  }

  void setActive(bool value) {
    active = value;
    notifyListeners();
  }

  void setGrant(ManagerGrant grant, bool allowed) {
    allowed ? grants.add(grant) : grants.remove(grant);
    notifyListeners();
  }

  String? validatePhone(String? v) => (v == null || v.trim().isEmpty || RegExp(r'^\+?[0-9 -]{6,16}$').hasMatch(v.trim())) ? null : 'Enter a valid phone number';

  Future<bool> save() async {
    if (busy || !formKey.currentState!.validate()) return false;
    busy = true;
    error = null;
    notifyListeners();
    error = isEditing
        ? await _auth.updateUser(existing!.username, name: name.text, role: role, active: active, phone: phone.text, grants: grants)
        : await _auth.addUser(username: username.text, name: name.text, role: role, password: password.text, phone: phone.text, grants: grants);
    busy = false;
    notifyListeners();
    return error == null;
  }

  Future<String?> resetPassword(String newPassword) => _auth.resetPassword(existing!.username, newPassword);

  @override
  void dispose() {
    for (final c in [name, username, phone, password]) {
      c.dispose();
    }
    super.dispose();
  }
}
