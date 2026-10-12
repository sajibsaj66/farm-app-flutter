import 'package:flutter/material.dart';

import '../controllers/dashboard_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/app_section.dart';
import '../models/farm_module.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dashboard_widgets.dart';

/// Farm Owner: how the business is doing — herd, milk, feed and vet costs,
/// purchases, sales, expenses, profit, stock, six-month trends, alerts and
/// what the managers recorded.
class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({super.key, required this.c, required this.onOpenSection});

  final DashboardController c;
  final ValueChanged<String> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final profile = c.profile;
    final status = c.animalsByStatus;
    final profit = c.monthProfit;
    final trends = c.trends;
    final decisions = c.pendingDecisions;
    final tasks = c.staffTasksToday;
    final maxMilk = trends.fold(0.0, (m, t) => t.milkLitres > m ? t.milkLitres : m);
    VoidCallback open(String section) => () => onOpenSection(section);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
      Text(c.greeting, style: const TextStyle(color: AppColors.muted)),
      const Text('Owner dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const Text('Business performance from the records saved on this device.', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      DashboardHero(
        caption: profile.location.isEmpty ? profile.name : '${profile.name} · ${profile.location}',
        headline: c.headline,
        detail: '${c.animalCount} animals on the farm · ${c.inventoryCount} stock items',
        stats: [
          ('Operating ${profit >= 0 ? 'profit' : 'loss'} this month', c.money(profit)),
          ('Revenue this month', c.money(c.monthRevenue)),
          ('Milk this month', '${c.milkThisMonth.toStringAsFixed(0)} L'),
        ],
      ),
      DashSection('Waiting for your decision',
          subtitle: '${decisions.length} item(s): large expenses and purchases, requests and managers’ reports', action: 'Approvals', onAction: open(AppSection.approvals)),
      if (decisions.isEmpty)
        const DashRow(icon: Icons.fact_check_outlined, title: 'Nothing is waiting for you', tone: StatTone.good)
      else
        for (final (m, r) in decisions.take(4))
          DashRow(
            icon: FarmModule.recordIconFor(m),
            title: switch (m) {
              FarmModule.expenses => 'Expense ${c.money(r.number('amount'))}: ${r['description']}',
              FarmModule.purchases => 'Purchase ${c.money(r.number('amount'))}: ${r['item']}',
              FarmModule.requests => 'Request: ${r['title']}',
              _ => '${r['period']} report from ${r['submittedBy']}',
            },
            subtitle: '${r['date']}',
            tone: StatTone.warning,
            onTap: open(AppSection.approvals),
          ),
      DashSection('Herd', subtitle: '${c.registeredAnimals} animals registered', action: 'Animals', onAction: open(FarmModule.animals)),
      StatGrid(children: [
        StatTile(label: 'On the farm', value: '${status['On farm']}', icon: Icons.pets, tone: StatTone.good, sub: '${c.pregnantCount} confirmed pregnant', onTap: open(FarmModule.animals)),
        StatTile(label: 'Sold', value: '${status['Sold']}', icon: Icons.sell_outlined, onTap: open(FarmModule.sales)),
        StatTile(label: 'Transferred', value: '${status['Transferred']}', icon: Icons.local_shipping_outlined, onTap: open(FarmModule.animals)),
        StatTile(
            label: 'Deceased',
            value: '${status['Deceased']}',
            icon: Icons.heart_broken_outlined,
            tone: (status['Deceased'] ?? 0) > 0 ? StatTone.warning : StatTone.neutral,
            onTap: open(FarmModule.mortality)),
      ]),
      DashSection('Milk production', action: 'Milk records', onAction: open(FarmModule.milkProduction)),
      StatGrid(children: [
        StatTile(label: 'Today', value: '${c.milkToday.toStringAsFixed(1)} L', icon: Icons.water_drop, onTap: open(FarmModule.milkProduction)),
        StatTile(label: 'Last 7 days', value: '${c.milkThisWeek.toStringAsFixed(0)} L', icon: Icons.date_range, onTap: open(FarmModule.milkProduction)),
        StatTile(
          label: 'This month',
          value: '${c.milkThisMonth.toStringAsFixed(0)} L',
          icon: Icons.calendar_month,
          sub: c.milkWithheldThisMonth > 0 ? '${c.milkWithheldThisMonth.toStringAsFixed(0)} L withheld (not for sale)' : null,
          tone: c.milkWithheldThisMonth > 0 ? StatTone.warning : StatTone.neutral,
          onTap: open(FarmModule.milkProduction),
        ),
      ]),
      const DashSection('This month’s money', subtitle: 'Operating profit is estimated from saved sales, feed, treatment, expense and animal records'),
      StatGrid(children: [
        StatTile(label: 'Sales (net)', value: c.money(c.monthSales), icon: Icons.point_of_sale, sub: '${c.monthSalesCount} sales', onTap: open(FarmModule.sales)),
        StatTile(label: 'Total costs', value: c.money(c.monthCosts), icon: Icons.receipt_long, onTap: open('Reports')),
        StatTile(
            label: 'Operating ${profit >= 0 ? 'profit' : 'loss'}',
            value: c.money(profit),
            icon: profit >= 0 ? Icons.trending_up : Icons.trending_down,
            tone: profit >= 0 ? StatTone.good : StatTone.bad,
            onTap: open('Reports')),
        StatTile(label: 'Feed consumed', value: c.money(c.feedMonthCost), icon: Icons.grass, sub: '${c.feedMonthKg.toStringAsFixed(0)} kg', onTap: open(FarmModule.feedRecords)),
        StatTile(label: 'Vet & treatment', value: c.money(c.monthVetCosts), icon: Icons.medical_services_outlined, onTap: open(FarmModule.treatments)),
        StatTile(
            label: 'Expenses',
            value: c.money(c.monthExpenses),
            icon: Icons.account_balance_wallet_outlined,
            sub: c.monthPendingExpenses > 0 ? '${c.money(c.monthPendingExpenses)} awaiting approval' : null,
            onTap: open(FarmModule.expenses)),
        if (c.budgetUsed != null)
          StatTile(
              label: 'Budget used',
              value: '${(c.budgetUsed! * 100).toStringAsFixed(0)}%',
              icon: Icons.savings_outlined,
              sub: '${c.money(c.monthExpenses)} of ${c.money(c.monthlyBudget)}',
              tone: c.budgetUsed! > 1 ? StatTone.bad : (c.budgetUsed! >= 0.9 ? StatTone.warning : StatTone.good),
              onTap: open(FarmModule.expenses)),
        StatTile(
            label: 'We owe',
            value: c.money(c.payables),
            icon: Icons.request_quote_outlined,
            sub: 'Unpaid expenses and purchases',
            tone: c.payables > 0 ? StatTone.warning : StatTone.good,
            onTap: open(FarmModule.expenses)),
        StatTile(
            label: 'Purchases',
            value: c.money(c.monthPurchases),
            icon: Icons.shopping_bag_outlined,
            sub: c.purchasesDue > 0 ? '${c.money(c.purchasesDue)} due to suppliers' : 'Nothing due',
            tone: c.purchasesDue > 0 ? StatTone.warning : StatTone.neutral,
            onTap: open(FarmModule.purchases)),
        StatTile(label: 'Customers owe', value: c.money(c.receivables), icon: Icons.payments_outlined, tone: c.receivables > 0 ? StatTone.warning : StatTone.good, onTap: open(FarmModule.collections)),
        StatTile(
            label: 'Net cash flow',
            value: c.money(c.monthCashFlow),
            icon: Icons.swap_vert,
            sub: 'Money in − money out (not profit)',
            tone: c.monthCashFlow >= 0 ? StatTone.good : StatTone.bad,
            onTap: open('Reports')),
      ]),
      DashSection('Inventory', subtitle: 'Stock value at current cost: ${c.money(c.stockValue)}', action: 'Stock', onAction: open(FarmModule.inventory)),
      if (c.lowStockItems.isEmpty)
        const DashRow(icon: Icons.inventory_2_outlined, title: 'All stock above reorder level', tone: StatTone.good)
      else
        for (final i in c.lowStockItems.take(4))
          DashRow(
              icon: Icons.inventory_2_outlined,
              title: '${i['name']}: ${i['qty']} ${i['unit']} left',
              subtitle: 'Reorder at ${i['reorder']}',
              tone: StatTone.warning,
              onTap: open(FarmModule.inventory)),
      DashSection('Staff tasks today', subtitle: tasks.isEmpty ? 'No tasks assigned today' : '${c.staffTasksDone} of ${tasks.length} done', action: 'Daily Tasks', onAction: open(FarmModule.tasks)),
      for (final t in tasks.where((t) => '${t['status']}' != 'Done').take(4))
        DashRow(
          icon: Icons.checklist,
          title: '${t['task']}',
          subtitle: '${t['assignedTo']} · ${t['shift']} · ${t['status']}',
          tone: '${t['status']}' == 'Not done' ? StatTone.bad : StatTone.warning,
          onTap: open(FarmModule.tasks),
        ),
      const DashSection('Six-month trend', subtitle: 'Milk recorded, revenue, costs and operating result per month'),
      Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.inputBorder)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final t in trends) _TrendRow(t: t, maxMilk: maxMilk, money: c.money),
          ]),
        ),
      ),
      DashSection('Needs attention', action: c.alertCount > 0 ? 'View all (${c.alertCount})' : null, onAction: open('Notifications')),
      if (c.attentionItems.isEmpty)
        const EmptyHint('Nothing needs attention right now.')
      else
        for (final a in c.attentionItems) alertRow(a, onTap: a.module == null ? null : open(a.module!)),
      const DashSection('Managers’ recent activity', subtitle: 'What your farm managers recorded'),
      if (c.managerActivity().isEmpty)
        const EmptyHint('No manager activity recorded yet.')
      else
        for (final a in c.managerActivity()) activityRow(a),
      const DashSection('Quick actions'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        DashAction(icon: Icons.query_stats, label: 'Financial reports', onTap: open('Reports')),
        for (final (icon, label, module) in const [
          (Icons.add, 'Add animal', FarmModule.animals),
          (Icons.point_of_sale_outlined, 'New sale', FarmModule.sales),
          (Icons.shopping_bag_outlined, 'New purchase', FarmModule.purchases),
          (Icons.account_balance_wallet_outlined, 'Add expense', FarmModule.expenses),
        ])
          if (c.canEdit(module)) DashAction(icon: icon, label: label, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: module)))),
      ]),
    ]);
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.t, required this.maxMilk, required this.money});

  final MonthTrend t;
  final double maxMilk;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 64, child: Text(t.month, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: maxMilk <= 0 ? 0 : t.milkLitres / maxMilk, minHeight: 8, backgroundColor: AppColors.brandSoft, color: AppColors.navyLight),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 64, child: Text('${t.milkLitres.toStringAsFixed(0)} L', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 64, top: 2),
            child: Text(
              'Revenue ${money(t.revenue)} · Costs ${money(t.costs)} · ${t.profit >= 0 ? 'Profit' : 'Loss'} ${money(t.profit)}',
              style: TextStyle(fontSize: 11, color: t.profit >= 0 ? AppColors.positive : AppColors.danger),
            ),
          ),
        ]),
      );
}
