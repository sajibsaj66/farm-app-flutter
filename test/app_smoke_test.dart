import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/app.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/herd_analytics.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/app_section.dart';

Finder _rail(String label) => find.descendant(of: find.byType(NavigationRail), matching: find.text(label));

Future<void> _signIn(WidgetTester tester, String roleLabel) async {
  await tester.tap(find.widgetWithText(ChoiceChip, roleLabel));
  await tester.pumpAndSettle();
  await _tapText(tester, 'Use demo $roleLabel account');
  await _tapText(tester, 'Sign in as $roleLabel');
}

Future<void> _pick(WidgetTester tester, String field, String optionContains) async {
  final dropdown = find.widgetWithText(DropdownButtonFormField<String>, field);
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(optionContains).last);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String label) async {
  await tester.ensureVisible(_rail(label));
  await tester.tap(_rail(label));
  await tester.pumpAndSettle();
}

/// The innermost vertical page scroller — not the one inside a multi-line text field.
Finder get _pageScroller =>
    find.byElementPredicate((e) => e.widget is Scrollable && (e.widget as Scrollable).axisDirection == AxisDirection.down && e.findAncestorWidgetOfExactType<EditableText>() == null).last;

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200, scrollable: _pageScroller);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner: login, every section, alerts, users, profile, forms, sign out', (tester) async {
    await mockStorage({});
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TechnovateFarmApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    // The owner's sign-in is filled in; an empty username is still refused.
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Username')).controller!.text, 'owner');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), '');
    await _tapText(tester, 'Sign in as Farm Owner');
    expect(find.text('Please enter your username'), findsOneWidget);

    await _signIn(tester, 'Farm Owner');
    expect(find.text('Owner dashboard'), findsOneWidget);
    expect(find.textContaining('need your attention'), findsOneWidget);
    expect(find.text('Herd'), findsOneWidget);
    expect(find.text('Deceased'), findsOneWidget);
    expect(find.textContaining('this month'), findsWidgets);
    expect(find.text('Birds & fish'), findsNothing, reason: 'livestock only');

    // Every section opens without layout errors.
    for (final s in AppSection.all) {
      await _open(tester, s.label);
    }

    // Reports: profit & loss for the owner.
    await _open(tester, 'Reports');
    expect(find.text('Farm profit & loss'), findsWidgets);
    expect(find.text('Copy CSV'), findsOneWidget);
    expect(find.text('Net cash flow (not profit)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<ReportKind>));
    await tester.pumpAndSettle();
    expect(find.text('Batch cost & profit'), findsNothing, reason: 'no poultry/fish batch report');
    await tester.tap(find.text('Animal cost & profit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'AN-1001 · Shona');
    expect(find.text('Milk produced'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Daily feed entry for a fattening bull takes the feed out of stock.
    await _open(tester, 'Feed Records');
    final fattening = FarmController.instance.feedItem('Fattening Concentrate')!.number('qty');
    await tester.tap(find.text('Add new'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Batch (optional)'), findsNothing, reason: 'no batch field');
    await _pick(tester, 'Animal (optional)', 'AN-1009 · Toofan');
    await _pick(tester, 'Feed item', 'Fattening Concentrate ·');
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity consumed'), '5');
    await _pick(tester, 'Shift', 'Morning');
    await _tapText(tester, 'Save record');
    expect(FarmController.instance.feedItem('Fattening Concentrate')!.number('qty'), fattening - 5);

    // Animal health: dashboard, report an emergency illness, open the case.
    await _open(tester, 'Animal Health');
    expect(find.text('Under treatment'), findsWidgets);
    expect(find.text('Today & overdue'), findsOneWidget);
    final casesBefore = FarmController.instance.count(FarmModule.illness);
    await tester.tap(find.text('Report illness').first);
    await tester.pumpAndSettle();
    await _pick(tester, 'Animal', 'AN-1002 · Rani');
    await tester.enterText(find.widgetWithText(TextFormField, 'Main symptoms'), 'Laboured breathing, not eating');
    await tester.ensureVisible(find.text('Severe breathing difficulty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Severe breathing difficulty'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('EMERGENCY: contact a veterinarian immediately'), 200, scrollable: _pageScroller);
    expect(find.textContaining('EMERGENCY: contact a veterinarian immediately'), findsOneWidget);
    expect(find.textContaining('Vet:').evaluate().isNotEmpty || find.textContaining('No valid veterinarian phone').evaluate().isNotEmpty, isTrue,
        reason: 'call or contact option shown for emergencies');
    await _pick(tester, 'Severity', 'Emergency');
    await _tapText(tester, 'Save record');
    expect(FarmController.instance.count(FarmModule.illness), casesBefore + 1);
    expect(find.text('Urgent — contact a veterinarian'), findsOneWidget);
    await tester.tap(find.textContaining('Rani · Emergency').first);
    await tester.pumpAndSettle();
    expect(find.text('Reported symptoms'), findsOneWidget);
    expect(find.text('Not evaluated by a veterinarian yet'), findsOneWidget);
    await _tapText(tester, 'Record recovery or outcome');
    expect(find.text('Recovery & case outcome'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Notifications: mark one read, badge count drops.
    await _open(tester, 'Notifications');
    final before = AuthController.instance.currentUser!.username;
    expect(before, 'owner');
    final unread = AlertsController.instance.activeCount;
    expect(unread, greaterThan(0));
    await tester.tap(find.byTooltip('Mark read').first);
    await tester.pumpAndSettle();
    expect(AlertsController.instance.activeCount, unread - 1);
    expect(find.byTooltip('${unread - 1} unread notifications'), findsOneWidget);

    // Add a milk record through the typed form (date defaults to today, dropdowns).
    await _open(tester, 'Milk Production');
    final milkBefore = FarmController.instance.count(FarmModule.milkProduction);
    await tester.tap(find.text('Add new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(find.text('Please choose animal'), findsOneWidget);
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Animal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AN-1001 · Shona').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evening').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Litres'), 'ten');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Quality'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accepted').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number, e.g. 12.5'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Litres'), '9.5');
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(FarmController.instance.count(FarmModule.milkProduction), milkBefore + 1);

    // Cow profile: milk, feed, margin, reproduction and the semen check.
    await _open(tester, 'Animals');
    await _tapText(tester, 'Shona');
    expect(find.text('Milk produced'), findsOneWidget);
    expect(find.text('Feed consumed'), findsOneWidget);
    expect(find.text('Feed per litre'), findsOneWidget);
    expect(find.text('Operating profit'), findsOneWidget);
    expect(find.textContaining('pregnancy check due'), findsWidgets);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Check semen');
    expect(find.text('Semen suitability for Shona'), findsOneWidget);
    expect(find.text('Verify before use'), findsWidgets, reason: 'Shona’s dam is unknown, so no semen is shown as conflict-free');
    expect(find.text(SemenSuitability.disclaimer), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Timeline');
    expect(find.textContaining('Calf Lali'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Settings → Users & roles → add a user.
    await _open(tester, 'Settings');
    await _tapText(tester, 'Users & roles');
    expect(find.text('Farhana Akter (you)'), findsOneWidget);
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Test Helper');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'helper1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'helper123');
    await _tapText(tester, 'Create user');
    expect(AuthController.instance.users.any((u) => u.username == 'helper1' && u.name == 'Test Helper'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Farm profile edit shows up in the app bar.
    await _tapText(tester, 'Farm profile');
    await tester.enterText(find.widgetWithText(TextFormField, 'Farm name'), 'Green Acres Dairy');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Green Acres Dairy'), findsWidgets);

    // Activity log shows who did it.
    await _tapText(tester, 'Activity log');
    expect(find.textContaining('Farhana Akter'), findsWidgets);
    expect(find.text('Added user Test Helper (Farm Manager, operations only)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Backup page opens.
    await _tapText(tester, 'Backup & restore');
    expect(find.text('Copy backup to clipboard'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Sign out (with confirmation) and sign in as the new manager (no extra rights).
    await _tapText(tester, 'Sign out');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Farm Manager'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'helper1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'helper123');
    await tester.tap(find.text('Sign in as Farm Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Today on the farm'), findsOneWidget, reason: 'manager dashboard');
    expect(_rail('Sales'), findsNothing);
    expect(_rail('Expenses'), findsNothing);
    await _open(tester, 'Reports');
    expect(find.text('Farm profit & loss'), findsNothing, reason: 'no financial reports without that right');
    await _open(tester, 'Settings');
    expect(find.text('Users & roles'), findsNothing);
    expect(find.text('Reset demo data'), findsNothing);
  });

  testWidgets('owner screens fit a phone screen', (tester) async {
    await mockStorage({});
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TechnovateFarmApp());
    await tester.pumpAndSettle();
    if (find.text('Welcome back').evaluate().isNotEmpty) await _signIn(tester, 'Farm Owner');
    expect(find.byType(NavigationBar), findsOneWidget);

    // Visit every section through the "More" sheet.
    for (final s in AppSection.all) {
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.widgetWithText(ListTile, s.label), 80, scrollable: _pageScroller);
      await tester.ensureVisible(find.widgetWithText(ListTile, s.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, s.label));
      await tester.pumpAndSettle();
    }

    // A cow profile fits a phone too.
    await tester.tap(find.text('Animals').last);
    await tester.pumpAndSettle();
    await _tapText(tester, 'Moti');
    expect(find.text('Milk produced'), findsOneWidget);
    await _tapText(tester, 'Record calving');
    expect(find.text('Record calving · Moti'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Family');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(ListTile, 'Settings'), 80, scrollable: _pageScroller);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    for (final page in ['Change password', 'Users & roles', 'Farm profile', 'Activity log', 'Backup & restore']) {
      await _tapText(tester, page);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
