import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/navigation_controller.dart';
import 'package:technovate_farm_management/data/demo_users.dart';
import 'package:technovate_farm_management/models/access_policy.dart';
import 'package:technovate_farm_management/models/app_section.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  late AuthController auth;
  late List<String> audit;

  Future<AuthController> restart() async {
    final a = AuthController(LocalStorageService.instance);
    await a.init();
    return a;
  }

  setUp(() async {
    await mockStorage({});
    audit = [];
    auth = AuthController(LocalStorageService.instance, onAudit: (m) async => audit.add(m));
    await auth.init();
  });

  test('only Farm Owner and Farm Manager roles, each with a demo account that can sign in', () async {
    expect(UserRole.values.map((r) => r.label), ['Farm Owner', 'Farm Manager']);
    for (final role in UserRole.values) {
      final account = auth.demoAccountFor(role)!;
      expect(await auth.login(role: role, username: account.username, password: account.password), isNull, reason: role.label);
      expect(auth.currentUser!.role, role);
    }
  });

  test('passwords are stored hashed, never as plain text', () async {
    final store = await openStorage();
    final stored = store.readValue('app_users')!;
    for (final a in demoAccounts) {
      expect(stored, isNot(contains('"${a.password}"')));
    }
    expect(stored, contains('passwordHash'));
  });

  test('wrong password and wrong role are rejected', () async {
    expect(await auth.login(role: UserRole.owner, username: 'owner', password: 'nope'), isNotNull);
    expect(await auth.login(role: UserRole.owner, username: 'manager', password: 'manager123'), contains('not a Farm Owner'));
    expect(auth.isSignedIn, isFalse);
  });

  test('session survives restart and is cleared on logout', () async {
    await auth.login(role: UserRole.manager, username: ' MANAGER ', password: 'manager123');
    final restarted = await restart();
    expect(restarted.currentUser?.username, 'manager');

    await restarted.logout();
    expect((await restart()).isSignedIn, isFalse);
  });

  group('role-permission matrix', () {
    const money = [FarmModule.sales, FarmModule.collections, FarmModule.customers, FarmModule.purchases, FarmModule.expenses];
    const owner = AccessPolicy(UserRole.owner);
    const opsOnly = AccessPolicy(UserRole.manager);
    final allRights = AccessPolicy(UserRole.manager, ManagerGrant.values.toSet());

    test('owner: everything', () {
      for (final m in FarmModule.all.where((m) => !FarmModule.outOfScope.contains(m.name))) {
        expect(owner.canEditModule(m.name), isTrue, reason: m.name);
      }
      expect(owner.canDelete && owner.canSeeFinance && owner.canManageSettings && owner.canManageUsers && owner.canBackup && owner.canResetData && owner.canViewActivityLog, isTrue);
    });

    test('manager without rights: daily operations only', () {
      for (final m in money) {
        expect(opsOnly.canOpenModule(m), isFalse, reason: m);
      }
      for (final m in [
        FarmModule.animals,
        FarmModule.feedRecords,
        FarmModule.milkProduction,
        FarmModule.illness,
        FarmModule.treatments,
        FarmModule.health,
        FarmModule.breeding,
        FarmModule.inventory,
        FarmModule.inventoryTx,
        FarmModule.mortality
      ]) {
        expect(opsOnly.canEditModule(m), isTrue, reason: m);
      }
      for (final m in [FarmModule.species, FarmModule.locations]) {
        expect(opsOnly.canOpenModule(m) && !opsOnly.canEditModule(m), isTrue, reason: '$m is view only');
      }
      expect(opsOnly.canDelete || opsOnly.canSeeFinance || opsOnly.canManageSettings || opsOnly.canManageUsers || opsOnly.canBackup || opsOnly.canResetData || opsOnly.canViewActivityLog, isFalse);
      expect(opsOnly.canCloseIllness, isTrue);
    });

    test('each right the owner gives opens exactly its records', () {
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.sales}).canEditModule(FarmModule.sales), isTrue);
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.sales}).canEditModule(FarmModule.collections), isTrue);
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.sales}).canOpenModule(FarmModule.expenses), isFalse);
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.purchases}).canEditModule(FarmModule.purchases), isTrue);
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.expenses}).canEditModule(FarmModule.expenses), isTrue);
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.finance}).canSeeFinance, isTrue);
      // Even with every right, a manager does not run the owner's settings.
      expect(allRights.canManageUsers || allRights.canManageSettings || allRights.canDelete || allRights.canBackup, isFalse);
    });

    test('nobody opens the poultry/fish/bee batch modules; signed out sees nothing', () {
      for (final m in FarmModule.outOfScope) {
        expect(owner.canOpenModule(m) || allRights.canOpenModule(m), isFalse, reason: m);
      }
      expect(AccessPolicy.none.canOpenModule(FarmModule.animals), isFalse);
    });

    test('navigation follows the access policy', () {
      List<String> labels(AccessPolicy a) => NavigationController(a).sections.map((s) => s.label).toList();
      expect(labels(owner), hasLength(AppSection.all.length));
      expect(labels(owner), isNot(contains(FarmModule.batches)));
      expect(labels(opsOnly), containsAll(['Overview', 'Animals', 'Feed Records', 'Milk Production', 'Animal Health', 'Mortality & Losses', 'Stock Transactions', 'Reports', 'Settings']));
      for (final m in money) {
        expect(labels(opsOnly), isNot(contains(m)), reason: m);
      }
      expect(labels(allRights), containsAll(money));
    });
  });

  group('owner user management', () {
    setUp(() async {
      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    });

    test('add a manager with chosen rights, who can then sign in, and it persists', () async {
      expect(await auth.addUser(username: 'Milker1', name: 'Jamal Mia', role: UserRole.manager, password: 'secret1', grants: {ManagerGrant.sales}), isNull);
      expect(audit.last, contains('Added user Jamal Mia (Farm Manager, may: record sales & payments)'));
      final fresh = await restart();
      expect(await fresh.login(role: UserRole.manager, username: 'milker1', password: 'secret1'), isNull);
      expect(fresh.access.canEditModule(FarmModule.sales), isTrue);
      expect(fresh.access.canOpenModule(FarmModule.expenses), isFalse);
    });

    test('the owner can change a manager\'s rights; owners never keep manager grants', () async {
      expect(await auth.updateUser('manager03', name: 'Sharmin Akter', role: UserRole.manager, active: true, grants: {ManagerGrant.expenses, ManagerGrant.finance}), isNull);
      final m = auth.users.firstWhere((u) => u.username == 'manager03');
      expect(m.grants, {ManagerGrant.expenses, ManagerGrant.finance});
      expect(await auth.updateUser('manager03', name: 'Sharmin Akter', role: UserRole.owner, active: true), isNull);
      expect(auth.users.firstWhere((u) => u.username == 'manager03').grants, isEmpty);
    });

    test('rejects duplicate usernames, bad usernames and short passwords', () async {
      expect(await auth.addUser(username: 'manager', name: 'Someone', role: UserRole.manager, password: 'secret1'), contains('already taken'));
      expect(await auth.addUser(username: 'a b', name: 'Someone', role: UserRole.manager, password: 'secret1'), isNotNull);
      expect(await auth.addUser(username: 'newuser', name: 'Someone', role: UserRole.manager, password: '123'), contains('at least'));
    });

    test('change role, disable, reset password and delete', () async {
      expect(await auth.updateUser('manager02', name: 'Mahmudul Hasan', role: UserRole.owner, active: true), isNull);
      expect(auth.users.firstWhere((u) => u.username == 'manager02').role, UserRole.owner);

      expect(await auth.updateUser('manager04', name: 'Habibur Rahman', role: UserRole.manager, active: false), isNull);
      expect(await auth.login(role: UserRole.manager, username: 'manager04', password: 'manager04pass'), contains('disabled'));

      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      await auth.addUser(username: 'helper', name: 'Field Helper', role: UserRole.manager, password: 'helper1');
      expect(await auth.resetPassword('helper', 'newpass99'), isNull);
      expect(await auth.login(role: UserRole.manager, username: 'helper', password: 'helper1'), isNotNull);
      expect(await auth.login(role: UserRole.manager, username: 'helper', password: 'newpass99'), isNull);

      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      expect(await auth.deleteUser('helper'), isNull);
      expect(auth.users.any((u) => u.username == 'helper'), isFalse);
    });

    test('owner cannot lock themselves or the farm out', () async {
      expect(await auth.updateUser('owner', name: 'Farhana Akter', role: UserRole.manager, active: true), contains('own role'));
      expect(await auth.updateUser('owner', name: 'Farhana Akter', role: UserRole.owner, active: false), contains('disable your own'));
      expect(await auth.deleteUser('owner'), contains('own account'));
    });

    test('a second owner can be removed', () async {
      await auth.addUser(username: 'owner2x', name: 'Second Owner', role: UserRole.owner, password: 'owner456');
      expect(await auth.deleteUser('owner2x'), isNull);
    });

    test('managers cannot manage users', () async {
      await auth.login(role: UserRole.manager, username: 'manager02', password: 'manager02pass');
      expect(await auth.addUser(username: 'x123', name: 'X Y', role: UserRole.manager, password: 'secret1'), contains('Only the Farm Owner'));
      expect(await auth.deleteUser('manager'), contains('Only the Farm Owner'));
      expect(await auth.updateUser('manager02', name: 'Mahmudul Hasan', role: UserRole.manager, active: true, grants: ManagerGrant.values.toSet()), contains('Only the Farm Owner'));
    });
  });

  test('anyone can change their own password', () async {
    await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
    expect(await auth.changeOwnPassword(current: 'wrong', next: 'abcdef'), contains('incorrect'));
    expect(await auth.changeOwnPassword(current: 'manager123', next: 'abc'), contains('at least'));
    expect(await auth.changeOwnPassword(current: 'manager123', next: 'fresh-pass'), isNull);
    final fresh = await restart();
    expect(await fresh.login(role: UserRole.manager, username: 'manager', password: 'fresh-pass'), isNull);
  });

  test('accounts with retired roles (Farm Worker, vet, accountant) become Farm Managers without money rights', () async {
    await mockStorage({
      'app_users': '[{"username":"owner","name":"Owner","role":"owner","passwordHash":"x","salt":"y","active":true},'
          '{"username":"worker","name":"Sabbir Hossain","role":"worker","passwordHash":"x","salt":"y","active":true},'
          '{"username":"vet","name":"Dr. Vet","role":"veterinarian","passwordHash":"x","salt":"y","active":true},'
          '{"username":"accounts","name":"Acc","role":"accountant","passwordHash":"x","salt":"y","active":true}]',
    });
    final a = AuthController(LocalStorageService.instance);
    await a.init();
    for (final name in ['worker', 'vet', 'accounts']) {
      final u = a.users.firstWhere((u) => u.username == name);
      expect(u.role, UserRole.manager, reason: name);
      expect(u.grants, isEmpty, reason: name);
    }
    expect(a.pendingNotices.where((n) => n.contains('was retired')), hasLength(3));
    final store = await openStorage();
    expect(store.readValue('app_users'), isNot(contains('"role":"worker"')), reason: 'role saved as manager');
    expect(store.readValue('app_users'), isNot(contains('veterinarian')));
  });

  test('ten demo accounts per role, each able to sign in, with the documented rights', () async {
    for (final role in UserRole.values) {
      final accounts = demoAccounts.where((a) => a.role == role).toList();
      expect(accounts, hasLength(10), reason: role.label);
      expect(auth.users.where((u) => u.role == role), hasLength(10));
      for (final a in accounts) {
        expect(await auth.login(role: role, username: a.username, password: a.password), isNull, reason: a.username);
      }
    }
    expect(demoAccounts.map((a) => a.username).toSet(), hasLength(20), reason: 'usernames are unique');
    expect(auth.demoAccountFor(UserRole.owner)!.username, 'owner', reason: 'original logins unchanged');
    Set<ManagerGrant> grants(String u) => auth.users.firstWhere((x) => x.username == u).grants;
    expect(grants('manager'), {ManagerGrant.sales, ManagerGrant.purchases, ManagerGrant.expenses});
    expect(grants('manager02'), ManagerGrant.values.toSet());
    expect(grants('manager03'), isEmpty);
    expect(grants('manager04'), {ManagerGrant.sales});
  });

  test('existing installs get the new demo accounts once; deleted ones stay deleted', () async {
    // An install from before: only the original accounts, no version key.
    await mockStorage({});
    final old = AuthController(LocalStorageService.instance, seed: demoAccounts.where((a) => const {'owner', 'manager'}.contains(a.username)).toList());
    await old.init();
    final store = await openStorage();
    await store.writeValue('demo_accounts_version', null);
    expect(old.users, hasLength(2));

    final upgraded = AuthController(LocalStorageService.instance);
    await upgraded.init();
    expect(upgraded.users, hasLength(20));
    expect(upgraded.pendingNotices.single, contains('18 demo accounts added'));

    await upgraded.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    expect(await upgraded.deleteUser('manager05'), isNull);
    final again = AuthController(LocalStorageService.instance);
    await again.init();
    expect(again.users, hasLength(19));
    expect(again.pendingNotices, isEmpty);
  });
}
