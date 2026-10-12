import 'package:flutter/material.dart';

import '../controllers/cow_profile_controller.dart';
import '../controllers/farm_controller.dart';
import '../controllers/finance_engine.dart';
import '../controllers/health_analytics.dart';
import '../controllers/health_rules.dart';
import '../controllers/herd_analytics.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'health_dashboard_view.dart';
import 'illness_details_view.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/semen_check_card.dart';

/// Everything about one animal: milk produced, feed eaten, cost and margin,
/// reproduction, health, growth, family and a full timeline.
class CowProfilePage extends StatefulWidget {
  const CowProfilePage({super.key, required this.animalId});

  final String animalId;

  @override
  State<CowProfilePage> createState() => _CowProfilePageState();
}

class _CowProfilePageState extends State<CowProfilePage> {
  late final controller = CowProfileController(widget.animalId);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _openForm(String module, {FarmRecord? existing, Map<String, String> values = const {}}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: module, existing: existing, initialValues: values)));

  void _openProfile(FarmRecord animal) => Navigator.push(context, MaterialPageRoute(builder: (_) => CowProfilePage(animalId: animal.id)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final animal = controller.animal;
          final a = controller.analytics;
          if (animal == null || a == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('This animal is no longer in the register.')));
          }
          final ref = animal.reference;
          final stats = a.period(controller.periodDays);
          final actual = controller.canSeeFinance ? a.actualProfit(controller.periodDays) : null;
          final currency = controller.farm.profile.currency;
          String money(double v) => '$currency${v.toStringAsFixed(0)}';
          return Scaffold(
            appBar: AppBar(
              title: Text('${animal['name']}'),
              actions: [
                if (controller.canOpen(FarmModule.animals)) IconButton(tooltip: 'Edit animal', icon: const Icon(Icons.edit_outlined), onPressed: () => _openForm(FarmModule.animals, existing: animal)),
              ],
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              _Header(animal: animal, a: a),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in CowProfileController.periods) ChoiceChip(label: Text(controller.periodLabel(p)), selected: controller.periodDays == p, onSelected: (_) => controller.setPeriod(p)),
              ]),
              const SizedBox(height: 12),
              _StatsGrid(children: [
                _Stat(
                    icon: Icons.water_drop,
                    label: 'Milk produced',
                    value: '${stats.milk.toStringAsFixed(1)} L',
                    sub: '${stats.avgMilkPerDay.toStringAsFixed(1)} L/day · ${stats.daysWithMilk} days recorded'),
                _Stat(
                    icon: Icons.grass,
                    label: 'Feed consumed',
                    value: '${stats.feedKg.toStringAsFixed(1)} kg',
                    sub: controller.canSeeFinance ? '${money(stats.feedCost)}${stats.feedCostIncomplete ? '+' : ''} feed cost' : 'In this period'),
                _Stat(
                  icon: Icons.compare_arrows,
                  label: 'Feed per litre',
                  value: stats.feedPerLitre == null ? '—' : '${stats.feedPerLitre!.toStringAsFixed(2)} kg',
                  sub:
                      stats.feedCostPerLitre == null ? 'No milk in this period' : (controller.canSeeFinance ? '${money(stats.feedCostPerLitre!)} feed cost per litre' : 'kg of feed per litre of milk'),
                ),
                if (actual != null)
                  _Stat(
                    icon: Icons.account_balance_wallet,
                    label: 'Operating profit',
                    value: money(actual.profit + actual.cost(FinanceEngine.catDisposal)),
                    sub: 'Sales ${money(actual.revenue)} − costs ${money(actual.totalCost - actual.cost(FinanceEngine.catDisposal))} (incl. shared)',
                    valueColor: actual.profit + actual.cost(FinanceEngine.catDisposal) >= 0 ? AppColors.brand : const Color(0xFFB3261E),
                  )
                else
                  _Stat(
                      icon: Icons.monitor_weight,
                      label: 'Weight',
                      value: a.latestWeight == null ? '—' : '${formatQty(a.latestWeight!)} kg',
                      sub: a.averageDailyGain == null ? 'No weight history' : '${(a.averageDailyGain! * 1000).toStringAsFixed(0)} g/day gain'),
              ]),
              if (stats.withheldMilk > 0) _Note(Icons.block_outlined, '${stats.withheldMilk.toStringAsFixed(1)} L withheld (withdrawal period) — not counted as income.'),
              if (stats.feedCostIncomplete) const _Note(Icons.info_outline, 'Some feed items have no cost per unit in Inventory, so the feed cost is a minimum.'),
              if (actual != null)
                _Note(Icons.calculate_outlined,
                    'Operating profit uses actual sales attributed to this animal (bulk milk sales are shared by each cow’s saleable milk) and excludes its purchase price. Estimated milk value at ${money(stats.milkPrice)}/L would be ${money(stats.milkIncome)} — an estimate, not income.'),
              const SizedBox(height: 14),
              const SectionTitle('Last 14 days'),
              const SizedBox(height: 8),
              _DailyChart(points: a.daily(14)),
              const SizedBox(height: 18),
              const SectionTitle('Record for this animal'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (controller.canOpen(FarmModule.milkProduction) && a.isFemale)
                  QuickAction(icon: Icons.water_drop_outlined, label: 'Milk', onTap: () => _openForm(FarmModule.milkProduction, values: {'animal': ref})),
                if (controller.canOpen(FarmModule.feedRecords)) QuickAction(icon: Icons.grass_outlined, label: 'Feed', onTap: () => _openForm(FarmModule.feedRecords, values: {'animal': ref})),
                if (controller.canOpen(FarmModule.weights)) QuickAction(icon: Icons.monitor_weight_outlined, label: 'Weight', onTap: () => _openForm(FarmModule.weights, values: {'animal': ref})),
                if (controller.canOpen(FarmModule.illness) && FarmController.isActive(animal))
                  QuickAction(icon: Icons.sick_outlined, label: 'Report illness', onTap: () => _openForm(FarmModule.illness, values: {'animal': ref})),
                if (controller.canOpen(FarmModule.health)) QuickAction(icon: Icons.medical_services_outlined, label: 'Health', onTap: () => _openForm(FarmModule.health, values: {'animal': ref})),
                if (controller.canOpen(FarmModule.breeding) && a.isFemale) ...[
                  QuickAction(icon: Icons.science_outlined, label: 'Check semen', onTap: () => _showSemenCheck(animal)),
                  QuickAction(
                      icon: Icons.biotech_outlined, label: 'Service / AI', onTap: () => _openForm(FarmModule.breeding, values: {'animal': ref, 'method': 'AI', 'result': FarmModule.resultPending})),
                ],
                if (controller.canRecordCalving && a.isFemale) QuickAction(icon: Icons.child_friendly_outlined, label: 'Record calving', onTap: () => _recordCalving(animal)),
              ]),
              const SizedBox(height: 20),
              if (a.isFemale) ...[
                _Section(title: 'Reproduction', children: [
                  _InfoRow('Status', a.reproStatus),
                  if (a.lastCalving != null) _InfoRow('Last calving', '${formatDate(a.lastCalving!)} (${daysBetween(a.lastCalving!, controller.today)} days ago)'),
                  if (a.lactationStage != null) _InfoRow('Lactation', '${a.lactationStage} · day ${a.daysInMilk} in milk'),
                  _InfoRow('Services', '${a.services.length} in total · ${a.currentCycleServices.length} this cycle'),
                  _InfoRow(
                    'Services per conception',
                    a.servicesPerConceptionHistory.isEmpty
                        ? 'No conception recorded yet'
                        : '${a.avgServicesPerConception!.toStringAsFixed(1)} on average · ${a.servicesPerConceptionHistory.map((n) => 'conceived after $n').join(', ')}',
                  ),
                  if (a.services.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No services recorded.', style: TextStyle(color: Colors.black54))),
                  for (final s in a.services.reversed)
                    _RecordTile(
                      icon: Icons.biotech_outlined,
                      title: '${s['date']} · ${s['method'] ?? 'Service'} · ${s['bull'] ?? ''}',
                      subtitle: [
                        s.status,
                        if ('${s['semen'] ?? ''}'.isNotEmpty) 'Semen ${s['semen']}',
                        if ('${s['technician'] ?? ''}'.isNotEmpty) '${s['technician']}',
                        if ('${s['calvingDate'] ?? ''}'.isNotEmpty) 'Calved ${s['calvingDate']}'
                      ].join(' · '),
                      onTap: controller.canOpen(FarmModule.breeding) ? () => _openForm(FarmModule.breeding, existing: s) : null,
                    ),
                ]),
              ],
              _Section(title: 'Feed in this period', children: [
                ..._feedBreakdown(a, controller.periodDays, money),
              ]),
              if (a.isFemale)
                _Section(title: 'Recent milk entries', children: [
                  if (a.milkRecords.isEmpty) const Text('No milk recorded.', style: TextStyle(color: Colors.black54)),
                  for (final m in a.milkRecords.reversed.take(10))
                    _RecordTile(
                      icon: Icons.water_drop_outlined,
                      title: '${m['date']} · ${m['shift']} · ${m['litres']} L',
                      subtitle: [m['quality'], if ('${m['fat'] ?? ''}'.isNotEmpty) 'Fat ${m['fat']}%', if ('${m['snf'] ?? ''}'.isNotEmpty) 'SNF ${m['snf']}%'].join(' · '),
                      warn: !CowAnalytics.isSellable(m),
                      onTap: controller.canOpen(FarmModule.milkProduction) ? () => _openForm(FarmModule.milkProduction, existing: m) : null,
                    ),
                ]),
              _illnessSection(animal),
              _Section(title: 'Vaccination & health records', children: [
                if (a.withdrawalUntil != null) _InfoRow('Withdrawal', 'Milk withheld until ${formatDate(a.withdrawalUntil!)}'),
                if (a.healthRecords.isEmpty) const Text('No health records.', style: TextStyle(color: Colors.black54)),
                for (final h in a.healthRecords.reversed)
                  _RecordTile(
                    icon: Icons.medical_services_outlined,
                    title: '${h['date']} · ${h['type']} · ${h['details']}',
                    subtitle: [
                      if ('${h['medicine'] ?? ''}'.isNotEmpty) '${h['medicine']}',
                      if ('${h['withdrawalDays'] ?? ''}'.isNotEmpty) '${h['withdrawalDays']}-day withdrawal',
                      if ('${h['cost'] ?? ''}'.isNotEmpty) money(h.number('cost')),
                      h.status
                    ].join(' · '),
                    onTap: controller.canOpen(FarmModule.health) ? () => _openForm(FarmModule.health, existing: h) : null,
                  ),
              ]),
              _Section(title: 'Weight & growth', children: [
                _InfoRow('Current weight', a.latestWeight == null ? 'Not recorded' : '${formatQty(a.latestWeight!)} kg'),
                if (a.averageDailyGain != null) _InfoRow('Average daily gain', '${(a.averageDailyGain! * 1000).toStringAsFixed(0)} g/day'),
                for (final w in a.weightRecords.reversed)
                  _RecordTile(
                    icon: Icons.monitor_weight_outlined,
                    title: '${w['date']} · ${w['weight']} kg',
                    subtitle: '${w['bcs'] ?? ''}'.isEmpty ? '' : 'Body condition ${w['bcs']}',
                    onTap: controller.canOpen(FarmModule.weights) ? () => _openForm(FarmModule.weights, existing: w) : null,
                  ),
              ]),
              _Section(title: 'Family', children: [
                _InfoRow('Sire', '${animal['sire'] ?? ''}'.trim().isEmpty ? 'Not recorded' : '${animal['sire']}'),
                if (a.dam != null)
                  _RecordTile(icon: Icons.female, title: 'Dam: ${a.dam!['name']} (${a.dam!.id})', subtitle: '${a.dam!['breed']}', onTap: () => _openProfile(a.dam!))
                else
                  _InfoRow('Dam', '${animal['dam'] ?? ''}'.trim().isEmpty ? 'Not recorded' : '${animal['dam']} (not in register)'),
                for (final calf in a.offspring)
                  _RecordTile(
                      icon: Icons.pets_outlined, title: 'Calf: ${calf['name']} (${calf.id})', subtitle: 'Born ${calf['dob']} · ${calf['sex']} · sire ${calf['sire']}', onTap: () => _openProfile(calf)),
              ]),
              _Section(title: 'Timeline', children: [
                if (a.timeline.isEmpty) const Text('Nothing recorded yet.', style: TextStyle(color: Colors.black54)),
                for (final e in a.timeline) _RecordTile(icon: e.icon, title: '${e.date} · ${e.title}', subtitle: e.detail),
              ]),
            ]),
          );
        },
      );

  /// Health status (separate from operational status) and illness cases.
  Widget _illnessSection(FarmRecord animal) {
    final health = HealthAnalytics(controller.farm, today: controller.today);
    final cases = health.casesFor(animal);
    return _Section(title: 'Illness & health status', children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
        const Text('Health status: ', style: TextStyle(color: Colors.black54, fontSize: 13)),
        HealthChip(health.statusOf(animal)),
      ]),
      const SizedBox(height: 6),
      if (cases.isEmpty) const Text('No illness reported.', style: TextStyle(color: Colors.black54)),
      for (final c in cases.take(5))
        _RecordTile(
          icon: HealthRules.isOpen(c.data) ? Icons.sick_outlined : Icons.task_alt,
          title: '${'${c['noticedAt']}'.split(' ').first} · ${c['symptoms']}',
          subtitle: '${c.id} · ${c['stage']} · ${c['severity']}${'${c['diagnosis'] ?? ''}'.isEmpty ? '' : ' · ${c['diagnosisStatus']}: ${c['diagnosis']}'}',
          warn: HealthRules.isUrgent(controller.farm, c),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IllnessDetailsPage(illnessId: c.id))),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalHealthHistoryPage(animalId: animal.id))),
          icon: const Icon(Icons.history, size: 18),
          label: const Text('Full health history & production review'),
        ),
      ),
    ]);
  }

  List<Widget> _feedBreakdown(CowAnalytics a, int? days, String Function(double) money) {
    final from = days == null ? null : controller.today.subtract(Duration(days: days - 1));
    final totals = <String, (double, double, bool)>{};
    for (final f in a.feedShares) {
      final d = FarmRecord.parseDate(f.date);
      if (from != null && (d == null || d.isBefore(from) || d.isAfter(controller.today))) continue;
      final prev = totals[f.feed] ?? (0.0, 0.0, false);
      totals[f.feed] = (prev.$1 + f.kg, prev.$2 + f.cost, prev.$3 || f.shared);
    }
    if (totals.isEmpty) return [const Text('No feed recorded for this animal in this period.', style: TextStyle(color: Colors.black54))];
    return [
      for (final e in totals.entries) _InfoRow(e.key, '${e.value.$1.toStringAsFixed(1)} kg${controller.canSeeFinance ? ' · ${money(e.value.$2)}' : ''}${e.value.$3 ? ' · includes group share' : ''}'),
      if (a.group.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Group rations for “${a.group}” are shared equally between the animals in that group.', style: const TextStyle(fontSize: 11, color: Colors.black54))),
    ];
  }

  Future<void> _showSemenCheck(FarmRecord cow) async {
    final results = controller.advisor.rank(cow);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
            Text('Semen suitability for ${cow['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Checked against her pedigree, condition and breeding history.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            if (results.isEmpty) const EmptyHint('No semen batches recorded. Add them in Semen Inventory.'),
            for (final r in results)
              SemenCheckCard(
                result: r,
                onUse: () {
                  Navigator.pop(ctx);
                  _openForm(FarmModule.breeding, values: {'animal': cow.reference, 'method': 'AI', 'semen': '${r.semen['code']}', 'bull': '${r.semen['bull']}', 'result': FarmModule.resultPending});
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _recordCalving(FarmRecord cow) async {
    final error = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CalvingSheet(controller: controller, cow: cow),
    );
    if (!mounted || error == null) return;
    showToast(context, error);
  }
}

class _CalvingSheet extends StatefulWidget {
  const _CalvingSheet({required this.controller, required this.cow});

  final CowProfileController controller;
  final FarmRecord cow;

  @override
  State<_CalvingSheet> createState() => _CalvingSheetState();
}

class _CalvingSheetState extends State<_CalvingSheet> {
  final name = TextEditingController();
  final tag = TextEditingController();
  final weight = TextEditingController();
  late DateTime date = widget.controller.today;
  String sex = 'Female';
  String? error;
  bool busy = false;

  @override
  void dispose() {
    for (final c in [name, tag, weight]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final w = weight.text.trim();
    final kg = w.isEmpty ? null : double.tryParse(w);
    if (w.isNotEmpty && kg == null) {
      setState(() => error = 'Birth weight must be a number.');
      return;
    }
    setState(() => busy = true);
    final result = await widget.controller.recordCalving(date: date, calfName: name.text, sex: sex, tag: tag.text, birthWeight: kg);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        busy = false;
        error = result;
      });
      return;
    }
    Navigator.pop(context, 'Calving recorded — ${name.text.trim()} added to Animals');
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.controller.calvingService;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Record calving · ${widget.cow['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            service == null ? 'No service recorded — the calf’s sire will be left blank.' : 'Service ${service['date']} · sire ${service['bull']}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: widget.controller.today);
              if (picked != null) setState(() => date = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Calving date: ${formatDate(date)}'),
          ),
          const SizedBox(height: 12),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Calf name', prefixIcon: Icon(Icons.pets_outlined))),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'Female', label: Text('Female')), ButtonSegment(value: 'Male', label: Text('Male'))],
            selected: {sex},
            onSelectionChanged: (v) => setState(() => sex = v.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: tag, decoration: const InputDecoration(labelText: 'Ear tag (optional)', prefixIcon: Icon(Icons.sell_outlined))),
          const SizedBox(height: 12),
          TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Birth weight kg (optional)', prefixIcon: Icon(Icons.monitor_weight_outlined))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Save calving'))),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.animal, required this.a});

  final FarmRecord animal;
  final CowAnalytics a;

  @override
  Widget build(BuildContext context) {
    final withdrawal = a.withdrawalUntil;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(FarmModule.recordIconFor(FarmModule.animals), color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${animal['name']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              Text([animal.id, if ('${animal['tag'] ?? ''}'.isNotEmpty) 'Tag ${animal['tag']}'].join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Text(animal.status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brand)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          [animal['breed'], animal['sex'], a.ageLabel, if (a.group.isNotEmpty) a.group, if ('${animal['location'] ?? ''}'.isNotEmpty) animal['location']].join(' · '),
          style: const TextStyle(color: Colors.white),
        ),
        if (a.isFemale) ...[
          const SizedBox(height: 6),
          Text(a.reproStatus, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
        if (a.lactationStage != null) Text('${a.lactationStage} · day ${a.daysInMilk} in milk', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        if (withdrawal != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.block_outlined, size: 18, color: Color(0xFF9A5B00)),
              const SizedBox(width: 6),
              Expanded(child: Text('Milk withdrawal until ${formatDate(withdrawal)} — do not sell her milk', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth > 640 ? 4 : 2;
        final width = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final child in children) SizedBox(width: width, child: child)]);
      });
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.sub, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7EDE8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.ink)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: Colors.black54),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.black54))),
        ]),
      );
}

