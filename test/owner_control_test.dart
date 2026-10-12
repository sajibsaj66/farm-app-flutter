import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/approvals_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/dashboard_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/finance_engine.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/core/utils/dates.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/finance.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

import 'support/mock_storage.dart';

/// Owner control: approvals of large expenses and purchases, budget,
/// payables, managers' requests and reports, staff and daily tasks, and the
/// yearly and animal trade reports.
void main() {
  final now = DateTime(2026, 10, 20, 9);
  final today = dateOnly(now);
  late FarmController farm;
  late AuthController auth;
  final rule = throwsA(isA<FarmRuleException>());

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => now);
    await farm.init();
    auth = AuthController(LocalStorageService.instance);
    await auth.init();
    farm.actor = () => auth.currentUser?.name;
    farm.access = () => auth.access;
  });

  Future<void> asOwner() => auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  Future<void> asManager() => auth.login(role: UserRole.manager, username: 'manager', password: 'manager123'); // sales, purchases, expenses
  Map<String, dynamic> expense(String amount, {String approval = ''}) => {
        'date': formatDate(today),
        'category': 'Equipment',
        'amount': amount,
        'description': 'Item $amount',
        'scope': FarmModule.scopeFarm,
        'payment': 'Paid',
        if (approval.isNotEmpty) 'approval': approval
      };
  double counted() => FinanceEngine(farm, ReportFilter(from: DateTime(2026, 10), to: today)).profitAndLoss.costs;

  group('large expenses and purchases need the owner\'s approval', () {
    test('a manager\'s expense above the limit waits and is not counted until approved', () async {
      expect(farm.profile.approvalLimit, 20000);
      await asManager();
      final before = counted();
      // Even if the manager tries to mark it approved, the app decides.
      final big = await farm.add(FarmModule.expenses, expense('30000', approval: FarmModule.approvalApproved));
      expect(big['approval'], FarmModule.approvalPending);
      expect(counted(), before, reason: 'pending: not a cost yet');
      expect(farm.pendingDecisions.map((d) => d.$2.id), contains(big.id));
      await expectLater(farm.decide(FarmModule.expenses, big.id, approve: true), rule, reason: 'only the owner decides');

      final small = await farm.add(FarmModule.expenses, expense('5000'));
      expect(small['approval'], FarmModule.approvalNotRequired);
      expect(counted(), before + 5000);

      await asOwner();
      await expectLater(farm.decide(FarmModule.expenses, big.id, approve: false), rule, reason: 'a rejection needs a reason');
      await farm.decide(FarmModule.expenses, big.id, approve: true, note: 'OK, buy it');
      expect(farm.find(FarmModule.expenses, big.id)!['approval'], FarmModule.approvalApproved);
      expect(farm.find(FarmModule.expenses, big.id)!['decisionNote'], 'OK, buy it');
      expect(counted(), before + 5000 + 30000);

      // A manager raising an approved amount sends it back for approval.
      await asManager();
      await farm.update(FarmModule.expenses, FarmRecord({...farm.find(FarmModule.expenses, big.id)!.toJson(), 'amount': '32000'}));
      expect(farm.find(FarmModule.expenses, big.id)!['approval'], FarmModule.approvalPending);
      // Re-saving it unchanged keeps it as it is.
      await asOwner();
      await farm.decide(FarmModule.expenses, big.id, approve: true);
      await asManager();
      await farm.update(FarmModule.expenses, farm.find(FarmModule.expenses, big.id)!);
      expect(farm.find(FarmModule.expenses, big.id)!['approval'], FarmModule.approvalApproved);
    });

    test('rejected spending is never counted; the owner\'s own spending needs no approval', () async {
      await asManager();
      final before = counted();
      final big = await farm.add(FarmModule.expenses, expense('25000'));
      await asOwner();
      await farm.decide(FarmModule.expenses, big.id, approve: false, note: 'Too expensive');
      expect(counted(), before);
      final mine = await farm.add(FarmModule.expenses, expense('90000'));
      expect(mine['approval'], FarmModule.approvalNotRequired);
      expect(counted(), before + 90000);
    });

    test('purchases above the limit also wait for the owner', () async {
      await asManager();
      final po = await farm.add(FarmModule.purchases, {'date': formatDate(today), 'supplier': 'X', 'item': 'Feed', 'qty': '1 t', 'amount': '50000', 'status': 'Ordered'});
      expect(po['approval'], FarmModule.approvalPending);
      await asOwner();
      await farm.decide(FarmModule.purchases, po.id, approve: true);
      expect(farm.find(FarmModule.purchases, po.id)!['approval'], FarmModule.approvalApproved);
    });
  });

  test('budget, payables and the decision queue on the owner dashboard', () async {
    await asOwner();
    final d = DashboardController(farm: farm, auth: auth, alerts: AlertsController(farm: farm, auth: auth, clock: () => now), clock: () => now);
    expect(d.monthlyBudget, 150000);
    expect(d.budgetUsed, closeTo(d.monthExpenses / 150000, 1e-9));
    final approvedSpend = farm.inRange(FarmModule.expenses, DateTime(2026, 10), today).where((e) => !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount'));
    expect(d.monthExpenses, approvedSpend);
    expect(d.monthPendingExpenses, greaterThan(0), reason: 'the demo has a pending chaff cutter');
    final owed = farm.list(FarmModule.expenses).where((e) => e['payment'] == 'Due' && !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount')) +
        farm.list(FarmModule.purchases).where((p) => p['status'] == 'Due' && !FarmModule.awaitsOrRefused(p['approval'])).fold(0.0, (s, p) => s + p.number('amount'));
    expect(d.payables, owed);
    expect(d.pendingDecisions, isNotEmpty);
    // Owner sees each waiting item as an alert.
    final alerts = AlertsController(farm: farm, auth: auth, clock: () => now).all;
    expect(alerts.where((a) => a.id.startsWith('decide:')), hasLength(farm.pendingDecisions.length));
  });

  group('requests and reports to the owner', () {
    test('a manager asks; only the owner approves or rejects', () async {
      await asManager();
      final r = await farm.add(FarmModule.requests, {'date': formatDate(today), 'type': 'Equipment', 'title': 'Water pump', 'estimatedAmount': '8000'});
      expect(r['status'], 'Pending');
      expect(r['requestedBy'], 'Rahim Uddin');
      await expectLater(farm.update(FarmModule.requests, FarmRecord({...r.toJson(), 'status': 'Approved'})), rule);
      await asOwner();
      await farm.decide(FarmModule.requests, r.id, approve: true, note: 'Buy the 1 hp one');
      final decided = farm.find(FarmModule.requests, r.id)!;
      expect(decided['status'], 'Approved');
      expect(decided['decidedBy'], 'Farhana Akter');
      // The manager is told.
      await asManager();
      final alerts = AlertsController(farm: farm, auth: auth, clock: () => now).all;
      expect(alerts.any((a) => a.id == 'request:${r.id}:Approved'), isTrue);
      // ...and sees it on the Approvals screen.
      expect(ApprovalsController(farm: farm, auth: auth).decided().any((i) => i.record.id == r.id), isTrue);
    });

    testWidgets('a daily report is filled in from the records; the owner reviews it', (tester) async {
      await tester.runAsync(asManager);
      late RecordFormController form;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        form = RecordFormController(module: FarmModule.managerReports, farm: farm, auth: auth, clock: () => now);
        return Scaffold(
            body: Form(key: form.formKey, child: Column(children: [for (final f in form.fields) TextFormField(controller: form.textControllers[f], validator: (v) => form.validate(f, v))])));
      })));
      final litres = farm.inRange(FarmModule.milkProduction, today, today).fold(0.0, (s, m) => s + m.number('litres'));
      expect(form.valueOf('summary'), contains('Milk: ${formatQty(double.parse(litres.toStringAsFixed(1)))} L'));
      expect(form.valueOf('summary'), contains('Sales:'), reason: 'this manager may record sales');
      expect(form.isReadOnly('status'), isTrue);
      final daily = form.valueOf('summary');
      form.setValue('period', 'Monthly');
      expect(form.valueOf('summary'), isNot(daily), reason: 'refreshed for the whole month');
      final monthLitres = farm.inRange(FarmModule.milkProduction, DateTime(2026, 10), DateTime(2026, 10, 31)).fold(0.0, (s, m) => s + m.number('litres'));
      expect(form.valueOf('summary'), contains('Milk: ${formatQty(double.parse(monthLitres.toStringAsFixed(1)))} L'));
      // A manager's own text is never overwritten.
      form.setValue('summary', 'My own words');
      form.setValue('period', 'Daily');
      expect(form.valueOf('summary'), 'My own words');
      late bool saved;
      await tester.runAsync(() async => saved = await form.save());
      expect(saved, isTrue, reason: form.error ?? '');
      final report = farm.list(FarmModule.managerReports).first;
      expect(report['submittedBy'], 'Rahim Uddin');
      expect(report['status'], 'Submitted');
      await tester.runAsync(() async {
        await asOwner();
        await farm.decide(FarmModule.managerReports, report.id, approve: true, note: 'Thanks');
      });
      expect(farm.find(FarmModule.managerReports, report.id)!['status'], 'Reviewed');
      expect(farm.find(FarmModule.managerReports, report.id)!['ownerComment'], 'Thanks');
    });
  });

  group('staff and daily tasks', () {
    test('the owner manages staff; a manager assigns and checks tasks', () async {
      await asManager();
      await expectLater(farm.add(FarmModule.staff, {'name': 'New Hand', 'job': 'Feeder', 'status': 'Active'}), rule, reason: 'only the owner hires');
      final form = RecordFormController(module: FarmModule.staff, existing: farm.list(FarmModule.staff).first, farm: farm, auth: auth);
      expect(form.isVisible('wage'), isFalse, reason: 'no finance right');
      form.dispose();

      final t = await farm.add(FarmModule.tasks, {'date': formatDate(today), 'task': 'Clean Shed B', 'area': 'Cleaning', 'assignedTo': 'Mohon Das', 'shift': 'Morning', 'status': 'Pending'});
      expect(t['checkedBy'], '');
      await expectLater(farm.update(FarmModule.tasks, FarmRecord({...t.toJson(), 'status': 'Not done'})), rule, reason: 'a reason is needed');
      final dash = DashboardController(farm: farm, auth: auth, alerts: AlertsController(farm: farm, auth: auth, clock: () => now), clock: () => now);
      final done = dash.staffTasksDone;
      await dash.markTaskDone(farm.find(FarmModule.tasks, t.id)!);
      expect(farm.find(FarmModule.tasks, t.id)!['checkedBy'], 'Rahim Uddin');
      expect(dash.staffTasksDone, done + 1);

      await asOwner();
      final hired = await farm.add(FarmModule.staff, {'name': 'New Hand', 'job': 'Feeder', 'status': 'Active'});
      // Renaming staff keeps their tasks; staff with tasks cannot be deleted.
      await farm.update(FarmModule.staff, FarmRecord({...farm.find(FarmModule.staff, 'SF-05')!.toJson(), 'name': 'Mohon Chandra Das'}));
      expect(farm.find(FarmModule.tasks, t.id)!['assignedTo'], 'Mohon Chandra Das');
      await expectLater(farm.remove(FarmModule.staff, 'SF-05'), rule);
      await farm.remove(FarmModule.staff, hired.id);
    });
  });

  group('owner reports', () {
    test('yearly summary adds up to the all-time P&L', () async {
      await asOwner();
      final r = ReportsController(farm: farm, auth: auth, clock: () => now)..applyPreset('All time');
      final t = r.annual();
      expect(t.rows.first.first, '2026');
      final all = FinanceEngine(farm, ReportFilter(from: r.earliestDate, to: today)).profitAndLoss;
      expect(t.rows.fold(0.0, (s, row) => s + double.parse(row[2])), closeTo(all.revenue, 1));
      expect(t.rows.fold(0.0, (s, row) => s + double.parse(row[4])), closeTo(all.operatingProfit, 1 * t.rows.length));
    });

    test('animal purchases & sales: result = net sale − purchase price − cost of keeping', () async {
      await asOwner();
      final r = ReportsController(farm: farm, auth: auth, clock: () => now)..applyPreset('All time');
      final t = r.animalTrade();
      final kalu = t.rows.firstWhere((row) => row.first == 'AN-1021 · Kalu');
      final net = double.parse(kalu[5]);
      expect(net, 143500, reason: '145 000 − 1 500 deductions');
      expect(double.parse(kalu[3]), 85000);
      expect(double.parse(kalu[7]), closeTo(net - 85000 - double.parse(kalu[6]), 1));
      // Managers without the finance right do not get these reports.
      await auth.login(role: UserRole.manager, username: 'manager03', password: 'manager03pass');
      expect(ReportsController(farm: farm, auth: auth, clock: () => now).kinds, isNot(contains(ReportKind.animalTrade)));
    });
  });
}
