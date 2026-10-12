import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/cow_profile_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/health_analytics.dart';
import 'package:technovate_farm_management/controllers/illness_controller.dart';
import 'package:technovate_farm_management/controllers/login_controller.dart';
import 'package:technovate_farm_management/controllers/navigation_controller.dart';
import 'package:technovate_farm_management/controllers/records_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/core/theme/app_theme.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';
import 'package:technovate_farm_management/views/dashboard_view.dart';
import 'package:technovate_farm_management/views/health_dashboard_view.dart';
import 'package:technovate_farm_management/views/login_view.dart';
import 'package:technovate_farm_management/views/records_view.dart';
import 'package:technovate_farm_management/views/widgets/dashboard_widgets.dart';
import 'package:technovate_farm_management/views/widgets/record_card.dart';

import 'support/mock_storage.dart';

/// QA: every filter changes the data on screen to exactly the records that
/// match it, and every button reaches something this user may open.
void main() {
  final farm = FarmController.instance;
  final auth = AuthController.instance;

  setUp(() async {
    await mockStorage({});
    await farm.init();
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  });

  group('sign-in remembers each role', () {
    test('choosing a role fills in its own username and password', () async {
      await auth.logout();
      final c = LoginController(auth: auth);
      expect((c.username.text, c.password.text), ('owner', 'owner123'));
      c.selectRole(UserRole.manager);
      expect((c.username.text, c.password.text), ('manager', 'manager123'));
      c.selectRole(UserRole.owner);
      expect(c.username.text, 'owner');
      c.dispose();
    });

    test('the last successful sign-in per role is remembered, and kept in step with password changes', () async {
      await auth.logout();
      expect(await auth.login(role: UserRole.manager, username: 'manager04', password: 'manager04pass', remember: true), isNull);
      await auth.logout();
      final c = LoginController(auth: auth)..selectRole(UserRole.manager);
      expect((c.username.text, c.password.text), ('manager04', 'manager04pass'));
      expect(c.username.text, isNot(LoginController(auth: auth).username.text), reason: 'owner still shows the owner login');

      // Restart: still remembered (saved in Hive).
      final restarted = AuthController(LocalStorageService.instance);
      await restarted.init();
      expect(restarted.savedLoginFor(UserRole.manager), ('manager04', 'manager04pass'));

      // The owner resets that manager's password: the saved one follows.
      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      await auth.resetPassword('manager04', 'newpass44');
      expect(auth.savedLoginFor(UserRole.manager), ('manager04', 'newpass44'));
      // Deleting the account forgets it (back to the demo login).
      await auth.deleteUser('manager04');
      expect(auth.savedLoginFor(UserRole.manager), ('manager', 'manager123'));

      // Unticking "Remember" forgets it.
      await auth.logout();
      await auth.login(role: UserRole.manager, username: 'manager06', password: 'manager06pass', remember: true);
      await auth.logout();
      await auth.login(role: UserRole.manager, username: 'manager06', password: 'manager06pass', remember: false);
      expect(auth.savedLoginFor(UserRole.manager), ('manager', 'manager123'));
      c.dispose();
    });

    testWidgets('the sign-in screen shows each role\'s details and signs in with them', (tester) async {
      await auth.logout();
      await tester.runAsync(() => auth.login(role: UserRole.manager, username: 'manager02', password: 'manager02pass', remember: true));
      await auth.logout();
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const LoginPage()));
      await tester.pumpAndSettle();
      String field(String label) => tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!.text;
      expect((field('Username'), field('Password')), ('owner', 'owner123'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Farm Manager'));
      await tester.pumpAndSettle();
      expect((field('Username'), field('Password')), ('manager02', 'manager02pass'));
      await tester.scrollUntilVisible(find.text('Sign in as Farm Manager'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in as Farm Manager'));
      await tester.pumpAndSettle();
      expect(auth.currentUser?.username, 'manager02');
    });
  });

  group('record lists: status filters, search and sort', () {
    test('every status filter of every section shows exactly the matching records', () {
      for (final m in FarmModule.all.where((m) => auth.access.canOpenModule(m.name))) {
        final c = RecordsController(m.name);
        final all = c.all;
        expect(c.filters.first, 'All');
        expect(c.filtered, hasLength(all.length), reason: '${m.name}: All');
        for (final f in c.filters.skip(1)) {
          c.setFilter(f);
          expect(c.filter, f);
          expect(c.filtered.every((r) => r.status.toLowerCase() == f.toLowerCase()), isTrue, reason: '${m.name}: $f');
          expect(c.filtered, hasLength(all.where((r) => r.status.toLowerCase() == f.toLowerCase()).length), reason: '${m.name}: $f');
        }
        c.setFilter('All');
        // Search: the first record's id finds it, and only matching records.
        if (all.isNotEmpty) {
          c.setQuery(all.first.id);
          expect(c.filtered.map((r) => r.id), contains(all.first.id), reason: m.name);
          expect(c.filtered.every((r) => r.matches(query: all.first.id, filter: 'All')), isTrue);
          c.setQuery('zz-no-such-record');
          expect(c.filtered, isEmpty);
          c.setQuery('');
        }
        c.dispose();
      }
    });

    test('sorting orders the list as named', () {
      final c = RecordsController(FarmModule.milkProduction);
      final newest = c.filtered.map((r) => '${r['date']}').toList();
      expect(newest, [...newest]..sort((a, b) => b.compareTo(a)));
      c.setSort(RecordSort.oldest);
      final oldest = c.filtered.map((r) => '${r['date']}').toList();
      expect(oldest, [...oldest]..sort());
      final animals = RecordsController(FarmModule.animals)..setSort(RecordSort.nameAz);
      final names = animals.filtered.map((r) => r.title.toLowerCase()).toList();
      expect(names, [...names]..sort());
    });

    testWidgets('tapping a filter chip and typing a search change the list on screen', (tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold(body: RecordsPage(module: FarmModule.animals))));
      await tester.pumpAndSettle();
      final all = farm.count(FarmModule.animals);
      expect(find.text('$all results'), findsOneWidget);
      final sold = farm.list(FarmModule.animals).where((a) => a.status == 'Sold').length;
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Sold'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Sold'));
      await tester.pumpAndSettle();
      expect(find.text('$sold results'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Kalu');
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      expect(find.descendant(of: find.byType(RecordCard), matching: find.text('Kalu')), findsOneWidget);
    });
  });

  group('health dashboard filters', () {
    test('each filter keeps only the animals that match it', () {
      final c = HealthDashboardController(farm: farm, auth: auth);
      final h = c.analytics;
      for (final status in FarmModule.healthStatuses) {
        c.update(HealthFilter(status: status));
        expect(h.rows(c.filter).every((r) => r.status == status), isTrue, reason: status);
      }
      for (final species in c.speciesOptions) {
        c.update(HealthFilter(species: species));
        final rows = h.rows(c.filter);
        expect(rows, isNotEmpty, reason: species);
        expect(rows.every((r) => r.animal['species'] == species), isTrue, reason: species);
      }
      for (final group in c.groupOptions) {
        c.update(HealthFilter(group: group));
        expect(h.rows(c.filter).every((r) => r.animal['group'] == group), isTrue, reason: group);
      }
      // The 'Reported sick' and 'Urgent vet attention' tiles.
      c.update(const HealthFilter(status: HealthAnalytics.filterSick));
      expect(h.rows(c.filter), hasLength(h.sickAnimalCount));
      expect(h.rows(c.filter).every((r) => r.openCases.isNotEmpty), isTrue);
      c.update(const HealthFilter(status: HealthAnalytics.filterUrgent));
      expect(h.rows(c.filter), hasLength(h.urgentAnimalCount));
      expect(h.rows(c.filter).every((r) => r.urgent), isTrue);
      c.update(const HealthFilter(treatment: 'Active treatment'));
      expect(h.rows(c.filter).every((r) => r.activeTreatments > 0), isTrue);
      c.update(const HealthFilter(query: 'Moti'));
      expect(h.rows(c.filter).map((r) => r.animal.id), ['AN-1004']);
      c.clear();
      expect(c.hasFilters, isFalse);
      expect(h.rows(c.filter), hasLength(h.rows(const HealthFilter()).length));
    });

    testWidgets('choosing a status on screen updates the animal count', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: HealthDashboardPage(onOpenSection: (_) {}))));
      await tester.pumpAndSettle();
      final h = HealthAnalytics(farm, today: farm.today);
      final treated = h.rows(const HealthFilter(status: FarmModule.healthTreatment)).length;
      await tester.scrollUntilVisible(find.widgetWithText(DropdownButtonFormField<String?>, 'Health status'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Health status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(FarmModule.healthTreatment).last);
      await tester.pumpAndSettle();
      expect(find.text('$treated animals'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('${h.rows(const HealthFilter()).length} animals'), findsOneWidget);
    });
  });

  group('report filters change the figures', () {
    test('species, animal, location and product filters, date presets and search', () {
      final r = ReportsController()..applyPreset('All time');
      r.setKind(ReportKind.animals);
      final all = r.build().rows.length;
      r.setFilter(r.filter.copyWith(species: 'Goat'));
      final goats = r.build().rows;
      expect(goats, isNotEmpty);
      expect(goats.length, lessThan(all));
      expect(goats.every((row) => row[1] == 'Goat'), isTrue);
      r.setFilter(r.filter.copyWith(clearSpecies: true, animal: 'AN-1001'));
      expect(r.build().rows.map((row) => row.first), ['AN-1001 · Shona']);
      r.setFilter(r.filter.copyWith(clearAnimal: true, location: 'Goat house'));
      final inGoatHouse = farm.list(FarmModule.animals).where((a) => a['location'] == 'Goat house').map((a) => a.reference).toSet();
      expect(r.build().rows.every((row) => inGoatHouse.contains(row.first)), isTrue);
      r.setFilter(r.filter.copyWith(clearLocation: true));

      r.setKind(ReportKind.sales);
      final allSales = r.build().rows.length;
      r.setFilter(r.filter.copyWith(product: 'Live animal'));
      final live = r.build().rows;
      expect(live.length, lessThan(allSales));
      expect(live.every((row) => row[2] == 'Live animal'), isTrue);
      r.setFilter(r.filter.copyWith(clearProduct: true));

      // A shorter period never shows more rows, and every row is inside it.
      r.setKind(ReportKind.feed);
      r.applyPreset('Last 7 days');
      final week = r.build().rows;
      expect(week.every((row) => row.first.compareTo(r.filter.from.toIso8601String().substring(0, 10)) >= 0), isTrue);
      r.applyPreset('Last 30 days');
      expect(r.build().rows.length, greaterThanOrEqualTo(week.length));

      // Search narrows rows to those containing the text.
      r.setKind(ReportKind.sales);
      r.applyPreset('All time');
      r.setQuery('Rahman Cattle Traders');
      expect(r.build().rows, isNotEmpty);
      expect(r.build().rows.every((row) => row.any((cell) => cell.contains('Rahman Cattle Traders'))), isTrue);
    });

    test('a cow profile\'s period chips change its totals', () {
      final c = CowProfileController('AN-1001');
      c.setPeriod(7);
      final week = c.analytics!.period(7).feedKg;
      c.setPeriod(30);
      expect(c.periodDays, 30);
      expect(c.analytics!.period(30).feedKg, greaterThan(week));
    });
  });

  group('dashboard buttons only lead to sections the user may open', () {
    for (final (role, user, password) in const [
      (UserRole.owner, 'owner', 'owner123'),
      (UserRole.manager, 'manager', 'manager123'),
      (UserRole.manager, 'manager03', 'manager03pass'),
    ]) {
      testWidgets(user, (tester) async {
        tester.view.physicalSize = const Size(500, 6000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(() => auth.login(role: role, username: user, password: password));
        final opened = <String>[];
        await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: DashboardPage(onOpenSection: opened.add))));
        await tester.pumpAndSettle();
        final allowed = NavigationController(auth.access).sections.map((s) => s.label).toSet();
        // Every tile and section link.
        final targets = [
          ...find.byType(StatTile).evaluate().map((e) => e.widget as StatTile).where((t) => t.onTap != null).map((t) => t.onTap!),
          ...find.byType(DashSection).evaluate().map((e) => e.widget as DashSection).where((s) => s.onAction != null).map((s) => s.onAction!),
        ];
        expect(targets, isNotEmpty);
        for (final tap in targets) {
          tap();
        }
        expect(opened, isNotEmpty);
        for (final label in opened) {
          expect(allowed, contains(label), reason: '$user: "$label" is not a section this user can open');
        }
      });
    }
  });
}