/// Milk (litres) and feed (kg) side by side for each day.
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.points});

  final List<DayPoint> points;

  static const milkColor = Color(0xFF2F6FB8);
  static const feedColor = Color(0xFF7FB069);

  @override
  Widget build(BuildContext context) {
    final maxMilk = points.fold(0.0, (m, p) => p.milk > m ? p.milk : m);
    final maxFeed = points.fold(0.0, (m, p) => p.feed > m ? p.feed : m);
    if (maxMilk == 0 && maxFeed == 0) return const EmptyHint('No milk or feed recorded in the last 14 days.');
    const height = 110.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7EDE8))),
      child: Column(children: [
        Row(children: [
          _legend(milkColor, 'Milk (max ${maxMilk.toStringAsFixed(1)} L)'),
          const SizedBox(width: 14),
          _legend(feedColor, 'Feed (max ${maxFeed.toStringAsFixed(1)} kg)'),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final p in points)
              Expanded(
                child: Tooltip(
                  message: '${formatDate(p.day)}\nMilk ${p.milk.toStringAsFixed(1)} L · Feed ${p.feed.toStringAsFixed(1)} kg',
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                    _bar(maxMilk == 0 ? 0 : p.milk / maxMilk * height, milkColor),
                    const SizedBox(width: 1),
                    _bar(maxFeed == 0 ? 0 : p.feed / maxFeed * height, feedColor),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(formatDate(points.first.day).substring(5), style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const Expanded(
            child: Text('Bars are scaled separately', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Colors.black45)),
          ),
          Text(formatDate(points.last.day).substring(5), style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String text) => Flexible(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
        ]),
      );

  Widget _bar(double h, Color c) => Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 8),
          height: h < 2 && h > 0 ? 2 : h,
          decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        // A Material (not a coloured Container) so row tap ripples stay visible.
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE7EDE8))),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.icon, required this.title, required this.subtitle, this.onTap, this.warn = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: warn ? const Color(0xFF9A5B00) : AppColors.brand, size: 20),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      );
}
