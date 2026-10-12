import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/core/theme/app_theme.dart';
import 'package:technovate_farm_management/models/finance.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/views/account_views.dart';
import 'package:technovate_farm_management/views/approvals_view.dart';
import 'package:technovate_farm_management/views/batch_profile_view.dart';
import 'package:technovate_farm_management/views/cow_profile_view.dart';
import 'package:technovate_farm_management/views/dashboard_view.dart';
import 'package:technovate_farm_management/views/health_dashboard_view.dart';
import 'package:technovate_farm_management/views/illness_details_view.dart';
import 'package:technovate_farm_management/views/my_profile_view.dart';
import 'package:technovate_farm_management/views/notifications_view.dart';
import 'package:technovate_farm_management/views/record_form_view.dart';
import 'package:technovate_farm_management/views/records_view.dart';
import 'package:technovate_farm_management/views/reports_view.dart';
import 'package:technovate_farm_management/views/settings_view.dart';
import 'package:technovate_farm_management/views/users_view.dart';

/// QA: every screen, form, profile and report renders on a small phone
/// (360 × 640) for every role, without layout overflow or exceptions.
void main() {
  final farm = FarmController.instance;
  final auth = AuthController.instance;

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: page)));
    await tester.pumpAndSettle();
    // Scroll through the page so lazily built rows are laid out too.
    final scrollers = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (scrollers.evaluate().isNotEmpty) {
      for (var i = 0; i < 6; i++) {
        await tester.drag(scrollers.first, const Offset(0, -500), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
    }
  }

  setUp(() async {
    await mockStorage({});
    await farm.init();
    await auth.init();
  });

  for (final (role, username, password, who) in const [
    (UserRole.owner, 'owner', 'owner123', 'Farm Owner'),
    (UserRole.manager, 'manager', 'manager123', 'Farm Manager (sales, purchases, expenses)'),
    (UserRole.manager, 'manager02', 'manager02pass', 'Farm Manager (all rights incl. finance)'),
    (UserRole.manager, 'manager03', 'manager03pass', 'Farm Manager (operations only)'),
  ]) {
    testWidgets('$who: every screen and form fits a phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      expect(await auth.login(role: role, username: username, password: password), isNull);
      final access = auth.access;

      await show(tester, DashboardPage(onOpenSection: (_) {}));
      await show(tester, HealthDashboardPage(onOpenSection: (_) {}));
      await show(tester, NotificationsPage(onOpenSection: (_) {}));
      await show(tester, const SettingsPage());
      await show(tester, const MyProfilePage());
      await show(tester, const ApprovalsPage());
      await show(tester, const ChangePasswordPage());
      if (access.canManageSettings) {
        for (final p in const [UsersPage(), FarmProfilePage(), BackupPage(), ActivityLogPage(), CalculationSettingsPage(), HealthSettingsPage()]) {
          await show(tester, p);
        }
      }

      for (final m in FarmModule.all) {
        if (!access.canOpenModule(m.name)) continue;
        await show(tester, RecordsPage(module: m.name));
        await show(tester, RecordFormPage(module: m.name));
        for (final r in farm.list(m.name).take(3)) {
          await show(tester, RecordFormPage(module: m.name, existing: r));
        }
      }
      if (access.canOpenModule(FarmModule.animals)) {
        for (final a in farm.list(FarmModule.animals)) {
          await show(tester, CowProfilePage(animalId: a.id));
          await show(tester, AnimalHealthHistoryPage(animalId: a.id));
        }
      }
      if (access.canOpenModule(FarmModule.batches)) {
        for (final b in farm.list(FarmModule.batches)) {
          await show(tester, BatchProfilePage(batchId: b.id));
        }
      }
      if (access.canOpenModule(FarmModule.illness)) {
        for (final c in farm.list(FarmModule.illness)) {
          await show(tester, IllnessDetailsPage(illnessId: c.id));
        }
      }
      // Reports: every report this user may open (financial ones only with finance rights).
      final kinds = ReportsController().kinds;
      expect(kinds.any((k) => k.financial), access.canSeeFinance);
      expect(kinds, isNot(contains(ReportKind.batches)));
      {
        await show(tester, const ReportsPage());
        for (final k in kinds) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<ReportKind>));
          await tester.pumpAndSettle();
          final item = find.text(k.label).last;
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item, warnIfMissed: false);
          await tester.pumpAndSettle();
          for (var i = 0; i < 4; i++) {
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -600), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
        }
      }
    });
  }

  test('every report builds for every period and filter without errors', () async {
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    final c = ReportsController();
    final filters = <ReportFilter Function(ReportFilter)>[
      (f) => f,
      (f) => f.copyWith(species: 'Cattle'),
      (f) => f.copyWith(animal: 'AN-1001'),
      (f) => f.copyWith(batch: 'BT-01'),
      (f) => f.copyWith(location: c.locationOptions.first),
      (f) => f.copyWith(product: 'Milk'),
    ];
    for (final preset in ReportsController.presets) {
      c.applyPreset(preset);
      final base = c.filter;
      for (final f in filters) {
        c.setFilter(f(base));
        for (final k in ReportKind.values) {
          c.setKind(k);
          final t = c.build();
          final where = '${k.label} · $preset · ${c.filter.description}';
          expect(t.columns, isNotEmpty, reason: where);
          for (final row in t.rows) {
            expect(row.length, t.columns.length, reason: '$where row width');
            for (final cell in row) {
              expect(cell.contains('NaN') || cell.contains('Infinity'), isFalse, reason: '$where: $row');
            }
          }
          for (final (label, value) in t.summary) {
            expect(value.contains('NaN') || value.contains('Infinity'), isFalse, reason: '$where: $label=$value');
          }
          expect(t.toCsv().split('\n'), hasLength(t.rows.length + 1));
        }
      }
    }
  });
}
