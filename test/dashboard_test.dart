import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/dashboard_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/finance_engine.dart';
import 'package:technovate_farm_management/core/theme/app_theme.dart';
import 'package:technovate_farm_management/core/utils/dates.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/finance.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';
import 'package:technovate_farm_management/views/dashboard_view.dart';

import 'support/mock_storage.dart';

/// The Owner and Manager dashboards: every figure must equal what the saved
/// records add up to, and each role sees its own dashboard.
void main() {
  final now = DateTime(2026, 10, 20, 9);
  final today = dateOnly(now);
  final monthStart = DateTime(2026, 10);
  late FarmController farm;
  late AuthController auth;

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => now);
    await farm.init();
    auth = AuthController(LocalStorageService.instance);
    await auth.init();
    farm.actor = () => auth.currentUser?.name;
    farm.access = () => auth.access;
  });

  DashboardController dash() => DashboardController(farm: farm, auth: auth, alerts: AlertsController(farm: farm, auth: auth, clock: () => now), clock: () => now);

  double sum(String module, String field, {DateTime? from}) => farm.inRange(module, from ?? monthStart, today).fold(0.0, (s, r) => s + r.number(field));

  test('owner figures match the saved records', () async {
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    final d = dash();
    expect(d.isOwner, isTrue);

    // Herd by status adds up to every registered animal.
    final status = d.animalsByStatus;
    expect(status.values.fold(0, (a, b) => a + b), farm.count(FarmModule.animals));
    expect(status['Sold'], farm.list(FarmModule.animals).where((a) => a.status == 'Sold').length);
    expect(status['Deceased'], farm.list(FarmModule.mortality).where((m) => '${m['animal']}'.isNotEmpty).length, reason: 'every mortality record marks its animal dead');

    // Milk: today, last 7 days, this month.
    expect(d.milkToday, sum(FarmModule.milkProduction, 'litres', from: today));
    expect(d.milkThisWeek, sum(FarmModule.milkProduction, 'litres', from: today.subtract(const Duration(days: 6))));
    expect(d.milkThisMonth, sum(FarmModule.milkProduction, 'litres'));

    // Money this month equals the underlying records.
    expect(d.monthSales, sum(FarmModule.sales, 'amount'));
    // Only approved spending counts (the demo has one pending and one rejected expense).
    expect(d.monthExpenses, farm.inRange(FarmModule.expenses, monthStart, today).where((e) => !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount')));
    expect(d.monthExpenses, lessThan(sum(FarmModule.expenses, 'amount')));
    expect(d.monthPurchases, sum(FarmModule.purchases, 'amount'));
    expect(d.feedMonthCost, closeTo(sum(FarmModule.feedRecords, 'totalCost'), 0.01));
    final engine = FinanceEngine(farm, ReportFilter(from: monthStart, to: today));
    expect(d.monthRevenue, engine.profitAndLoss.revenue);
    expect(d.monthProfit, engine.profitAndLoss.revenue - engine.profitAndLoss.costs);
    expect(d.monthVetCosts, greaterThan(0));
    expect(d.receivables, farm.list(FarmModule.sales).fold(0.0, (s, r) => s + (r.number('due') > 0 ? r.number('due') : 0)));
    expect(d.stockValue, farm.list(FarmModule.inventory).fold(0.0, (s, i) => s + i.number('qty') * i.number('unitCost')));

    // Six-month trend: one row per month, the same revenue as the P&L.
    final trends = d.trends;
    expect(trends, hasLength(6));
    expect(trends.last.month, '2026-10');
    final six = FinanceEngine(farm, ReportFilter(from: DateTime(2026, 5), to: today));
    expect(trends.fold(0.0, (s, t) => s + t.revenue), closeTo(six.profitAndLoss.revenue, 0.01));
    expect(trends.last.milkLitres, d.milkThisMonth);

    // The owner reviews what managers recorded.
    expect(d.managerActivity().every((a) => auth.users.any((u) => u.name == a.by && u.role == UserRole.manager)), isTrue);
    expect(d.managerActivity(), isNotEmpty);
  });

  test('a new sale and expense show on the owner dashboard at once', () async {
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    final (sales, expenses, profit) = (dash().monthSales, dash().monthExpenses, dash().monthProfit);
    await farm.add(FarmModule.sales, {'date': formatDate(today), 'product': 'Manure', 'customer': 'Moyna Store', 'qty': '100', 'unit': 'kg', 'unitPrice': '5'});
    await farm.add(FarmModule.expenses, {'date': formatDate(today), 'category': 'Water', 'amount': '250', 'description': 'Pump repair', 'scope': FarmModule.scopeFarm, 'payment': 'Paid'});
    final after = dash();
    expect(after.monthSales, sales + 500);
    expect(after.monthExpenses, expenses + 250);
    expect(after.monthProfit, closeTo(profit + 500 - 250, 0.01));
  });

  test('manager sees today\'s work, and no money without the right', () async {
    await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
    final d = dash();
    expect(d.isOwner, isFalse);
    expect(d.canSeeFinance, isFalse);
    expect(d.canEdit(FarmModule.sales), isFalse);
    expect(d.canEdit(FarmModule.milkProduction), isTrue);

    // Lactating cows still to milk today.
    final milkedToday = farm.list(FarmModule.milkProduction).where((m) => m['date'] == formatDate(today)).map((m) => m['animal']).toSet();
    for (final cow in d.cowsNotMilkedToday) {
      expect(cow['group'], 'Lactating cows');
      expect(milkedToday, isNot(contains(cow.reference)));
    }
    await farm.add(FarmModule.milkProduction, {'date': formatDate(today), 'animal': 'AN-1001 · Shona', 'shift': 'Morning', 'litres': '12', 'quality': 'Accepted'});
    expect(dash().cowsNotMilkedToday.any((c) => c.id == 'AN-1001'), isFalse);

    // Tasks due: every scheduled dose, follow-up or vaccination due by today.
    for (final t in d.tasksToday) {
      expect(farm.find(t.module, t.recordId!), isNotNull);
    }
    // Recent activity hides money records and account changes.
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    await farm.add(FarmModule.sales, {'date': formatDate(today), 'product': 'Manure', 'customer': 'Moyna Store', 'qty': '10', 'unit': 'kg', 'unitPrice': '5'});
    await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
    expect(dash().recentActivity(limit: 50).any((a) => a.title.contains(FarmModule.sales)), isFalse);
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    expect(dash().recentActivity(limit: 50).any((a) => a.title.contains(FarmModule.sales)), isTrue);
  });

  for (final (role, user, password, title) in const [
    (UserRole.owner, 'owner', 'owner123', 'Owner dashboard'),
    (UserRole.manager, 'manager03', 'manager03pass', 'Today on the farm'),
  ]) {
    testWidgets('$user sees the $title', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await AuthController.instance.init();
      await FarmController.instance.init();
      await AuthController.instance.login(role: role, username: user, password: password);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: DashboardPage(onOpenSection: (_) {}))));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      if (role == UserRole.owner) {
        expect(find.text('Herd'), findsOneWidget);
        expect(find.textContaining('this month'), findsWidgets);
      } else {
        expect(find.text('Milking'), findsOneWidget);
        expect(find.text('Herd'), findsNothing);
        expect(find.textContaining('Operating'), findsNothing, reason: 'no money for an operations-only manager');
      }
    });
  }
}
