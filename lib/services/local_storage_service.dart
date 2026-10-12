import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local persistence in a Hive box. Reads and writes are no-ops until
/// [init] runs.
///
/// Earlier versions saved to SharedPreferences. On the first start with Hive,
/// every saved value is copied across unchanged (records, users, session,
/// profile, activity, backups…). The old copy is left in place and never
/// written again, so nothing can be lost by the move.
class LocalStorageService {
  LocalStorageService._();

  static final LocalStorageService instance = LocalStorageService._();

  static const boxName = 'deshit_bd_farm';
  static const _migratedKey = '_migrated_from_shared_preferences';
  static const _activityKey = 'farm_activity';
  static const _sessionKey = 'auth_session';
  static const _usersKey = 'app_users';
  static const _profileKey = 'farm_profile';
  static String _recordsKey(String module) => 'records_$module';
  static String _dismissedKey(String username) => 'dismissed_alerts_$username';

  Box<dynamic>? _box;
  bool _memoryOnly = false;

  /// How many values were copied from SharedPreferences on this start
  /// (0 when nothing needed moving).
  int migratedFromPreferences = 0;

  Future<void> init() async {
    if (_box?.isOpen ?? false) return;
    if (_memoryOnly) {
      _box = await Hive.openBox<dynamic>(boxName, bytes: Uint8List(0));
    } else {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(boxName);
    }
    await _migrateFromPreferences();
  }

  /// Tests: start again with an empty in-memory box (nothing touches the
  /// disk). The next [init] copies the mocked SharedPreferences values in, as
  /// a real upgrade would.
  Future<void> debugResetForTests() async {
    await _box?.close();
    _box = null;
    _memoryOnly = true;
    unreadable.clear();
  }

  Future<void> _migrateFromPreferences() async {
    final box = _box!;
    migratedFromPreferences = 0;
    if (box.containsKey(_migratedKey)) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (box.containsKey(key)) continue; // never overwrite data already in Hive
      final value = prefs.get(key);
      await box.put(key, value is List ? value.map((e) => '$e').toList() : value);
      migratedFromPreferences++;
    }
    await box.put(_migratedKey, DateTime.now().toIso8601String());
  }

  /// Every stored key (for diagnostics and tests).
  Iterable<String> get keys => _box?.keys.map((k) => '$k') ?? const [];

  // Records

  /// Saved rows for [module], or null when the module was never saved.
  List<Map<String, dynamic>>? readRecords(String module) => _readList(_recordsKey(module));

  Future<void> writeRecords(String module, List<Map<String, dynamic>> rows) => _writeJson(_recordsKey(module), rows);

  // Activity log

  List<Map<String, dynamic>> readActivity() => _readList(_activityKey) ?? [];

  Future<void> writeActivity(List<Map<String, dynamic>> entries) => _writeJson(_activityKey, entries);

  Future<void> clearActivity() async {
    await _box?.delete(_activityKey);
  }

  // Farm profile

  Map<String, dynamic>? readProfile() => _readMap(_profileKey);

  Future<void> writeProfile(Map<String, dynamic> profile) => _writeJson(_profileKey, profile);

  // Users and session

  List<Map<String, dynamic>>? readUsers() => _readList(_usersKey);

  Future<void> writeUsers(List<Map<String, dynamic>> users) => _writeJson(_usersKey, users);

  /// Username of the signed-in user, if a session was saved.
  String? readSession() => readValue(_sessionKey);

  Future<void> writeSession(String? username) => writeValue(_sessionKey, username);

  // Sign-in details remembered per role (Farm Owner / Farm Manager), so the
  // sign-in screen fills them in when that role is chosen.
  static const _savedLoginsKey = 'saved_logins';

  /// role name → (username, password).
  Map<String, (String, String)> readSavedLogins() {
    final saved = _readMap(_savedLoginsKey) ?? const {};
    return {
      for (final e in saved.entries)
        if (e.value is Map) e.key: ('${(e.value as Map)['username'] ?? ''}', '${(e.value as Map)['password'] ?? ''}'),
    };
  }

  Future<void> writeSavedLogins(Map<String, (String, String)> logins) => _writeJson(_savedLoginsKey, {
        for (final e in logins.entries) e.key: {'username': e.value.$1, 'password': e.value.$2}
      });

  // Dismissed alerts, per user

  Set<String> readDismissedAlerts(String username) {
    final saved = _box?.get(_dismissedKey(username));
    return saved is List ? saved.map((e) => '$e').toSet() : <String>{};
  }

  Future<void> writeDismissedAlerts(String username, Set<String> ids) async {
    await _box?.put(_dismissedKey(username), ids.toList());
  }

  // Simple values (data version, automatic backup)

  String? readValue(String key) {
    final v = _box?.get(key);
    return v == null ? null : '$v';
  }

  Future<void> writeValue(String key, String? value) async {
    if (value == null) {
      await _box?.delete(key);
    } else {
      await _box?.put(key, value);
    }
  }

  /// True when any farm records were saved before (an existing install).
  bool get hasSavedRecords => keys.any((k) => k.startsWith('records_'));

  // Helpers

  Future<void> _writeJson(String key, Object value) async {
    await _box?.put(key, jsonEncode(value));
  }

  /// Saved values that could not be read. Their original text is kept under
  /// the key shown (never deleted), and the app carries on without them.
  final List<(String key, String keptAs)> unreadable = [];

  /// Reads a JSON list of objects. Malformed text, or entries that are not
  /// objects, never crash the app: the raw text is kept aside and only valid
  /// entries are returned.
  List<Map<String, dynamic>>? _readList(String key) {
    final saved = readValue(key);
    if (saved == null) return null;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) throw const FormatException('Not a list');
      final rows = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (rows.length != decoded.length) _keepAside(key, saved);
      return rows;
    } on FormatException {
      _keepAside(key, saved);
      return key == _usersKey ? null : [];
    }
  }

  Map<String, dynamic>? _readMap(String key) {
    final saved = readValue(key);
    if (saved == null) return null;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) throw const FormatException('Not an object');
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      _keepAside(key, saved);
      return null;
    }
  }

  void _keepAside(String key, String raw) {
    final keptAs = 'unreadable_${key}_${DateTime.now().millisecondsSinceEpoch}';
    _box?.put(keptAs, raw);
    unreadable.add((key, keptAs));
  }
}
