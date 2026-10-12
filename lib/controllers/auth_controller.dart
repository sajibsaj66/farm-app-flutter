import 'package:flutter/foundation.dart';

import '../core/utils/password_hasher.dart';
import '../data/demo_users.dart';
import '../models/access_policy.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/local_storage_service.dart';

/// Who is signed in, plus the farm's user accounts.
///
/// Accounts and the session are stored on the device. Management methods
/// return an error message for the user, or null on success.
class AuthController extends ChangeNotifier {
  AuthController(this._storage, {List<DemoAccount>? seed, this.onAudit}) : _seed = seed ?? demoAccounts;

  static final AuthController instance = AuthController(LocalStorageService.instance);

  static const minPasswordLength = 6;
  static const _demoVersionKey = 'demo_accounts_version';

  final LocalStorageService _storage;
  final List<DemoAccount> _seed;

  /// Called with a description of every account change, for the activity log.
  Future<void> Function(String message)? onAudit;

  final List<AppUser> _users = [];

  /// Messages from data migration, written to the activity log once the farm
  /// data is ready.
  final List<String> pendingNotices = [];
  AppUser? _user;
  bool ready = false;

  AppUser? get currentUser => _user;

  bool get isSignedIn => _user != null;

  UserRole? get role => _user?.role;

  /// What the signed-in user may see and do.
  AccessPolicy get access => AccessPolicy.of(_user);

  bool get canManageUsers => access.canManageUsers;

  List<AppUser> get users => List.unmodifiable(_users);

  DemoAccount? demoAccountFor(UserRole role) {
    for (final a in _seed) {
      if (a.role == role) return a;
    }
    return null;
  }

  // Remembered sign-in details, per role

  /// The username and password the sign-in screen fills in for [role]: the
  /// last successful sign-in remembered on this device, or the demo account.
  (String, String) savedLoginFor(UserRole role) {
    final saved = _storage.readSavedLogins()[role.name];
    if (saved != null && saved.$1.isNotEmpty) return saved;
    final demo = demoAccountFor(role);
    return demo == null ? ('', '') : (demo.username, demo.password);
  }

  Future<void> rememberLogin(UserRole role, String username, String password) async {
    final all = _storage.readSavedLogins()..[role.name] = (username.trim().toLowerCase(), password);
    await _storage.writeSavedLogins(all);
  }

  Future<void> forgetLogin(UserRole role) async {
    final all = _storage.readSavedLogins()..remove(role.name);
    await _storage.writeSavedLogins(all);
  }

  /// Keeps remembered details in step with password changes, role changes and
  /// deleted accounts, so the sign-in screen never offers stale details.
  Future<void> _syncSavedLogins(String username, {String? newPassword, UserRole? role, bool removed = false}) async {
    final all = _storage.readSavedLogins();
    var changed = false;
    for (final key in [...all.keys]) {
      final (user, password) = all[key]!;
      if (user != username) continue;
      if (removed || (role != null && role.name != key)) {
        all.remove(key);
      } else if (newPassword != null && newPassword != password) {
        all[key] = (user, newPassword);
      } else {
        continue;
      }
      changed = true;
    }
    if (changed) await _storage.writeSavedLogins(all);
  }

