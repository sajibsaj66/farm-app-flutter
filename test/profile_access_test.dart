import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technovate_farm_management/app.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/my_profile_controller.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/controllers/records_controller.dart';
import 'package:technovate_farm_management/core/theme/app_theme.dart';
import 'package:technovate_farm_management/models/access_policy.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';
import 'package:technovate_farm_management/views/cow_profile_view.dart';
import 'package:technovate_farm_management/views/my_profile_view.dart';

import 'support/mock_storage.dart';

Finder inProfile(Finder f) => find.descendant(of: find.byType(MyProfilePage), matching: f);

void main() {
  group('Hive local storage', () {
    test('demo data is saved in the Hive box and survives a restart', () async {
      await mockStorage({});
      final farm = FarmController(LocalStorageService.instance);
      await farm.init();
      final store = await openStorage();
      for (final m in FarmModule.all) {
        expect(store.keys, contains('records_${m.name}'), reason: m.name);
        expect(store.readRecords(m.name), hasLength(farm.count(m.name)));
      }
      final moti = farm.find(FarmModule.animals, 'AN-1004')!;
      await farm.update(FarmModule.animals, FarmRecord({...moti.toJson(), 'breed': 'Sahiwal cross'}));

      final restarted = FarmController(LocalStorageService.instance);
      await restarted.init();
      expect(restarted.find(FarmModule.animals, 'AN-1004')!['breed'], 'Sahiwal cross');
    });

    test('data saved by the older SharedPreferences version is moved to Hive unchanged, once', () async {
      final legacyAnimals = [
        {'id': 'AN-9', 'name': 'Old Cow', 'species': 'Cattle', 'type': 'Cow', 'breed': 'Local', 'sex': 'Female', 'group': 'Dry cows', 'status': 'Active', 'location': 'Shed A'},
      ];
      await mockStorage({
        'records_${FarmModule.animals}': jsonEncode(legacyAnimals),
        'data_version': '${FarmController.dataVersion}',
        'auth_session': 'manager',
        'dismissed_alerts_owner': ['stock:X:1'],
      });
      final farm = FarmController(LocalStorageService.instance);
      await farm.init();
      expect(farm.find(FarmModule.animals, 'AN-9')!['name'], 'Old Cow');
      expect(farm.count(FarmModule.milkProduction), 0, reason: 'no demo activity is mixed into real data');
      expect(farm.activity.first.title, contains('moved to Hive'));
      final store = await openStorage();
      expect(store.readDismissedAlerts('owner'), {'stock:X:1'});
      expect(store.readSession(), 'manager');

      // The old copy is left alone, and a later start does not copy it again
      // over newer Hive data.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('records_${FarmModule.animals}'), jsonEncode(legacyAnimals));
      await farm.update(FarmModule.animals, FarmRecord({...farm.find(FarmModule.animals, 'AN-9')!.toJson(), 'name': 'Renamed Cow'}));
      final again = FarmController(LocalStorageService.instance);
      await again.init();
      expect(again.find(FarmModule.animals, 'AN-9')!['name'], 'Renamed Cow');
      expect(again.activity.where((a) => a.title.contains('moved to Hive')), hasLength(1));
    });
  });

  group('what each role can see and change', () {
    late FarmController farm;
    late AuthController auth;

    setUp(() async {
      await mockStorage({});
      farm = FarmController(LocalStorageService.instance);
      await farm.init();
      auth = AuthController(LocalStorageService.instance);
      await auth.init();
    });

    test('access labels per user', () {
      const owner = AccessPolicy(UserRole.owner);
      const opsOnly = AccessPolicy(UserRole.manager);
      expect(owner.accessLabel(FarmModule.sales), 'View, add, edit & delete');
      expect(opsOnly.accessLabel(FarmModule.species), 'View only');
      expect(opsOnly.accessLabel(FarmModule.milkProduction), 'View, add & edit');
      expect(opsOnly.accessLabel(FarmModule.sales), 'No access');
      expect(const AccessPolicy(UserRole.manager, {ManagerGrant.sales}).accessLabel(FarmModule.sales), 'View, add & edit');
    });

    test('a manager sees farm setup read-only and cannot save it', () async {
      await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
      final species = farm.list(FarmModule.species).first;
      final form = RecordFormController(module: FarmModule.species, existing: species, farm: farm, auth: auth);
      expect(form.canEdit, isFalse);
      expect(form.title, '${FarmModule.species} details');
      expect(form.fields.every(form.isReadOnly), isTrue);
      expect(RecordsController(FarmModule.species, farm: farm, auth: auth).canEdit, isFalse);
      expect(RecordsController(FarmModule.milkProduction, farm: farm, auth: auth).canEdit, isTrue);
      expect(RecordsController(FarmModule.milkProduction, farm: farm, auth: auth).canDelete, isFalse);
    });

    test('signed out, nothing can be changed', () {
      final form = RecordFormController(module: FarmModule.milkProduction, farm: farm, auth: auth);
      expect(form.canEdit, isFalse);
    });

    test('permissions are enforced in the data layer, not only hidden in screens', () async {
      farm.access = () => auth.access;
      final rule = throwsA(isA<FarmRuleException>());
      final sale = {'date': '2026-10-01', 'product': 'Manure', 'customer': 'Moyna Store', 'qty': '10', 'unit': 'kg', 'unitPrice': '4'};
      final expense = {'date': '2026-10-01', 'category': 'Water', 'amount': '100', 'description': 'Test', 'scope': FarmModule.scopeFarm, 'payment': 'Paid'};

      // Operations-only manager: daily records yes; money, setup, delete, settings no.
      await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
      await farm.add(FarmModule.milkProduction, {'date': '2026-10-01', 'animal': 'AN-1001 · Shona', 'shift': 'Morning', 'litres': '7', 'quality': 'Accepted'});
      await expectLater(farm.add(FarmModule.sales, sale), rule);
      await expectLater(farm.add(FarmModule.expenses, expense), rule);
      await expectLater(farm.update(FarmModule.species, farm.list(FarmModule.species).first), rule);
      await expectLater(farm.remove(FarmModule.milkProduction, farm.list(FarmModule.milkProduction).first.id), rule);
      await expectLater(farm.archive(FarmModule.animals, farm.find(FarmModule.animals, 'AN-1006')!), rule);
      await expectLater(farm.updateProfile(farm.profile), rule);
      await expectLater(farm.reset(), rule);
      await expectLater(farm.restore(farm.exportData()), rule);

      // A manager the owner allowed to record sales and expenses.
      await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
      await farm.add(FarmModule.sales, sale);
      await farm.add(FarmModule.expenses, expense);
      await expectLater(farm.remove(FarmModule.expenses, farm.list(FarmModule.expenses).first.id), rule, reason: 'only the owner deletes');

      // The owner may do everything; signed out, nothing.
      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      await farm.remove(FarmModule.expenses, farm.list(FarmModule.expenses).first.id);
      await auth.logout();
      await expectLater(farm.add(FarmModule.milkProduction, {'date': '2026-10-01', 'animal': 'AN-1001 · Shona', 'shift': 'Evening', 'litres': '7', 'quality': 'Accepted'}), rule);
    });

    test('My profile counts only the data the user can see, live', () async {
      await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
      farm.actor = () => auth.currentUser?.name;
      final c = MyProfileController(farm: farm, auth: auth);
      final names = c.modules.map((m) => m.module).toSet();
      expect(names, isNot(contains(FarmModule.sales)));
      expect(names, isNot(contains(FarmModule.batches)));
      expect(c.hiddenModules, containsAll([FarmModule.sales, FarmModule.expenses, FarmModule.customers, FarmModule.purchases]));
      expect(names.length + c.hiddenModules.length + FarmModule.outOfScope.length, FarmModule.all.length);
      final milk = c.modules.firstWhere((m) => m.module == FarmModule.milkProduction);
      expect(milk.records, farm.count(FarmModule.milkProduction));
      expect(c.modules.firstWhere((m) => m.module == FarmModule.species).canEdit, isFalse);

      await farm.add(FarmModule.milkProduction, {'date': '2026-10-01', 'animal': 'AN-1001 · Shona', 'shift': 'Morning', 'litres': '7', 'quality': 'Accepted'});
      expect(c.modules.firstWhere((m) => m.module == FarmModule.milkProduction).records, milk.records + 1);
      expect(c.recentChanges().first.title, contains('Milk Production'));
      expect(c.recentChanges().first.by, 'Sharmin Akter');

      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      expect(c.hiddenModules, isEmpty);
      expect(c.recentChanges(), isNotEmpty, reason: 'the demo owner has demo activity');
      expect(c.recentChanges().every((a) => a.by == 'Farhana Akter'), isTrue, reason: 'only your own changes');
    });
  });

  testWidgets('a change made by one user is seen by every other user and role', (tester) async {
    await mockStorage({});
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Finder rail(String label) => find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
    Future<void> signIn(String role, String username, String password) async {
      await tester.tap(find.widgetWithText(ChoiceChip, role));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Username'), username);
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
      await tester.tap(find.text('Sign in as $role'));
      await tester.pumpAndSettle();
    }

    Future<void> signOut() async {
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
    }

    Future<void> open(String label) async {
      await tester.ensureVisible(rail(label));
      await tester.tap(rail(label));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const TechnovateFarmApp());
    await tester.pumpAndSettle();
    final farm = FarmController.instance;

    // 1. A Farm Manager with operations-only rights edits the newest milk record.
    await signIn('Farm Manager', 'manager03', 'manager03pass');
    expect(rail(FarmModule.sales), findsNothing, reason: 'no sales rights');
    await open(FarmModule.species);
    expect(find.text('View only'), findsOneWidget);
    expect(find.text('Add new'), findsNothing);
    await open(FarmModule.milkProduction);
    final target = RecordsController(FarmModule.milkProduction).filtered.first;
    await tester.tap(find.byTooltip('Record actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing, reason: 'only the owner deletes');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Litres'), '12.5');
    await tester.ensureVisible(find.text('Save record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(farm.find(FarmModule.milkProduction, target.id)!['litres'], '12.5');
    expect(LocalStorageService.instance.readRecords(FarmModule.milkProduction)!.firstWhere((r) => r['id'] == target.id)['litres'], '12.5', reason: 'saved in Hive');

    // The manager's own profile lists the change.
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My profile'));
    await tester.pumpAndSettle();
    expect(inProfile(find.text('Your farm data')), findsNothing, reason: 'section removed');
    expect(inProfile(find.textContaining('Milk Production record updated · ${target.id}')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await signOut();

    // 2. Another Farm Manager sees that change, and
    // who made it.
    await signIn('Farm Manager', 'manager05', 'manager05pass');
    await open(FarmModule.milkProduction);
    await tester.tap(find.byTooltip('Record actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('12.5'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // The manager changes it again; the owner then sees that.
    await tester.tap(find.byTooltip('Record actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Litres'), '11');
    await tester.ensureVisible(find.text('Save record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    await signOut();

    // 3. Farm Owner sees the latest value and both changes in the activity log.
    await signIn('Farm Owner', 'owner', 'owner123');
    expect(farm.find(FarmModule.milkProduction, target.id)!['litres'], '11');
    final changes = farm.activity.where((a) => a.title == 'Milk Production record updated · ${target.id}').map((a) => a.by).toList();
    expect(changes, ['Rokeya Begum', 'Sharmin Akter']);
  });

  testWidgets('an edit shows at once on an open profile page', (tester) async {
    await mockStorage({});
    final farm = FarmController.instance;
    await farm.init();
    await AuthController.instance.init();
    await AuthController.instance.login(role: UserRole.manager, username: 'manager', password: 'manager123');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CowProfilePage(animalId: 'AN-1004')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Moti'), findsWidgets);
    await tester.runAsync(() async {
      final moti = farm.find(FarmModule.animals, 'AN-1004')!;
      await farm.update(FarmModule.animals, FarmRecord({...moti.toJson(), 'name': 'Motijheel'}));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Motijheel'), findsWidgets);
    // Linked records show the new name too.
    expect(farm.list(FarmModule.milkProduction).where((m) => FarmRecord.refId(m['animal']) == 'an-1004').every((m) => m['animal'] == 'AN-1004 · Motijheel'), isTrue);
    expect(MyProfilePage, isNotNull);
  });
}
