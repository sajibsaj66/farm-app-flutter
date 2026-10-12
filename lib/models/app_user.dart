import 'access_policy.dart';
import 'user_role.dart';

class AppUser {
  const AppUser({
    required this.username,
    required this.name,
    required this.role,
    required this.passwordHash,
    required this.salt,
    this.phone = '',
    this.active = true,
    this.grants = const {},
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        username: '${json['username']}',
        name: '${json['name']}',
        role: UserRole.parse('${json['role']}'),
        passwordHash: '${json['passwordHash']}',
        salt: '${json['salt']}',
        phone: '${json['phone'] ?? ''}',
        active: json['active'] != false,
        grants: ManagerGrant.parse(json['grants']),
      );

  final String username;
  final String name;
  final UserRole role;
  final String passwordHash;
  final String salt;
  final String phone;

  /// Disabled accounts cannot sign in.
  final bool active;

  /// Extra rights the owner gave this manager (ignored for owners, who have
  /// every right).
  final Set<ManagerGrant> grants;

  AccessPolicy get access => AccessPolicy.of(this);

  String get firstName => name.split(' ').first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  AppUser copyWith({String? name, UserRole? role, String? passwordHash, String? salt, String? phone, bool? active, Set<ManagerGrant>? grants}) => AppUser(
        username: username,
        name: name ?? this.name,
        role: role ?? this.role,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        phone: phone ?? this.phone,
        active: active ?? this.active,
        grants: grants ?? this.grants,
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'name': name,
        'role': role.name,
        'passwordHash': passwordHash,
        'salt': salt,
        'phone': phone,
        'active': active,
        'grants': [
          for (final g in ManagerGrant.values)
            if (grants.contains(g)) g.name
        ],
      };
}