  Future<void> init() async {
    await _storage.init();
    _users.clear();
    final saved = _storage.readUsers();
    if (saved == null) {
      _users.addAll(_seed.map((a) => _newUser(username: a.username, name: a.name, role: a.role, password: a.password, grants: a.grants)));
      await _saveUsers();
      await _storage.writeValue(_demoVersionKey, '$demoAccountsVersion');
    } else {
      _users.addAll(saved.map(AppUser.fromJson));
      // Accounts saved with a role this version no longer has (Farm Worker,
      // veterinarian, accountant) were read as Farm Manager with no money
      // rights; save that and note it.
      final known = UserRole.values.map((r) => r.name).toSet();
      final migrated = saved.where((u) => !known.contains('${u['role']}')).toList();
      if (migrated.isNotEmpty) {
        await _saveUsers();
        for (final u in migrated) {
          pendingNotices.add('Role "${u['role']}" was retired — ${u['name']} is now a Farm Manager without money rights. Review it in Users & roles.');
        }
      }
      // New demo accounts are added once to existing installs. Accounts the
      // owner deletes later are not brought back.
      final version = int.tryParse(_storage.readValue(_demoVersionKey) ?? '') ?? 1;
      if (version < demoAccountsVersion) {
        final added = _seed.where((a) => _find(a.username) == null).toList();
        _users.addAll(added.map((a) => _newUser(username: a.username, name: a.name, role: a.role, password: a.password, grants: a.grants)));
        await _saveUsers();
        await _storage.writeValue(_demoVersionKey, '$demoAccountsVersion');
        if (added.isNotEmpty) pendingNotices.add('${added.length} demo accounts added (10 Farm Owners and 10 Farm Managers).');
      }
    }
    final session = _find(_storage.readSession());
    _user = session != null && session.active ? session : null;
    ready = true;
    notifyListeners();
  }

  // Session

  /// Signs in. With [remember], the username and password are remembered
  /// for this role on this device (true) or forgotten (false).
  Future<String?> login({required UserRole role, required String username, required String password, bool? remember}) async {
    final user = _find(username);
    if (user == null || !PasswordHasher.verify(password, salt: user.salt, hash: user.passwordHash)) {
      return 'Incorrect username or password.';
    }
    if (!user.active) return 'This account is disabled. Please contact the farm owner.';
    if (user.role != role) return 'This account is not a ${role.label} account. Choose ${user.role.label} instead.';
    if (remember != null) remember ? await rememberLogin(role, username, password) : await forgetLogin(role);
    _user = user;
    await _storage.writeSession(user.username);
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _user = null;
    await _storage.writeSession(null);
    notifyListeners();
  }

  Future<String?> changeOwnPassword({required String current, required String next}) async {
    final me = _user;
    if (me == null) return 'You are not signed in.';
    if (!PasswordHasher.verify(current, salt: me.salt, hash: me.passwordHash)) return 'Current password is incorrect.';
    final invalid = validatePassword(next);
    if (invalid != null) return invalid;
    if (current == next) return 'New password must be different from the current one.';
    await _replace(_withPassword(me, next));
    await _syncSavedLogins(me.username, newPassword: next);
    await onAudit?.call('Changed own password');
    return null;
  }

  // User management (owner only)

  Future<String?> addUser({required String username, required String name, required UserRole role, required String password, String phone = '', Set<ManagerGrant> grants = const {}}) async {
    final denied = _requireOwner();
    if (denied != null) return denied;
    final key = username.trim().toLowerCase();
    final invalid = validateUsername(key) ?? validateName(name) ?? validatePassword(password);
    if (invalid != null) return invalid;
    if (_find(key) != null) return 'Username "$key" is already taken.';
    _users.add(_newUser(username: key, name: name.trim(), role: role, password: password, phone: phone.trim(), grants: role == UserRole.manager ? grants : const {}));
    await _saveUsers();
    notifyListeners();
    await onAudit?.call('Added user ${name.trim()} (${role.label}${_grantsNote(role, grants)})');
    return null;
  }

  Future<String?> updateUser(String username, {required String name, required UserRole role, required bool active, String phone = '', Set<ManagerGrant>? grants}) async {
    final denied = _requireOwner();
    if (denied != null) return denied;
    final target = _find(username);
    if (target == null) return 'User not found.';
    final invalid = validateName(name);
    if (invalid != null) return invalid;
    final isSelf = target.username == _user!.username;
    if (isSelf && role != target.role) return 'You cannot change your own role.';
    if (isSelf && !active) return 'You cannot disable your own account.';
    if (_wouldRemoveLastOwner(target, newRole: role, active: active)) return 'The farm must keep at least one active Farm Owner.';
    final newGrants = role == UserRole.manager ? (grants ?? target.grants) : const <ManagerGrant>{};
    await _replace(target.copyWith(name: name.trim(), role: role, active: active, phone: phone.trim(), grants: newGrants));
    await _syncSavedLogins(target.username, role: role, removed: !active);
    await onAudit?.call('Updated user ${name.trim()} (${role.label}${_grantsNote(role, newGrants)}${active ? '' : ', disabled'})');
    return null;
  }

