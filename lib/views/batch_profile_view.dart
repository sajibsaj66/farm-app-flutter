import 'package:flutter/material.dart';

import '../controllers/batch_analytics.dart';
import '../controllers/batch_profile_controller.dart';
import '../controllers/finance_engine.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dialogs.dart';

/// A flock, pond or hive group: head count flow, growth, feed, production,
/// unsold stock, costs and profit.
class BatchProfilePage extends StatefulWidget {
  const BatchProfilePage({super.key, required this.batchId});

  final String batchId;

  @override
  State<BatchProfilePage> createState() => _BatchProfilePageState();
}

class _BatchProfilePageState extends State<BatchProfilePage> {
  late final controller = BatchProfileController(widget.batchId);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _openForm(String module, {FarmRecord? existing, Map<String, String> values = const {}}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: module, existing: existing, initialValues: values)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final batch = controller.batch;
          final a = controller.analytics;
          if (batch == null || a == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('This batch no longer exists.')));
          }
          final ref = batch.reference;
          final currency = controller.farm.profile.currency;
          String money(double v) => '$currency${v.toStringAsFixed(0)}';
          final unit = a.unitName;
          return Scaffold(
            appBar: AppBar(
              title: Text('${batch['name']}'),
              actions: [
                if (controller.canOpen(FarmModule.batches)) IconButton(tooltip: 'Edit batch', icon: const Icon(Icons.edit_outlined), onPressed: () => _openForm(FarmModule.batches, existing: batch)),
              ],
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              _Header(batch: batch, a: a),
              const SizedBox(height: 14),
              _Grid(children: [
                _Stat(Icons.groups, 'Alive now', '${formatQty(a.closing)} $unit', 'Opened with ${formatQty(a.opening)}'),
                _Stat(Icons.heart_broken, 'Mortality', '${(a.mortalityRate * 100).toStringAsFixed(1)}%',
                    '${formatQty(a.died)} died · last 7 days ${(a.recentMortalityRate(7) * 100).toStringAsFixed(1)}%'),
                _Stat(Icons.scale, 'Average weight', a.avgWeightG == null ? '—' : '${formatQty(a.avgWeightG!)} g',
                    a.biomassKg == null ? 'No sampling yet' : 'Biomass ≈ ${a.biomassKg!.toStringAsFixed(0)} kg'),
                _Stat(Icons.grass, 'Feed used', '${a.feedKg.toStringAsFixed(0)} kg', a.fcr == null ? (controller.canSeeFinance ? money(a.feedCost) : '') : 'FCR ${a.fcr!.toStringAsFixed(2)}'),
              ]),
              const SizedBox(height: 14),
              _Section(title: 'Head count', children: [
                _Row('Opening', '${formatQty(a.opening)} $unit'),
                _Row('Added (purchase, hatching, transfer in)', formatQty(a.additions)),
                _Row('Died / lost', formatQty(a.died)),
                _Row('Sold', formatQty(a.soldHead)),
                _Row('Harvested', formatQty(a.harvestedHead)),
                _Row('Transferred out / culled', formatQty(a.removedByMovement)),
                _Row('Closing (alive now)', '${formatQty(a.closing)} $unit', bold: true),
              ]),
              if (a.purpose == 'Eggs' || a.eggs > 0) ...[
                _Section(title: 'Egg production', children: [
                  _Row('Eggs produced', formatQty(a.eggs)),
                  _Row('Saleable', formatQty(a.saleableEggs)),
                  _Row('Broken / damaged', formatQty(a.damagedEggs)),
                  if (a.layingRate != null) _Row('Average laying rate', '${a.layingRate!.toStringAsFixed(1)}%'),
                  const SizedBox(height: 8),
                  _EggChart(points: a.dailyEggs(14)),
                ]),
              ],
              if (a.harvestKg > 0 || a.liveKgSold > 0 || a.latestSample != null)
                _Section(title: 'Growth, harvest & sales', children: [
                  if (a.latestSample != null) _Row('Latest sample', '${a.latestSample!['date']} · ${a.latestSample!['avgWeight']} g × ${a.latestSample!['sampleSize']}'),
                  _Row('Biomass estimate', a.biomassKg == null ? '—' : '${a.biomassKg!.toStringAsFixed(0)} kg'),
                  if (a.harvestKg > 0) _Row('Harvested', '${a.harvestKg.toStringAsFixed(1)} kg'),
                  if (a.liveKgSold > 0) _Row('Sold live', '${a.liveKgSold.toStringAsFixed(1)} kg (${formatQty(a.soldHead)} $unit)'),
                  if (a.weightGainKg != null) _Row('Weight gained', '${a.weightGainKg!.toStringAsFixed(0)} kg'),
                  if (a.fcr != null) _Row('Feed conversion ratio', a.fcr!.toStringAsFixed(2)),
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(a.biomassAssumption, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                  if (a.latestSample != null && '${a.latestSample!['ph'] ?? ''}'.isNotEmpty)
                    _Row('Water (latest)', '${a.latestSample!['waterTemp']} °C · pH ${a.latestSample!['ph']} · DO ${a.latestSample!['oxygen']} mg/L'),
                ]),
              if (a.unsold.isNotEmpty)
                _Section(title: 'Unsold stock from this batch', children: [
                  for (final e in a.unsold.entries) _Row(e.key, formatQty(e.value < 0 ? 0 : e.value)),
                ]),
              if (controller.canSeeFinance) _money(a, money),
              const SizedBox(height: 4),
              const SectionTitle('Record for this batch'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (controller.canOpen(FarmModule.feedRecords)) QuickAction(icon: Icons.grass_outlined, label: 'Feed', onTap: () => _openForm(FarmModule.feedRecords, values: {'batch': ref})),
                if (controller.canOpen(FarmModule.mortality)) QuickAction(icon: Icons.heart_broken_outlined, label: 'Mortality', onTap: () => _openForm(FarmModule.mortality, values: {'batch': ref})),
                if (controller.canOpen(FarmModule.sampling)) QuickAction(icon: Icons.scale_outlined, label: 'Weight sample', onTap: () => _openForm(FarmModule.sampling, values: {'batch': ref})),
                if (controller.canOpen(FarmModule.production))
                  QuickAction(
                      icon: Icons.egg_outlined,
                      label: a.purpose == 'Eggs' ? 'Eggs' : 'Harvest',
                      onTap: () => _openForm(FarmModule.production, values: {'batch': ref, 'product': _productFor(a), 'unit': FarmModule.defaultProductUnit[_productFor(a)] ?? 'kg'})),
                if (controller.canOpen(FarmModule.health)) QuickAction(icon: Icons.medical_services_outlined, label: 'Health', onTap: () => _openForm(FarmModule.health, values: {'batch': ref})),
                if (controller.canOpen(FarmModule.batchMovements)) QuickAction(icon: Icons.swap_horiz, label: 'Add / move', onTap: () => _openForm(FarmModule.batchMovements, values: {'batch': ref})),
                if (controller.canOpen(FarmModule.sales))
                  QuickAction(
                      icon: Icons.point_of_sale_outlined,
                      label: 'Sale',
                      onTap: () => _openForm(FarmModule.sales, values: {
                            'batch': ref,
                            'product': a.purpose == 'Meat' ? 'Live birds' : _productFor(a),
                            'unit': a.purpose == 'Meat' ? 'kg' : (FarmModule.defaultProductUnit[_productFor(a)] ?? 'kg')
                          })),
                if (controller.isOpen && controller.canOpen(FarmModule.batches)) QuickAction(icon: Icons.task_alt, label: 'Close batch', onTap: () => _close(context, batch)),
              ]),
              const SizedBox(height: 18),
              _Section(title: 'Mortality & losses', children: [
                if (a.deaths.isEmpty) const Text('No losses recorded.', style: TextStyle(color: Colors.black54)),
                for (final d in a.deaths.reversed.take(10))
                  _Tile(Icons.heart_broken_outlined, '${d['date']} · ${d['count']} lost', '${d['cause']}${'${d['disposal'] ?? ''}'.isEmpty ? '' : ' · ${d['disposal']}'}',
                      () => _openForm(FarmModule.mortality, existing: d)),
              ]),
              if (a.movements.isNotEmpty)
                _Section(title: 'Movements', children: [
                  for (final m in a.movements.reversed.take(10))
                    _Tile(Icons.swap_horiz, '${m['date']} · ${m['type']} · ${m['quantity']}', '${m['notes'] ?? ''}', () => _openForm(FarmModule.batchMovements, existing: m)),
                ]),
              if (a.health.isNotEmpty)
                _Section(title: 'Health & vaccination', children: [
                  for (final h in a.health.reversed)
                    _Tile(Icons.medical_services_outlined, '${h['date']} · ${h['type']} · ${h['details']}', [h.status, if ('${h['next'] ?? ''}'.isNotEmpty) 'next ${h['next']}'].join(' · '),
                        () => _openForm(FarmModule.health, existing: h)),
                ]),
              if (a.sales.isNotEmpty && controller.canSeeFinance)
                _Section(title: 'Sales', children: [
                  for (final s in a.sales.reversed)
                    _Tile(Icons.point_of_sale_outlined, '${s['date']} · ${s['product']} · ${s['qty']} ${s['unit']}', '${s['customer']} · net ${money(s.number('amount'))} · ${s['status']}',
                        () => _openForm(FarmModule.sales, existing: s)),
                ]),
            ]),
          );
        },
      );

  String _productFor(BatchAnalytics a) => switch (a.purpose) {
        'Eggs' => 'Eggs',
        'Honey' => 'Honey',
        'Meat' => 'Meat',
        _ => '${a.batch['species']}'.toLowerCase().contains('shrimp') ? 'Shrimp' : 'Fish',
      };

  Widget _money(BatchAnalytics a, String Function(double) money) {
    final p = a.profit;
    final out = a.saleableOutput;
    return _Section(title: 'Cost & profit (whole batch so far)', children: [
      _Row('Stocking / purchase', money(p.cost(FinanceEngine.catStocking))),
      _Row('Feed', money(p.cost(FinanceEngine.catFeed))),
      _Row('Health & vaccination', money(p.cost(FinanceEngine.catTreatment))),
      _Row('Other direct costs', money(p.directCost - p.cost(FinanceEngine.catStocking) - p.cost(FinanceEngine.catFeed) - p.cost(FinanceEngine.catTreatment))),
      _Row('Shared costs allocated', money(p.allocatedCost)),
      for (final m in p.allocatedByMethod.entries) _Row('   · ${m.key}', money(m.value)),
      _Row('Total cost', money(p.totalCost), bold: true),
      _Row('Revenue (net sales)', money(p.revenue)),
      _Row(p.profit >= 0 ? 'Operating profit' : 'Operating loss', money(p.profit), bold: true, color: p.profit >= 0 ? AppColors.brand : const Color(0xFFB3261E)),
      if (out != null && a.costPerSaleableUnit != null) _Row(out.$3, '${controller.farm.profile.currency}${a.costPerSaleableUnit!.toStringAsFixed(2)} per ${out.$2}'),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Revenue is actual sales only; unsold eggs, fish or honey are not counted as income.', style: TextStyle(fontSize: 11, color: Colors.black54)),
      ),
    ]);
  }

  Future<void> _close(BuildContext context, FarmRecord batch) async {
    final ok = await confirmDialog(
      context,
      title: 'Close ${batch['name']}?',
      message: 'The batch is marked Closed today and its final settlement covers its whole life. Record any final sales or harvest first. You can reopen it by editing the status.',
      confirmLabel: 'Close batch',
    );
    if (!ok) return;
    final error = await controller.closeBatch(controller.today);
    if (context.mounted) showToast(context, error ?? 'Batch closed');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.batch, required this.a});

  final FarmRecord batch;
  final BatchAnalytics a;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(Icons.groups, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${batch['name']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                Text('${batch.id} · ${batch['species']}${'${batch['breed'] ?? ''}'.isEmpty ? '' : ' · ${batch['breed']}'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text(batch.status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brand)),
            ),
          ]),
          const SizedBox(height: 12),
          Text('${batch['purpose']} · ${batch['location']} · started ${batch['startDate']} · day ${a.ageDays}', style: const TextStyle(color: Colors.white)),
        ]),
      );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth > 640 ? 4 : 2;
        final width = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final child in children) SizedBox(width: width, child: child)]);
      });
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value, this.sub);

  final IconData icon;
  final String label;
  final String value;
  final String sub;

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
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false, this.color});

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 13, color: color))),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap);

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.brand, size: 20),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      );
}

class _EggChart extends StatelessWidget {
  const _EggChart({required this.points});

  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    final max = points.fold(0.0, (m, p) => p.$2 > m ? p.$2 : m);
    if (max == 0) return const Text('No eggs recorded in the last 14 days.', style: TextStyle(color: Colors.black54));
    const height = 80.0;
    return Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (day, eggs) in points)
            Expanded(
              child: Tooltip(
                message: '${formatDate(day)}: ${formatQty(eggs)} eggs',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(height: eggs / max * height, decoration: const BoxDecoration(color: Color(0xFFE0A526), borderRadius: BorderRadius.vertical(top: Radius.circular(2)))),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Text(formatDate(points.first.$1).substring(5), style: const TextStyle(fontSize: 10, color: Colors.black54)),
        Expanded(
            child:
                Text('Eggs per day (max ${formatQty(max)})', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black45))),
        Text(formatDate(points.last.$1).substring(5), style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ]),
    ]);
  }
}
