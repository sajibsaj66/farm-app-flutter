import '../models/access_policy.dart';
import '../models/user_role.dart';

/// A starter account seeded on first launch. Only the hash of [password] is
/// stored on the device; the plain value is kept here for the login screen's
/// "Use demo account" button. Replace with a real auth backend before release.
class DemoAccount {
  const DemoAccount({required this.username, required this.name, required this.role, required this.password, this.grants = const {}});

  final String username;
  final String name;
  final UserRole role;
  final String password;

  /// Rights the owner has given this demo manager.
  final Set<ManagerGrant> grants;
}

/// Bumped whenever demo accounts are added, so existing installs receive the
/// new ones once (see AuthController.init). 3: Farm Owner and Farm Manager
/// only.
const demoAccountsVersion = 3;

const _owners = ['Farhana Akter', 'Abdul Karim', 'Nasrin Sultana', 'Mizanur Rahman', 'Shahida Begum', 'Rafiqul Islam', 'Tahmina Khatun', 'Jahangir Alam', 'Salma Parvin', 'Kamrul Hasan'];
const _managers = ['Rahim Uddin', 'Mahmudul Hasan', 'Sharmin Akter', 'Habibur Rahman', 'Rokeya Begum', 'Anisur Rahman', 'Fatema Tuz Zohra', 'Delwar Hossain', 'Mousumi Akter', 'Shafiqul Islam'];

/// Demo managers show the different rights an owner can give:
/// manager — sales, purchases and expenses; manager02 — those plus financial
/// summaries; then alternately operations only, and sales only.
Set<ManagerGrant> _demoGrants(int i) => switch (i) {
      0 => {ManagerGrant.sales, ManagerGrant.purchases, ManagerGrant.expenses},
      1 => ManagerGrant.values.toSet(),
      _ when i.isEven => const {},
      _ => {ManagerGrant.sales},
    };

/// Ten demo accounts per role. The first of each role keeps its original
/// login (owner/owner123, manager/manager123); the others are owner02…owner10
/// and manager02…manager10, each with the password "<username>pass".
final demoAccounts = <DemoAccount>[
  for (final (role, prefix, names) in [(UserRole.owner, 'owner', _owners), (UserRole.manager, 'manager', _managers)])
    for (final (i, name) in names.indexed)
      DemoAccount(
        username: i == 0 ? prefix : '$prefix${(i + 1).toString().padLeft(2, '0')}',
        name: name,
        role: role,
        password: i == 0 ? '${prefix}123' : '$prefix${(i + 1).toString().padLeft(2, '0')}pass',
        grants: role == UserRole.manager ? _demoGrants(i) : const {},
      ),
];