  Future<String?> resetPassword(String username, String newPassword) async {
    final denied = _requireOwner();
    if (denied != null) return denied;
    final target = _find(username);
    if (target == null) return 'User not found.';
    final invalid = validatePassword(newPassword);
    if (invalid != null) return invalid;
    await _replace(_withPassword(target, newPassword));
    await _syncSavedLogins(target.username, newPassword: newPassword);
    await onAudit?.call('Reset password for ${target.name}');
    return null;
  }

  Future<String?> deleteUser(String username) async {
    final denied = _requireOwner();
    if (denied != null) return denied;
    final target = _find(username);
    if (target == null) return 'User not found.';
    if (target.username == _user!.username) return 'You cannot delete your own account.';
    if (_wouldRemoveLastOwner(target, newRole: null, active: false)) return 'The farm must keep at least one active Farm Owner.';
    _users.removeWhere((u) => u.username == target.username);
    await _syncSavedLogins(target.username, removed: true);
    await _saveUsers();
    notifyListeners();
    await onAudit?.call('Deleted user ${target.name}');
    return null;
  }

  // Validation shared with the forms

  static String? validateUsername(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return 'Please enter a username';
    if (!RegExp(r'^[a-z0-9._]{3,20}$').hasMatch(v)) return 'Use 3–20 letters, numbers, dots or underscores';
    return null;
  }

  static String? validateName(String? value) => (value == null || value.trim().length < 2) ? 'Please enter the full name' : null;

  static String? validatePassword(String? value) => (value == null || value.length < minPasswordLength) ? 'Password must be at least $minPasswordLength characters' : null;

  // Internals

  String? _requireOwner() => canManageUsers ? null : 'Only the Farm Owner can manage users.';

  bool _wouldRemoveLastOwner(AppUser target, {required UserRole? newRole, required bool active}) {
    if (target.role != UserRole.owner || !target.active) return false;
    final staysOwner = newRole == UserRole.owner && active;
    if (staysOwner) return false;
    final activeOwners = _users.where((u) => u.role == UserRole.owner && u.active).length;
    return activeOwners <= 1;
  }

  static String _grantsNote(UserRole role, Set<ManagerGrant> grants) =>
      role != UserRole.manager ? '' : (grants.isEmpty ? ', operations only' : ', may: ${ManagerGrant.values.where(grants.contains).map((g) => g.label.toLowerCase()).join(', ')}');

  AppUser _newUser({required String username, required String name, required UserRole role, required String password, String phone = '', Set<ManagerGrant> grants = const {}}) {
    final salt = PasswordHasher.newSalt();
    return AppUser(username: username, name: name, role: role, salt: salt, passwordHash: PasswordHasher.hash(password, salt), phone: phone, grants: grants);
  }

  AppUser _withPassword(AppUser user, String password) {
    final salt = PasswordHasher.newSalt();
    return user.copyWith(salt: salt, passwordHash: PasswordHasher.hash(password, salt));
  }

  Future<void> _replace(AppUser updated) async {
    final i = _users.indexWhere((u) => u.username == updated.username);
    if (i >= 0) _users[i] = updated;
    if (_user?.username == updated.username) _user = updated;
    await _saveUsers();
    notifyListeners();
  }

  Future<void> _saveUsers() => _storage.writeUsers(_users.map((u) => u.toJson()).toList());

  AppUser? _find(String? username) {
    final key = username?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final u in _users) {
      if (u.username == key) return u;
    }
    return null;
  }
}
