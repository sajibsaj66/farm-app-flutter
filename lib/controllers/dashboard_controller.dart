import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/access_policy.dart';
import '../models/activity_entry.dart';
import '../models/alert_item.dart';
import '../models/farm_module.dart';
import '../models/farm_profile.dart';
import '../models/farm_record.dart';
import '../models/finance.dart';
import '../models/user_role.dart';
import 'alerts_controller.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'finance_engine.dart';
import 'health_rules.dart';
import 'herd_analytics.dart';

/// One month on the owner's trend table.
class MonthTrend {
  const MonthTrend({required this.month, required this.milkLitres, required this.revenue, required this.costs});

  /// "2026-10".
  final String month;
  final double milkLitres;
  final double revenue;
  final double costs;

  double get profit => revenue - costs;
}

/// A task for today or overdue, on the manager's dashboard.
class DashboardTask {
  const DashboardTask({required this.title, required this.detail, required this.module, this.recordId, this.overdue = false});

  final String title;
  final String detail;
  final String module;
  final String? recordId;
  final bool overdue;
}

/// Figures for the two dashboards. Every number is worked out from the
/// records saved on this device — nothing is estimated or typed in.
///
/// * Farm Owner: business performance — herd by status, milk, feed, vet
///   costs, purchases, sales, expenses, profit, stock, trends and the
///   managers' recorded activity.
/// * Farm Manager: today's operations — feeding, milking, health, doses and
///   vaccinations due, low stock, pending tasks and recent activity.
class DashboardController {
  DashboardController({FarmController? farm, AuthController? auth, AlertsController? alerts, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        alerts = alerts ?? AlertsController.instance,
        _clock = clock ?? DateTime.now;

  final FarmController farm;
  final AlertsController alerts;
  final AuthController _auth;
  final DateTime Function() _clock;

  FarmProfile get profile => farm.profile;

  AccessPolicy get access => _auth.access;

  bool get isOwner => access.isOwner;

  DateTime get today => dateOnly(_clock());

  String get _todayKey => formatDate(today);

  String get greeting {
    final hour = _clock().hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final name = _auth.currentUser?.firstName;
    return name == null ? part : '$part, $name';
  }

  /// Quick actions and cards only link to modules the user may open.
  bool canOpen(String module) => access.canOpenModule(module);

  bool canEdit(String module) => access.canEditModule(module);

  bool get canSeeFinance => access.canSeeFinance;

  String money(double v) => '${profile.currency}${v.toStringAsFixed(0)}';

  // ------------------------------------------------------------------ herd

  List<FarmRecord> get _animals => farm.list(FarmModule.animals);

  /// Animals on the farm now (any status other than sold, dead, transferred
  /// or archived — so pregnant, dry and under-treatment animals count).
  int get animalCount => _animals.where(FarmController.isActive).length;

  int get registeredAnimals => _animals.length;

  /// Registered animals by status group, in a fixed order.
  Map<String, int> get animalsByStatus {
    int count(String status) => _animals.where((a) => a.status.toLowerCase() == status).length;
    return {
      'On farm': animalCount,
      'Sold': count('sold'),
      'Transferred': count('transferred'),
      'Deceased': count('dead'),
      if (count('archived') > 0) 'Archived': count('archived'),
    };
  }

  int get pregnantCount => HerdAnalytics(farm, today: _clock()).breeding.pregnant;

  // ------------------------------------------------------------------ milk

  double _milkBetween(DateTime from, DateTime to) => farm.inRange(FarmModule.milkProduction, from, to).fold(0.0, (s, m) => s + m.number('litres'));

  double get milkToday => _milkBetween(today, today);
  double get milkThisWeek => _milkBetween(today.subtract(const Duration(days: 6)), today);
  double get milkThisMonth => _milkBetween(DateTime(today.year, today.month), today);
  double get milkTotal => farm.sum(FarmModule.milkProduction, 'litres');

  /// Litres recorded as Withheld or Rejected this month (not for sale).
  double get milkWithheldThisMonth =>
      farm.inRange(FarmModule.milkProduction, DateTime(today.year, today.month), today).where((m) => !FarmController.isSellableMilk(m)).fold(0.0, (s, m) => s + m.number('litres'));

  /// Lactating cows with no milk recorded today.
  List<FarmRecord> get cowsNotMilkedToday {
    final milked = farm.list(FarmModule.milkProduction).where((m) => '${m['date']}' == _todayKey).map((m) => FarmRecord.refId(m['animal'])).toSet();
    return _animals.where((a) => FarmController.isActive(a) && '${a['group']}' == 'Lactating cows' && !milked.contains(a.id.toLowerCase())).toList();
  }

  // ------------------------------------------------------------------ feed

  Iterable<FarmRecord> _feedBetween(DateTime from, DateTime to) => farm.inRange(FarmModule.feedRecords, from, to);

  double _kg(Iterable<FarmRecord> rows) => rows.fold(0.0, (s, r) => s + (Units.kg(r.number('qty'), '${r['unit'] ?? 'kg'}') ?? 0));

  double _cost(Iterable<FarmRecord> rows) => rows.fold(0.0, (s, r) => s + (r.number('totalCost') > 0 ? r.number('totalCost') : r.number('qty') * (farm.feedItem(r['feed'])?.number('unitCost') ?? 0)));

  int get feedEntriesToday => _feedBetween(today, today).length;
  double get feedTodayKg => _kg(_feedBetween(today, today));
  double get feedTodayCost => _cost(_feedBetween(today, today));
  double get feedMonthKg => _kg(_feedBetween(DateTime(today.year, today.month), today));
  double get feedMonthCost => _cost(_feedBetween(DateTime(today.year, today.month), today));

  // ------------------------------------------------------------- finances

  /// This calendar month so far.
  late final FinanceEngine month = FinanceEngine(farm, ReportFilter(from: DateTime(today.year, today.month), to: today));

  double get monthProfit => month.profitAndLoss.operatingProfit;
  double get monthRevenue => month.profitAndLoss.revenue;
  double get monthCosts => month.profitAndLoss.costs;
  double get monthCashFlow => month.netCashFlow;

  /// Veterinary, treatment and medicine costs this month (health records,
  /// treatment plans, consultation fees and vet/medicine expenses).
  double get monthVetCosts {
    final c = month.profitAndLoss.costsByCategory;
    return (c[FinanceEngine.catTreatment] ?? 0) + (c['Veterinary treatment'] ?? 0) + (c['Medicine and vaccines'] ?? 0);
  }

  Iterable<FarmRecord> _thisMonth(String module) => farm.inRange(module, DateTime(today.year, today.month), today);

  /// Expenses this month that count (approved or not needing approval).
  double get monthExpenses => _thisMonth(FarmModule.expenses).where((e) => !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount'));

  /// Expenses this month still waiting for the owner's approval.
  double get monthPendingExpenses => _thisMonth(FarmModule.expenses).where((e) => '${e['approval']}' == FarmModule.approvalPending).fold(0.0, (s, e) => s + e.number('amount'));

  double get monthlyBudget => profile.monthlyBudget;

  /// Share of this month's budget used (null when no budget is set).
  double? get budgetUsed => monthlyBudget <= 0 ? null : monthExpenses / monthlyBudget;

  /// What the farm owes: unpaid expenses and purchases due to suppliers
  /// (refused ones excluded).
  double get payables =>
      farm.list(FarmModule.expenses).where((e) => '${e['payment']}' == 'Due' && !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount')) +
      farm.list(FarmModule.purchases).where((p) => '${p['status']}' == 'Due' && !FarmModule.awaitsOrRefused(p['approval'])).fold(0.0, (s, p) => s + p.number('amount'));

  // ------------------------------------------------------ owner decisions

  /// Large expenses/purchases, requests and reports waiting for the owner.
  List<(String, FarmRecord)> get pendingDecisions => farm.pendingDecisions.where((d) => access.canOpenModule(d.$1)).toList();

  /// The signed-in manager's own requests, newest first.
  List<FarmRecord> get myRequests => farm.list(FarmModule.requests).where((r) => '${r['requestedBy']}' == _auth.currentUser?.name).toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));

  /// Whether today's daily report has been sent to the owner.
  bool get dailyReportSent => farm.list(FarmModule.managerReports).any((r) => '${r['date']}' == _todayKey && '${r['period']}' == 'Daily');

  // ---------------------------------------------------------- staff tasks

  List<FarmRecord> get staffTasksToday => farm.list(FarmModule.tasks).where((t) => '${t['date']}' == _todayKey).toList();

  int get staffTasksDone => staffTasksToday.where((t) => '${t['status']}' == 'Done').length;

  /// Marks a staff task done (checked by the signed-in user).
  Future<void> markTaskDone(FarmRecord task) => farm.update(FarmModule.tasks, FarmRecord({...task.toJson(), 'status': 'Done'}));

  /// Net sales recorded this month.
  double get monthSales => _thisMonth(FarmModule.sales).fold(0.0, (s, e) => s + e.number('amount'));

  int get monthSalesCount => _thisMonth(FarmModule.sales).length;

  /// Supplier purchases recorded this month. (A log of orders: their cost
  /// reaches profit through expenses and stock, so it is not added again.)
  double get monthPurchases => _thisMonth(FarmModule.purchases).fold(0.0, (s, e) => s + e.number('amount'));

  double get purchasesDue => farm.list(FarmModule.purchases).where((p) => '${p['status']}' == 'Due').fold(0.0, (s, e) => s + e.number('amount'));

  /// Money customers still owe.
  double get receivables => farm.list(FarmModule.sales).fold(0.0, (s, r) => s + (r.number('due') > 0 ? r.number('due') : 0));

  /// The last six months, oldest first.
  List<MonthTrend> get trends {
    final engine = FinanceEngine(farm, ReportFilter(from: DateTime(today.year, today.month - 5), to: today));
    return [
      for (final (key, revenue, costs, _, _) in engine.monthly)
        MonthTrend(
          month: key,
          revenue: revenue,
          costs: costs,
          milkLitres: farm.list(FarmModule.milkProduction).where((m) => '${m['date']}'.startsWith(key)).fold(0.0, (s, m) => s + m.number('litres')),
        ),
    ];
  }

  // ------------------------------------------------------------ inventory

  int get inventoryCount => farm.count(FarmModule.inventory);

  List<FarmRecord> get lowStockItems => farm.list(FarmModule.inventory).where((r) => r.isLowStock).toList();

  int get lowStockCount => lowStockItems.length;

  double get stockValue => farm.list(FarmModule.inventory).fold(0.0, (s, i) => s + i.number('qty') * i.number('unitCost'));

  // --------------------------------------------------------------- health

  List<FarmRecord> get openIllness => farm.list(FarmModule.illness).where((c) => HealthRules.isOpen(c.data)).toList();

  List<FarmRecord> get urgentIllness => openIllness.where((c) => HealthRules.isUrgent(farm, c)).toList();

  /// Doses, follow-ups and vaccinations due today (or within a week for
  /// vaccinations), and anything overdue.
  List<DashboardTask> get tasksToday {
    final out = <DashboardTask>[];
    for (final m in farm.list(FarmModule.medication).where((m) => '${m['status']}' == FarmModule.medScheduled)) {
      final at = m.dateOf('scheduledAt');
      if (at == null || dateOnly(at).isAfter(today)) continue;
      out.add(DashboardTask(
          title: '${FarmRecord.displayName(m['animal'])}: ${m['medicine']} dose',
          detail: 'Scheduled ${m['scheduledAt']}',
          module: FarmModule.medication,
          recordId: m.id,
          overdue: dateOnly(at).isBefore(today)));
    }
    for (final f in farm.list(FarmModule.followUps).where((f) => '${f['status']}' == 'Scheduled')) {
      final due = f.dateOf('dueDate');
      if (due == null || due.isAfter(today)) continue;
      out.add(DashboardTask(
          title: '${FarmRecord.displayName(f['animal'])}: ${f['type']}', detail: 'Follow-up due ${f['dueDate']}', module: FarmModule.followUps, recordId: f.id, overdue: due.isBefore(today)));
    }
    for (final h in farm.list(FarmModule.health).where((h) => '${h['status']}' != 'Completed')) {
      final due = h.dateOf('next') ?? h.dateOf('date');
      if (due == null || due.isAfter(today.add(const Duration(days: 7)))) continue;
      final who = '${h['animal'] ?? ''}'.isNotEmpty ? FarmRecord.displayName(h['animal']) : 'Herd';
      out.add(DashboardTask(
          title: '$who: ${h['type']} — ${h['details']}',
          detail: due.isBefore(today) ? 'Was due ${formatDate(due)}' : 'Due ${formatDate(due)}',
          module: FarmModule.health,
          recordId: h.id,
          overdue: due.isBefore(today)));
    }
    out.sort((a, b) => (b.overdue ? 1 : 0).compareTo(a.overdue ? 1 : 0));
    return out;
  }

  // --------------------------------------------------- alerts and activity

  int get alertCount => alerts.activeCount;

  String get headline => switch (alertCount) {
        0 => 'Your farm is in good shape.',
        1 => '1 item needs your attention.',
        _ => '$alertCount items need your attention.',
      };

  List<AlertItem> get attentionItems => alerts.active.take(4).toList();

  /// Activity this user may see. For managers, entries about records they
  /// cannot open (e.g. sales without that right) and account or settings
  /// changes are left out.
  List<ActivityEntry> recentActivity({int limit = 6}) {
    if (access.canViewActivityLog) return farm.activity.take(limit).toList();
    final hidden = [
      for (final m in FarmModule.all)
        if (!access.canOpenModule(m.name)) m.name
    ];
    const settings = ['user', 'password', 'farm profile', 'backup', 'demo', 'restored', 'settings', 'moved to hive'];
    return farm.activity.where((a) => !hidden.any((m) => a.title.contains(m)) && !settings.any((w) => a.title.toLowerCase().contains(w))).take(limit).toList();
  }

  /// What the farm managers recorded recently (for the owner to review).
  List<ActivityEntry> managerActivity({int limit = 6}) {
    final managers = _auth.users.where((u) => u.role == UserRole.manager).map((u) => u.name).toSet();
    return farm.activity.where((a) => managers.contains(a.by)).take(limit).toList();
  }

  // ------------------------------------------------ kept for older callers

  double get salesTotal => farm.sum(FarmModule.sales, 'amount');
  double get expensesTotal => farm.sum(FarmModule.expenses, 'amount');
  double get netBalance => monthProfit;
}
