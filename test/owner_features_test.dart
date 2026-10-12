import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/account_controllers.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/dashboard_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_profile.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  late FarmController farm;
  late AuthController auth;
  final demoDay = DateTime(2026, 10, 10, 9);

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => demoDay);
    auth = AuthController(LocalStorageService.instance);
    farm.actor = () => auth.currentUser?.name;
    auth.onAudit = farm.log;
    await farm.init();
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  });

  AlertsController alertsAt(DateTime now) => AlertsController(farm: farm, auth: auth, clock: () => now);

  group('alerts are computed from the data', () {
    test('demo data raises low stock, health, breeding and payment alerts', () {
      final titles = alertsAt(demoDay).active.map((a) => a.title).toList();
      expect(titles, contains('Mineral Mixture is running low'));
      expect(titles.any((t) => t.startsWith('Moti')), isTrue);
      expect(titles, contains('Shona: pregnancy check due'));
      expect(titles, contains('Moti: not pregnant — re-breed'));
      expect(titles, contains('Moti: milk withdrawal period'));
      expect(titles, contains('Rahman Grocery has a payment due'));
      // Completed vaccination far in the future is not an alert.
      expect(titles.any((t) => t.startsWith('Badsha')), isFalse);
    });

    test('restocking clears the low stock alert', () async {
      final item = farm.list(FarmModule.inventory).firstWhere((r) => r['name'] == 'Mineral Mixture');
      await farm.add(FarmModule.inventoryTx, {'date': '2026-10-10', 'item': item['name'], 'type': FarmModule.txPurchase, 'quantity': '200', 'unitCost': '120'});
      expect(alertsAt(demoDay).active.map((a) => a.title), isNot(contains('Mineral Mixture is running low')));
    });

    test('overdue health follow-ups are flagged as overdue', () {
      final later = alertsAt(demoDay.add(const Duration(days: 10))).active;
      expect(later.any((a) => a.title.contains('overdue')), isTrue);
    });

    test('mark read is remembered per user, and can be undone', () async {
      final alerts = alertsAt(demoDay);
      final first = alerts.active.first;
      await alerts.dismiss(first.id);
      expect(alertsAt(demoDay).active.map((a) => a.id), isNot(contains(first.id)));

      await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
      expect(alertsAt(demoDay).active.map((a) => a.id), contains(first.id));

      await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
      final again = alertsAt(demoDay);
      await again.restoreDismissed();
      expect(again.active.map((a) => a.id), contains(first.id));
    });

    test('users only see alerts for modules they can open', () async {
      // manager03 runs operations only (no sales rights).
      await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
      final modules = alertsAt(demoDay).active.map((a) => a.module).toSet();
      expect(modules, isNot(contains(FarmModule.sales)));
      expect(modules, contains(FarmModule.inventory));
      expect(modules, contains(FarmModule.health));
    });
  });

  test('dashboard counts only today\'s milk and shows the net balance', () {
    final dash = DashboardController(farm: farm, auth: auth, alerts: alertsAt(demoDay), clock: () => demoDay);
    final todays = farm.sum(FarmModule.milkProduction, 'litres', where: (r) => r['date'] == '2026-10-10');
    expect(todays, greaterThan(0));
    expect(dash.milkToday, todays);
    expect(DashboardController(farm: farm, auth: auth, alerts: alertsAt(demoDay), clock: () => DateTime(2026, 10, 11)).milkToday, 0);
    expect(dash.feedTodayKg, farm.sum(FarmModule.feedRecords, 'qty', where: (r) => r['date'] == '2026-10-10'));
    expect(dash.pregnantCount, 2);
    expect(dash.monthProfit, dash.month.profitAndLoss.operatingProfit);
    expect(dash.greeting, 'Good morning, Farhana');
    expect(dash.headline, contains('need your attention'));
  });

  test('profit & loss report and CSV export', () {
    final reports = ReportsController(farm: farm, auth: auth, clock: () => demoDay)..applyPreset('All time');
    final pnl = reports.farmPnl();
    final total = pnl.rows.firstWhere((r) => r[1] == 'Total revenue');
    expect(double.parse(total[2]), closeTo(farm.sum(FarmModule.sales, 'amount'), 1));
    final csv = reports.buildCsv(FarmModule.sales)!.split('\n');
    expect(csv.first, startsWith('"id","date","product","customer"'));
    expect(csv, hasLength(farm.count(FarmModule.sales) + 1));
  });

  test('form validation by field type, and inventory status is automatic', () async {
    final form = RecordFormController(module: FarmModule.inventory, farm: farm, auth: auth, clock: () => demoDay);
    expect(form.validate('qty', 'abc'), contains('number'));
    expect(form.validate('qty', '-1'), contains('negative'));
    expect(form.validate('qty', '12.5'), isNull);
    expect(form.validate('category', ''), contains('choose'));
    expect(form.validate('status', ''), isNull, reason: 'status is set automatically');
    form.dispose();

    final milk = RecordFormController(module: FarmModule.milkProduction, farm: farm, auth: auth, clock: () => demoDay);
    expect(milk.textControllers['date']!.text, '2026-10-10', reason: 'new records default to today');
    expect(milk.optionsFor('animal'), contains('AN-1001 · Shona'));
    expect(milk.validate('date', '10/10/2026'), isNotNull);
    milk.dispose();

    final health = RecordFormController(module: FarmModule.health, farm: farm, auth: auth);
    expect(health.validate('next', ''), isNull, reason: 'next date is optional');
    health.dispose();

    final customers = RecordFormController(module: FarmModule.customers, farm: farm, auth: auth);
    expect(customers.validate('phone', 'call me'), isNotNull);
    expect(customers.validate('phone', '01700000001'), isNull);
    customers.dispose();
  });

  test('activity log records who made each change', () async {
    await farm.add(FarmModule.sales, {'date': '2026-10-10', 'customer': 'X', 'item': 'Milk', 'qty': '1 L', 'amount': '120', 'status': 'Paid'});
    expect(farm.activity.first.by, 'Farhana Akter');
    expect(farm.activity.first.title, startsWith('New Sales record added · S-'));
  });

  test('farm profile can be edited and persists', () async {
    await farm.updateProfile(const FarmProfile(name: 'Green Acres', location: 'Bogura', phone: '01711111111', currency: 'Tk '));
    final fresh = FarmController(LocalStorageService.instance);
    await fresh.init();
    expect(fresh.profile.name, 'Green Acres');
    expect(fresh.profile.currency, 'Tk ');
    expect(farm.activity.first.title, 'Farm profile and calculation settings updated');
  });

  group('backup & restore', () {
    test('a backup restores records, profile and activity exactly', () async {
      final backup = jsonEncode(farm.exportData());
      expect(backup, isNot(contains('passwordHash')));

      final animals = farm.count(FarmModule.animals);
      final purchases = farm.count(FarmModule.purchases);
      await farm.remove(FarmModule.purchases, 'PO-9001');
      await farm.add(FarmModule.animals, {'name': 'Extra', 'species': 'Goat', 'sex': 'Female', 'status': 'Active'});
      await farm.updateProfile(const FarmProfile(name: 'Changed'));
      expect(farm.count(FarmModule.animals), animals + 1);
      expect(farm.count(FarmModule.purchases), purchases - 1);

      final c = BackupController(farm: farm, auth: auth)..restoreInput.text = backup;
      expect(await c.restore(), isTrue);
      expect(farm.count(FarmModule.animals), animals);
      expect(farm.count(FarmModule.purchases), purchases);
      expect(farm.profile.name, 'Nabijah Demo Farm');
      expect(farm.activity.first.title, 'Data restored from backup');
    });

    test('invalid backups are rejected without changing anything', () async {
      final animals = farm.count(FarmModule.animals);
      final c = BackupController(farm: farm, auth: auth);
      c.restoreInput.text = 'not json';
      expect(await c.restore(), isFalse);
      expect(c.error, isNotNull);

      c.restoreInput.text = jsonEncode({'app': 'something else'});
      expect(await c.restore(), isFalse);

      c.restoreInput.text = jsonEncode({
        'app': 'technovate_farm',
        'version': 1,
        'records': {
          'Animals': [
            {'name': 'no id'}
          ],
        },
      });
      expect(await c.restore(), isFalse);
      expect(farm.count(FarmModule.animals), animals);
    });

    test('only the owner can restore', () async {
      await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
      final c = BackupController(farm: farm, auth: auth)..restoreInput.text = jsonEncode(farm.exportData());
      expect(await c.restore(), isFalse);
      expect(c.error, contains('Only the Farm Owner'));
    });
  });
}
