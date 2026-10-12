import 'package:flutter/material.dart';

import '../controllers/dashboard_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'illness_details_view.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dashboard_widgets.dart';

/// Farm Manager: today's operations — milking, feeding, animal health,
/// doses and vaccinations due, low stock, pending tasks and recent activity.
/// Money appears only if the owner has allowed it.
class ManagerDashboard extends StatelessWidget {
  const ManagerDashboard({super.key, required this.c, required this.onOpenSection});

  final DashboardController c;
  final ValueChanged<String> onOpenSection;

  void _form(BuildContext context, String module, {FarmRecord? existing}) => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: module, existing: existing)));

  @override
  Widget build(BuildContext context) {
    final notMilked = c.cowsNotMilkedToday;
    final tasks = c.tasksToday;
    final staffTasks = c.staffTasksToday;
    final urgent = c.urgentIllness;
    final open = c.openIllness;
    VoidCallback section(String s) => () => onOpenSection(s);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
      Text(c.greeting, style: const TextStyle(color: AppColors.muted)),
      const Text('Today on the farm', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
      Text(formatDate(c.today), style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      DashboardHero(
        caption: c.profile.name,
        headline: c.headline,
        detail: '${c.animalCount} animals on the farm',
        stats: [
          ('Milk today', '${c.milkToday.toStringAsFixed(1)} L'),
          ('Feed today', '${c.feedTodayKg.toStringAsFixed(0)} kg'),
          ('Tasks due', '${tasks.length}'),
          ('Staff tasks done', '${c.staffTasksDone}/${staffTasks.length}'),
        ],
      ),
      DashSection('Staff tasks today',
          subtitle: staffTasks.isEmpty ? 'No tasks assigned yet' : '${c.staffTasksDone} of ${staffTasks.length} done', action: 'Daily Tasks', onAction: section(FarmModule.tasks)),
      for (final t in staffTasks)
        DashRow(
          icon: '${t['status']}' == 'Done' ? Icons.check_circle : Icons.radio_button_unchecked,
          title: '${t['task']}',
          subtitle: '${t['assignedTo']} · ${t['shift']} · ${t['status']}${'${t['checkedBy'] ?? ''}'.isEmpty ? '' : ' (checked by ${t['checkedBy']})'}',
          tone: switch ('${t['status']}') { 'Done' => StatTone.good, 'Not done' => StatTone.bad, _ => StatTone.neutral },
          onTap: '${t['status']}' == 'Pending' && c.canEdit(FarmModule.tasks) ? () => c.markTaskDone(t) : () => _form(context, FarmModule.tasks, existing: t),
        ),
      if (c.canEdit(FarmModule.tasks))
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _form(context, FarmModule.tasks), icon: const Icon(Icons.add), label: const Text('Assign a task'))),
      if (staffTasks.any((t) => '${t['status']}' == 'Pending')) const Text('Tap a pending task to mark it done.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      DashSection('Report to the owner',
          subtitle: c.dailyReportSent ? 'Today’s report has been sent' : 'Today’s report has not been sent yet', action: 'Reports sent', onAction: section(FarmModule.managerReports)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (c.canEdit(FarmModule.managerReports))
          DashAction(icon: Icons.summarize_outlined, label: c.dailyReportSent ? 'Send another report' : 'Send today’s report', onTap: () => _form(context, FarmModule.managerReports)),
        if (c.canEdit(FarmModule.requests)) DashAction(icon: Icons.approval_outlined, label: 'Ask the owner (feed, equipment, purchase…)', onTap: () => _form(context, FarmModule.requests)),
      ]),
      for (final r in c.myRequests.take(3))
        DashRow(
          icon: Icons.approval,
          title: '${r['title']}',
          subtitle: '${r['status']}${'${r['decisionNote'] ?? ''}'.isEmpty ? '' : ' · ${r['decisionNote']}'}',
          tone: switch ('${r['status']}') { 'Approved' => StatTone.good, 'Rejected' => StatTone.bad, _ => StatTone.warning },
          onTap: () => _form(context, FarmModule.requests, existing: r),
        ),
      DashSection('Milking',
          subtitle: notMilked.isEmpty ? 'Every lactating cow has a milk record today' : '${notMilked.length} lactating cow(s) not recorded yet today',
          action: 'Milk records',
          onAction: section(FarmModule.milkProduction)),
      if (notMilked.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final cow in notMilked) Chip(avatar: const Icon(Icons.water_drop_outlined, size: 16, color: AppColors.orange), label: Text('${cow['name']}')),
        ]),
      if (c.canEdit(FarmModule.milkProduction))
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _form(context, FarmModule.milkProduction), icon: const Icon(Icons.add), label: const Text('Record milk'))),
      DashSection('Feeding', subtitle: '${c.feedEntriesToday} feed entries today · ${c.feedTodayKg.toStringAsFixed(0)} kg', action: 'Feed records', onAction: section(FarmModule.feedRecords)),
      if (c.canEdit(FarmModule.feedRecords))
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _form(context, FarmModule.feedRecords), icon: const Icon(Icons.add), label: const Text('Feed entry'))),
      DashSection('Animal health', subtitle: '${open.length} open illness case(s)${urgent.isEmpty ? '' : ' · ${urgent.length} urgent'}', action: 'Animal Health', onAction: section('Animal Health')),
      for (final i in urgent)
        DashRow(
          icon: Icons.emergency,
          title: 'URGENT: ${FarmRecord.displayName(i['animal'])} — contact a veterinarian',
          subtitle: '${i['severity']} · ${i['symptoms']}',
          tone: StatTone.bad,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IllnessDetailsPage(illnessId: i.id))),
        ),
      for (final i in open.where((i) => !urgent.contains(i)).take(4))
        DashRow(
          icon: Icons.sick_outlined,
          title: '${FarmRecord.displayName(i['animal'])}: ${i['symptoms']}',
          subtitle: '${i['stage']}',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IllnessDetailsPage(illnessId: i.id))),
        ),
      if (c.canEdit(FarmModule.illness))
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _form(context, FarmModule.illness), icon: const Icon(Icons.add), label: const Text('Report illness'))),
      const DashSection('Treatments & vaccinations due', subtitle: 'Doses, follow-ups and vaccinations due today or overdue'),
      if (tasks.isEmpty)
        const EmptyHint('Nothing due today.')
      else
        for (final t in tasks)
          DashRow(
            icon: t.overdue ? Icons.alarm : Icons.today,
            title: t.title,
            subtitle: '${t.overdue ? 'OVERDUE · ' : ''}${t.detail}',
            tone: t.overdue ? StatTone.warning : StatTone.neutral,
            onTap: () {
              final r = t.recordId == null ? null : c.farm.find(t.module, t.recordId!);
              if (r != null) _form(context, t.module, existing: r);
            },
          ),
      DashSection('Feed & stock', action: 'Stock transactions', onAction: section(FarmModule.inventoryTx)),
      if (c.lowStockItems.isEmpty)
        const DashRow(icon: Icons.inventory_2_outlined, title: 'All stock above reorder level', tone: StatTone.good)
      else
        for (final i in c.lowStockItems)
          DashRow(
              icon: Icons.inventory_2_outlined,
              title: '${i['name']}: ${i['qty']} ${i['unit']} left',
              subtitle: 'Reorder at ${i['reorder']}',
              tone: StatTone.warning,
              onTap: section(FarmModule.inventory)),
      if (c.canSeeFinance) ...[
        const DashSection('This month’s money', subtitle: 'Shown because the owner allowed you to see financial summaries'),
        StatGrid(children: [
          StatTile(label: 'Sales (net)', value: c.money(c.monthSales), icon: Icons.point_of_sale),
          StatTile(label: 'Operating result', value: c.money(c.monthProfit), icon: Icons.trending_up, tone: c.monthProfit >= 0 ? StatTone.good : StatTone.bad),
        ]),
      ],
      DashSection('Pending tasks', action: c.alertCount > 0 ? 'View all (${c.alertCount})' : null, onAction: section('Notifications')),
      if (c.attentionItems.isEmpty)
        const EmptyHint('No pending reminders.')
      else
        for (final a in c.attentionItems) alertRow(a, onTap: a.module == null ? null : section(a.module!)),
      const DashSection('Quick entry'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (icon, label, module) in const [
          (Icons.water_drop_outlined, 'Milk', FarmModule.milkProduction),
          (Icons.grass_outlined, 'Feed', FarmModule.feedRecords),
          (Icons.add, 'Register animal', FarmModule.animals),
          (Icons.sick_outlined, 'Illness', FarmModule.illness),
          (Icons.medical_services_outlined, 'Vaccination', FarmModule.health),
          (Icons.biotech_outlined, 'Breeding', FarmModule.breeding),
          (Icons.monitor_weight_outlined, 'Weight', FarmModule.weights),
          (Icons.receipt_long_outlined, 'Stock movement', FarmModule.inventoryTx),
          (Icons.heart_broken_outlined, 'Mortality', FarmModule.mortality),
          (Icons.point_of_sale_outlined, 'Sale', FarmModule.sales),
          (Icons.shopping_bag_outlined, 'Purchase', FarmModule.purchases),
          (Icons.account_balance_wallet_outlined, 'Expense', FarmModule.expenses),
        ])
          if (c.canEdit(module)) DashAction(icon: icon, label: label, onTap: () => _form(context, module)),
      ]),
      const DashSection('Recent activity'),
      if (c.recentActivity().isEmpty)
        const EmptyHint('Your entries will appear here.')
      else
        for (final a in c.recentActivity()) activityRow(a),
    ]);
  }
}
