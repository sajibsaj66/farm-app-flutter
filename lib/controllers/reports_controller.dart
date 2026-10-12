import 'package:flutter/foundation.dart';

import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/farm_module.dart';
import '../models/farm_profile.dart';
import '../models/farm_record.dart';
import '../models/finance.dart';
import 'auth_controller.dart';
import 'batch_analytics.dart';
import 'farm_controller.dart';
import 'finance_engine.dart';
import 'health_reports.dart';
import 'herd_analytics.dart';

enum ReportKind {
  farmPnl('Farm profit & loss', financial: true),
  monthly('Monthly profit & loss', financial: true),
  cashFlow('Cash flow', financial: true),
  animals('Animal cost & profit', financial: true),
  batches('Batch cost & profit', financial: true),
  species('Species-wise performance', financial: true),
  costPerUnit('Cost per litre & kg', financial: true),
  feed('Feed consumption & cost'),
  production('Production & unsold stock'),
  mortality('Mortality'),
  sales('Sales & collections', financial: true),
  expensive('Most expensive to maintain', financial: true),
  breeding('Breeding performance'),
  health('Vaccination & treatment schedule'),
  inventory('Inventory status & value'),
  healthSick('Health: current sick animals'),
  healthHistory('Health: illness history'),
  healthFrequency('Health: illness frequency by species'),
  healthTreatments('Health: treatment records'),
  healthConsultations('Health: veterinary consultations'),
  healthMedication('Health: medication administration'),
  healthFollowUps('Health: upcoming & overdue follow-ups'),
  healthRecovered('Health: recovered animals'),
  healthRecurring('Health: ongoing & recurring illness'),
  healthCosts('Health: veterinary & medicine costs', financial: true),
  healthProduction('Health: production observations'),
  annual('Yearly summary', financial: true),
  animalTrade('Animal purchases & sales', financial: true),
  records('Export raw records');

  const ReportKind(this.label, {this.financial = false});
  final String label;

  /// Shows profit, income or costs — only for users who may see finances.
  final bool financial;

  /// Not part of this livestock system (poultry/fish/bee batches).
  bool get outOfScope => this == batches;
}

enum FeedGrouping { day, week, month, year }

/// Holds the report filter and builds every report as a [ReportTable].
class ReportsController extends ChangeNotifier {
  ReportsController({FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock ?? DateTime.now {
    final t = today;
    filter = ReportFilter(from: DateTime(t.year, t.month), to: t);
    if (!kinds.contains(kind) && kinds.isNotEmpty) kind = kinds.first;
  }

  final FarmController farm;
  final AuthController _auth;
  final DateTime Function() _clock;

  late ReportFilter filter;
  ReportKind kind = ReportKind.farmPnl;
  FeedGrouping feedGrouping = FeedGrouping.day;
  String exportModule = FarmModule.feedRecords;

  DateTime get today => dateOnly(_clock());

  bool get canSeeFinance => _auth.access.canSeeFinance;

  /// Reports this user may open: operational reports for everyone; profit,
  /// income and cost reports only with finance rights.
  List<ReportKind> get kinds => [
        for (final k in ReportKind.values)
          if (!k.outOfScope && (canSeeFinance || !k.financial)) k
      ];

  /// Modules whose raw records this user may export.
  List<String> get exportModules => [
        for (final m in FarmModule.all)
          if (_auth.access.canOpenModule(m.name)) m.name
      ];

  FarmProfile get profile => farm.profile;

  String money(double v) => '${profile.currency}${v.toStringAsFixed(0)}';
  static String n0(double v) => v.toStringAsFixed(0);
  static String n1(double v) => v.toStringAsFixed(1);
  static String n2(double v) => v.toStringAsFixed(2);

  // ------------------------------------------------------------ filter state

  static const presets = ['This month', 'Last 7 days', 'Last 30 days', 'This year', 'All time'];

  void applyPreset(String preset) {
    final t = today;
    final (from, to) = switch (preset) {
      'Last 7 days' => (t.subtract(const Duration(days: 6)), t),
      'Last 30 days' => (t.subtract(const Duration(days: 29)), t),
      'This year' => (DateTime(t.year), t),
      'All time' => (earliestDate, t),
      _ => (DateTime(t.year, t.month), t),
    };
    setFilter(filter.copyWith(from: from, to: to));
  }

  DateTime get earliestDate {
    var min = today;
    for (final m in farm.modules) {
      for (final r in farm.list(m)) {
        for (final f in const ['date', 'startDate', 'purchaseDate']) {
          final d = r.dateOf(f);
          if (d != null && d.isBefore(min)) min = dateOnly(d);
        }
      }
    }
    return min;
  }

  /// Error message when the dates are the wrong way round.
  String? setDates(DateTime from, DateTime to) {
    if (to.isBefore(from)) return 'The end date is before the start date.';
    setFilter(filter.copyWith(from: dateOnly(from), to: dateOnly(to)));
    return null;
  }

  void setFilter(ReportFilter f) {
    filter = f;
    shown = pageSize;
    notifyListeners();
  }

  void setKind(ReportKind k) {
    kind = k;
    shown = pageSize;
    notifyListeners();
  }

  void setFeedGrouping(FeedGrouping g) {
    feedGrouping = g;
    notifyListeners();
  }

  void setExportModule(String m) {
    exportModule = m;
    notifyListeners();
  }

  List<String> get speciesOptions => farm.list(FarmModule.species).where(FarmController.isLivestockSpecies).map((s) => '${s['name']}').toList();
  List<String> get locationOptions => farm.list(FarmModule.locations).map((s) => '${s['name']}').toList();
  List<String> get animalOptions => farm.list(FarmModule.animals).map((a) => a.id).toList();
  List<String> get batchOptions => farm.list(FarmModule.batches).map((b) => b.id).toList();
  String animalLabel(String id) => farm.find(FarmModule.animals, id)?.reference ?? id;
  String batchLabel(String id) => farm.find(FarmModule.batches, id)?.reference ?? id;

  FinanceEngine get engine => FinanceEngine(farm, filter);

  String get periodLabel => '${formatDate(filter.from)} to ${formatDate(filter.to)} · ${filter.description}';

  // ------------------------------------------------------------- dispatch

  /// Free-text search applied to the rows of any report.
  String query = '';

  void setQuery(String q) {
    query = q;
    shown = pageSize;
    notifyListeners();
  }

  /// Rows shown on screen (pagination). CSV always exports every row.
  static const pageSize = 50;
  int shown = pageSize;

  void showMore() {
    shown += pageSize;
    notifyListeners();
  }

  HealthReports get health => HealthReports(farm, filter, today: today);

  /// The selected report, narrowed by [query]. The CSV uses the same rows.
  ReportTable build() {
    final t = _build();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return t;
    final keep = [
      for (var i = 0; i < t.rows.length; i++)
        if (t.rows[i].any((c) => c.toLowerCase().contains(q))) i
    ];
    return ReportTable(
      title: t.title,
      columns: t.columns,
      rows: [for (final i in keep) t.rows[i]],
      linkIds: [
        for (final i in keep)
          if (i < t.linkIds.length) t.linkIds[i]
      ],
      notes: [...t.notes, 'Showing rows containing "$query".'],
      summary: t.summary,
      numericFrom: t.numericFrom,
    );
  }

  ReportTable _build() {
    // Checked here too, not only in the report picker.
    if (!kinds.contains(kind)) kind = kinds.isEmpty ? ReportKind.feed : kinds.first;
    if (kind == ReportKind.records && !exportModules.contains(exportModule)) exportModule = exportModules.isEmpty ? FarmModule.feedRecords : exportModules.first;
    return _report();
  }

  ReportTable _report() => switch (kind) {
        ReportKind.farmPnl => farmPnl(),
        ReportKind.monthly => monthly(),
        ReportKind.cashFlow => cashFlow(),
        ReportKind.animals => animals(),
        ReportKind.batches => batches(),
        ReportKind.species => species(),
        ReportKind.costPerUnit => costPerUnit(),
        ReportKind.feed => feed(),
        ReportKind.production => productionReport(),
        ReportKind.mortality => mortality(),
        ReportKind.sales => salesReport(),
        ReportKind.expensive => expensive(),
        ReportKind.breeding => breeding(),
        ReportKind.health => healthSchedule(),
        ReportKind.inventory => inventory(),
        ReportKind.records => records(exportModule),
        ReportKind.healthSick => health.sickList(),
        ReportKind.healthHistory => health.history(),
        ReportKind.healthFrequency => health.frequencyBySpecies(),
        ReportKind.healthTreatments => health.treatments(),
        ReportKind.healthConsultations => health.consultations(),
        ReportKind.healthMedication => health.medication(),
        ReportKind.healthFollowUps => health.followUps(),
        ReportKind.healthRecovered => health.recovered(),
        ReportKind.healthRecurring => health.recurring(),
        ReportKind.healthCosts => health.costs(),
        ReportKind.healthProduction => health.productionObservations(),
        ReportKind.annual => annual(),
        ReportKind.animalTrade => animalTrade(),
      };

  List<String> get _methodNotes => [
        'Revenue is actual net sales (gross − discount − deductions) on the sale date — production is never treated as sold.',
        'Feed cost is ${profile.feedCostBasis == FeedCostBasis.consumption ? 'counted when fed (quantity × price on each feed record). Feed purchases entered as expenses are stock bought and are not counted again.' : 'counted when bought (Feed expenses), plus manual expense-only feed records.'}',
        'Animal purchase prices are assets: ${profile.assetMethod == AssetMethod.depreciate ? 'depreciated straight-line over ${formatQty(profile.depreciationYears)} years to ${formatQty(profile.residualPercent)}%,' : 'not depreciated,'} with the book value charged only when an animal is sold or lost.',
      ];

  // ------------------------------------------------------- financial reports

  /// One row per calendar year on record: milk, revenue, costs, result and
  /// herd changes. (Uses the species/animal/location filters, not the dates.)
  ReportTable annual() {
    final first = earliestDate.year;
    final rows = <List<String>>[];
    for (var y = today.year; y >= first; y--) {
      final from = DateTime(y);
      final to = y == today.year ? today : DateTime(y, 12, 31);
      final e = FinanceEngine(farm, filter.copyWith(from: from, to: to));
      final pnl = e.profitAndLoss;
      bool inYear(DateTime? d) => d != null && d.year == y;
      final animals = farm.list(FarmModule.animals);
      rows.add([
        '$y',
        n0(farm.inRange(FarmModule.milkProduction, from, to).fold(0.0, (s, m) => s + m.number('litres'))),
        n0(pnl.revenue),
        n0(pnl.costs),
        n0(pnl.operatingProfit),
        '${animals.where((a) => inYear(a.dateOf('purchaseDate'))).length}',
        '${farm.inRange(FarmModule.sales, from, to).where((s) => '${s['product']}' == 'Live animal').length}',
        '${farm.inRange(FarmModule.mortality, from, to).where((m) => '${m['animal']}'.isNotEmpty).length}',
      ]);
    }
    return ReportTable(
      title: ReportKind.annual.label,
      columns: ['Year', 'Milk (L)', 'Revenue (${profile.currency})', 'Costs (${profile.currency})', 'Operating result (${profile.currency})', 'Animals bought', 'Animals sold', 'Deaths'],
      rows: rows,
      notes: ['Each year runs from 1 January to 31 December (this year: to today). The date filter is not used.', ..._methodNotes],
    );
  }

  /// Each animal bought or sold in the period: purchase price, sale, the cost
  /// of keeping it, and the result of the trade.
  ReportTable animalTrade() {
    final whole = FinanceEngine(farm, filter.copyWith(from: earliestDate, to: today));
    final costs = {for (final p in whole.unitProfits) p.unit: whole.productionCost(p)};
    final rows = <List<String>>[];
    final ids = <String>[];
    double bought = 0, sold = 0, result = 0;
    for (final a in farm.list(FarmModule.animals)) {
      final purchased = a.dateOf('purchaseDate');
      final sale = farm.list(FarmModule.sales).where((s) => '${s['product']}' == 'Live animal' && a.isReferencedBy(s['animal'])).firstOrNull;
      final soldOn = sale?.dateOf('date');
      bool inPeriod(DateTime? d) => d != null && !dateOnly(d).isBefore(filter.from) && !dateOnly(d).isAfter(filter.to);
      if (!inPeriod(purchased) && !inPeriod(soldOn)) continue;
      if (filter.species != null && '${a['species']}' != filter.species) continue;
      final price = a.number('purchasePrice');
      final net = sale?.number('amount') ?? 0;
      final keep = costs[UnitRef.animal(a.id)] ?? 0;
      final outcome = sale == null ? null : net - price - keep;
      bought += inPeriod(purchased) ? price : 0;
      sold += inPeriod(soldOn) ? net : 0;
      result += outcome ?? 0;
      ids.add(a.id);
      rows.add([
        a.reference,
        '${a['species']}',
        '${a['purchaseDate'] ?? ''}'.isEmpty ? 'Born on farm' : '${a['purchaseDate']}',
        n0(price),
        sale == null ? 'Not sold (${a.status})' : '${sale['date']}',
        sale == null ? '' : n0(net),
        n0(keep),
        outcome == null ? '' : n0(outcome),
      ]);
    }
    return ReportTable(
      title: ReportKind.animalTrade.label,
      columns: ['Animal', 'Species', 'Bought on', 'Purchase price', 'Sold on', 'Net sale', 'Cost of keeping', 'Result'],
      rows: rows,
      linkIds: ids,
      numericFrom: 3,
      summary: [('Bought in period', money(bought)), ('Sold in period (net)', money(sold)), ('Result of animals sold', money(result))],
      notes: const [
        'Result = net sale − purchase price − cost of keeping (feed, health, breeding, direct and allocated shared costs while on the farm).',
        'Animals not yet sold show their costs so far; their result is not estimated.',
      ],
    );
  }

  ReportTable farmPnl() {
    final e = engine;
    final pnl = e.profitAndLoss;
    final rows = <List<String>>[
      for (final r in pnl.revenueByProduct.entries) ['Revenue', r.key, n0(r.value)],
      ['Revenue', 'Total revenue', n0(pnl.revenue)],
      for (final c in (pnl.costsByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) ['Cost', c.key, n0(c.value)],
      ['Cost', 'Total costs', n0(pnl.costs)],
      ['Result', pnl.operatingProfit >= 0 ? 'Operating profit' : 'Operating loss', n0(pnl.operatingProfit)],
    ];
    return ReportTable(
      title: ReportKind.farmPnl.label,
      columns: ['Section', 'Line', 'Amount (${profile.currency})'],
      rows: rows,
      numericFrom: 2,
      summary: [
        ('Revenue', money(pnl.revenue)),
        ('Costs', money(pnl.costs)),
        (pnl.operatingProfit >= 0 ? 'Operating profit' : 'Operating loss', money(pnl.operatingProfit)),
        ('Net cash flow (not profit)', money(e.netCashFlow)),
      ],
      notes: [
        ..._methodNotes,
        if (pnl.excludedOverhead > 0) 'Filtered report: ${money(pnl.excludedOverhead)} of farm-wide overhead is not allocated to the selected animals/batches and is left out.',
        'Operating profit is not cash: see the Cash flow report for money actually received and paid.',
      ],
    );
  }

  ReportTable monthly() {
    final e = engine;
    final rows = [
      for (final (m, rev, cost, cin, cout) in e.monthly) [m, n0(rev), n0(cost), n0(rev - cost), n0(cin), n0(cout), n0(cin - cout)],
    ];
    return ReportTable(
      title: ReportKind.monthly.label,
      columns: ['Month', 'Revenue', 'Costs', 'Operating profit', 'Cash in', 'Cash out', 'Net cash flow'],
      rows: rows,
      summary: [('Months', '${rows.length}'), ('Operating profit', money(e.profitAndLoss.operatingProfit)), ('Net cash flow', money(e.netCashFlow))],
      notes: _methodNotes,
    );
  }

  ReportTable cashFlow() {
    final e = engine;
    final byCat = <String, double>{};
    for (final c in e.cashFlow) {
      byCat[c.category] = (byCat[c.category] ?? 0) + c.amount;
    }
    final rows = [
      for (final c in (byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) [c.value >= 0 ? 'In' : 'Out', c.key, n0(c.value.abs())],
    ];
    return ReportTable(
      title: ReportKind.cashFlow.label,
      columns: ['Direction', 'Category', 'Amount (${profile.currency})'],
      rows: rows,
      numericFrom: 2,
      summary: [('Cash in', money(e.cashIn)), ('Cash out', money(e.cashOut)), ('Net cash flow', money(e.netCashFlow))],
      notes: const [
        'Net cash flow = cash actually received − cash actually paid. It is not profit.',
        'Expenses marked "Due" are not counted until paid. Sales count only the amount paid at sale and later payments received.',
        'Treatment and breeding costs on health/breeding records, animal purchases and batch stocking are assumed paid on their dates.',
      ],
    );
  }

  ReportTable animals() {
    final e = engine;
    final milk = e.milkByAnimal;
    final units = e.unitProfits.where((p) => p.unit.kind == UnitKind.animal).toList()..sort((a, b) => b.profit.compareTo(a.profit));
    final rows = <List<String>>[];
    final ids = <String?>[];
    for (final p in units) {
      final a = e.recordOf(p.unit)!;
      final litres = milk[p.unit] ?? 0;
      final growth = CowAnalytics(farm, a, today: filter.to).averageDailyGain;
      rows.add([
        p.label,
        p.species,
        n1(litres),
        n0(p.revenue),
        n0(p.cost(FinanceEngine.catFeed)),
        n0(p.cost(FinanceEngine.catTreatment) + p.cost(FinanceEngine.catBreeding)),
        n0(p.directCost - p.cost(FinanceEngine.catFeed) - p.cost(FinanceEngine.catTreatment) - p.cost(FinanceEngine.catBreeding) - p.cost(FinanceEngine.catDisposal)),
        n0(p.allocatedCost),
        n0(p.profit + p.cost(FinanceEngine.catDisposal)),
        n0(e.periodDays == 0 ? 0 : p.cost(FinanceEngine.catFeed) / e.periodDays),
        litres > 0 ? n2(e.productionCost(p) / litres) : '',
        growth == null ? '' : n0(growth * 1000),
        n0(a.number('purchasePrice')),
        n0(_disposalProceeds(a)),
      ]);
      ids.add(a.id);
    }
    return ReportTable(
      title: ReportKind.animals.label,
      columns: [
        'Animal',
        'Species',
        'Milk (L)',
        'Revenue',
        'Feed',
        'Health & breeding',
        'Other direct',
        'Shared (allocated)',
        'Operating profit',
        'Feed per day',
        'Cost per litre',
        'Daily gain (g)',
        'Purchase price',
        'Sale proceeds'
      ],
      rows: rows,
      numericFrom: 2,
      linkIds: ids,
      summary: [
        ('Animals', '${rows.length}'),
        ('Revenue', money(units.fold(0.0, (s, p) => s + p.revenue))),
        ('Operating profit', money(units.fold(0.0, (s, p) => s + p.profit + p.cost(FinanceEngine.catDisposal))))
      ],
      notes: [
        'Revenue counts sales of the animal itself and its share of unassigned sales (e.g. milk sold in bulk is shared by each cow’s saleable milk in the period).',
        'Operating profit excludes the animal’s purchase price; purchase price and sale proceeds are shown separately.',
        'Animals with no production show their running cost and growth instead of income.',
        'Shared costs are allocated by the method chosen on each farm-wide expense.',
      ],
    );
  }

  double _disposalProceeds(FarmRecord a) => farm.list(FarmModule.sales).where((s) => '${s['product']}' == 'Live animal' && a.isReferencedBy(s['animal'])).fold(0.0, (t, s) => t + s.number('amount'));

  ReportTable batches() {
    final e = engine;
    final rows = <List<String>>[];
    final ids = <String?>[];
    final profits = {for (final p in e.unitProfits) p.unit.key: p};
    for (final b in farm.list(FarmModule.batches)) {
      if (filter.batch != null && b.id != filter.batch) continue;
      if (filter.species != null && '${b['species']}' != filter.species) continue;
      if (filter.location != null && '${b['location']}' != filter.location) continue;
      final p = profits[UnitRef.batch(b.id).key];
      if (p == null) continue;
      final a = BatchAnalytics(farm, b, today: filter.to);
      final out = a.saleableOutput;
      rows.add([
        b.reference,
        '${b['species']}',
        '${b['status']}',
        n0(a.opening),
        n0(a.additions),
        n0(a.died),
        n0(a.soldHead + a.harvestedHead),
        n0(a.removedByMovement),
        n0(a.closing),
        n1(a.mortalityRate * 100),
        n0(p.cost(FinanceEngine.catStocking)),
        n0(p.cost(FinanceEngine.catFeed)),
        n0(p.cost(FinanceEngine.catTreatment)),
        n0(p.directCost - p.cost(FinanceEngine.catStocking) - p.cost(FinanceEngine.catFeed) - p.cost(FinanceEngine.catTreatment)),
        n0(p.allocatedCost),
        n0(p.totalCost),
        n0(p.revenue),
        n0(p.profit),
        out == null ? '' : '${n1(out.$1)} ${out.$2}',
        out == null || out.$1 == 0 ? '' : n2(e.productionCost(p) / out.$1),
        a.fcr == null ? '' : n2(a.fcr!),
      ]);
      ids.add(b.id);
    }
    return ReportTable(
      title: ReportKind.batches.label,
      columns: [
        'Batch',
        'Species',
        'Status',
        'Opening',
        'Added',
        'Died',
        'Sold/harvested',
        'Transferred/culled',
        'Closing',
        'Mortality %',
        'Stocking',
        'Feed',
        'Health',
        'Other direct',
        'Shared',
        'Total cost',
        'Revenue',
        'Operating profit',
        'Saleable output',
        'Cost per unit',
        'FCR'
      ],
      rows: rows,
      numericFrom: 3,
      linkIds: ids,
      notes: const [
        'Money columns cover the report period; head counts are as of the end date.',
        'Closing = opening + added − died − sold/harvested − transferred/culled.',
        'Cost per unit: eggs → per saleable egg; meat → per kg live weight sold; fish, shrimp and honey → per kg harvested.',
        'FCR = feed kg ÷ weight gained, where weight gained = current biomass (count × latest sample weight) + weight sold or harvested − opening weight.',
      ],
    );
  }

  ReportTable species() {
    final e = engine;
    final bySpecies = <String, (double, double, int)>{};
    for (final p in e.unitProfits) {
      final key = p.species.isEmpty ? 'Unspecified' : p.species;
      final prev = bySpecies[key] ?? (0.0, 0.0, 0);
      bySpecies[key] = (prev.$1 + p.revenue, prev.$2 + p.totalCost, prev.$3 + 1);
    }
    final pnl = e.profitAndLoss;
    final unitRevenue = bySpecies.values.fold(0.0, (s, v) => s + v.$1);
    final unitCost = bySpecies.values.fold(0.0, (s, v) => s + v.$2);
    final rows = [
      for (final s in (bySpecies.entries.toList()..sort((a, b) => (b.value.$1 - b.value.$2).compareTo(a.value.$1 - a.value.$2))))
        [s.key, '${s.value.$3}', n0(s.value.$1), n0(s.value.$2), n0(s.value.$1 - s.value.$2)],
      if ((pnl.revenue - unitRevenue).abs() > 0.5 || (pnl.costs - unitCost).abs() > 0.5)
        ['Farm-wide (not allocated)', '', n0(pnl.revenue - unitRevenue), n0(pnl.costs - unitCost), n0(pnl.revenue - unitRevenue - pnl.costs + unitCost)],
    ];
    return ReportTable(
      title: ReportKind.species.label,
      columns: ['Species', 'Animals / batches', 'Revenue', 'Costs', 'Operating profit'],
      rows: rows,
      numericFrom: 1,
      summary: [('Revenue', money(pnl.revenue)), ('Operating profit', money(pnl.operatingProfit))],
      notes: ['The farm-wide row holds overhead not allocated to any animal or batch, so species rows add up to the farm total.', ..._methodNotes],
    );
  }

  ReportTable costPerUnit() {
    final e = engine;
    final profits = {for (final p in e.unitProfits) p.unit: p};
    final rows = <List<String>>[];
    // Milk: all milking animals together.
    final milk = e.milkByAnimal;
    final litres = milk.values.fold(0.0, (s, v) => s + v);
    if (litres > 0) {
      final cost = milk.keys.fold(0.0, (s, u) => s + (profits[u] == null ? 0 : e.productionCost(profits[u]!)));
      rows.add(['Milk (all milking animals)', 'litre', n1(litres), n0(cost), n2(cost / litres)]);
      for (final u in milk.keys) {
        final p = profits[u];
        if (p == null || milk[u]! <= 0) continue;
        rows.add(['  ${p.label}', 'litre', n1(milk[u]!), n0(e.productionCost(p)), n2(e.productionCost(p) / milk[u]!)]);
      }
    }
    // Eggs: per laying batch.
    final eggs = e.productionOf('Eggs');
    for (final entry in eggs.entries) {
      final p = profits[entry.key];
      if (p == null || entry.value.$2 <= 0) continue;
      rows.add([p.label, 'saleable egg', n0(entry.value.$2), n0(e.productionCost(p)), n2(e.productionCost(p) / entry.value.$2)]);
    }
    // Meat sold live and harvests (kg).
    final live = e.liveSales;
    final harvest = <UnitRef, double>{};
    for (final product in const ['Fish', 'Shrimp', 'Meat', 'Honey']) {
      for (final entry in e.productionOf(product).entries) {
        harvest[entry.key] = (harvest[entry.key] ?? 0) + entry.value.$1;
      }
    }
    for (final u in {...live.keys, ...harvest.keys}) {
      final p = profits[u];
      if (p == null || u.kind != UnitKind.batch) continue;
      final kg = (live[u]?.$1 ?? 0) + (harvest[u] ?? 0);
      if (kg <= 0) continue;
      rows.add([p.label, live.containsKey(u) ? 'kg live weight sold' : 'kg harvested', n1(kg), n0(e.productionCost(p)), n2(e.productionCost(p) / kg)]);
    }
    // Fattening: each animal sold live in the period, per kg of its last
    // recorded live weight.
    for (final u in live.keys.where((u) => u.kind == UnitKind.animal)) {
      final p = profits[u];
      final kg = e.animal(u.id)?.number('weight') ?? 0;
      if (p == null || kg <= 0) continue;
      rows.add([p.label, 'kg live weight (last weighing)', n1(kg), n0(e.productionCost(p)), n2(e.productionCost(p) / kg)]);
    }
    return ReportTable(
      title: ReportKind.costPerUnit.label,
      columns: ['Product / source', 'Per', 'Quantity', 'Allocated cost (${profile.currency})', 'Cost per unit'],
      rows: rows,
      numericFrom: 2,
      notes: const [
        'Cost per litre = operating cost of the milking animals in the period (feed, health, breeding, direct and allocated shared costs) ÷ all milk they produced.',
        'Fattening: an animal sold live in the period — its operating cost in the period ÷ its last recorded live weight. Choose a period that covers the whole fattening for a full-cycle figure.',
        'The purchase price and book value of animals are not production costs and are excluded.',
      ],
    );
  }

  // ------------------------------------------------------- operational reports

  String _bucket(DateTime d) => switch (feedGrouping) {
        FeedGrouping.day => formatDate(d),
        FeedGrouping.week => () {
            final monday = d.subtract(Duration(days: d.weekday - 1));
            return 'Week of ${formatDate(monday)}';
          }(),
        FeedGrouping.month => '${d.year}-${d.month.toString().padLeft(2, '0')}',
        FeedGrouping.year => '${d.year}',
      };

  ReportTable feed() {
    final e = engine;
    final records = farm.inRange(FarmModule.feedRecords, filter.from, filter.to).where((f) {
      final u = e.unitOf(f);
      if (filter.animal != null && !(u?.kind == UnitKind.animal && u?.id == filter.animal)) return false;
      if (filter.batch != null && !(u?.kind == UnitKind.batch && u?.id == filter.batch)) return false;
      if (filter.species != null && '${f['species']}' != filter.species) return false;
      if (filter.location != null && e.locationOf(u) != filter.location) return false;
      return true;
    }).toList();
    final rows = <String, (double, double, int, Set<String>)>{};
    var totalKg = 0.0, totalCost = 0.0;
    for (final f in records) {
      final key = '${_bucket(f.dateOf('date')!)}|${f['species'] ?? ''}|${f['feed']}';
      final kg = Units.kg(f.number('qty'), '${f['unit']}') ?? 0;
      final cost = f.number('totalCost') > 0 ? f.number('totalCost') : f.number('qty') * f.number('unitPrice');
      final prev = rows[key] ?? (0.0, 0.0, 0, <String>{});
      final fed = '${f['animal']}'.isNotEmpty ? '${f['animal']}' : ('${f['batch']}'.isNotEmpty ? '${f['batch']}' : 'Group: ${f['group']}');
      rows[key] = (prev.$1 + kg, prev.$2 + cost, prev.$3 + 1, {...prev.$4, fed});
      totalKg += kg;
      totalCost += cost;
    }
    final keys = rows.keys.toList()..sort((a, b) => b.compareTo(a));
    return ReportTable(
      title: ReportKind.feed.label,
      columns: ['Period', 'Species', 'Feed item', 'Fed to', 'Entries', 'Quantity (kg)', 'Cost (${profile.currency})'],
      rows: [
        for (final k in keys)
          () {
            final parts = k.split('|');
            final v = rows[k]!;
            return [parts[0], parts[1], parts[2], '${v.$4.length}', '${v.$3}', n1(v.$1), n0(v.$2)];
          }(),
      ],
      numericFrom: 3,
      summary: [('Feed fed', '${n1(totalKg)} kg'), ('Feed cost', money(totalCost)), ('Per day', '${n1(totalKg / e.periodDays)} kg · ${money(totalCost / e.periodDays)}')],
      notes: const [
        'Quantities in g are converted to kg; feed recorded in litres or pieces is costed but not included in kg totals.',
        'Group rations count once here; in animal reports they are shared equally between the animals in the group.'
      ],
    );
  }

  ReportTable productionReport() {
    final rows = <List<String>>[];
    final from = filter.from, to = filter.to;
    bool keepProduct(String p) => filter.product == null || filter.product == p;
    if (keepProduct('Milk')) {
      final milk = farm.inRange(FarmModule.milkProduction, from, to).where((m) => filter.animal == null || FarmRecord.refId(m['animal']) == filter.animal!.toLowerCase());
      final total = milk.fold(0.0, (s, m) => s + m.number('litres'));
      final saleable = milk.where(FarmController.isSellableMilk).fold(0.0, (s, m) => s + m.number('litres'));
      final sold = _sold('Milk', from, to);
      final used = _used('Milk', from, to);
      rows.add(['Milk', 'L', n1(total), n1(saleable), n1(total - saleable), n1(sold), n1(used), n1(farm.productStock('Milk', asOf: to))]);
    }
    for (final product in FarmModule.products.where((p) => p != 'Milk' && keepProduct(p))) {
      final recs = farm.inRange(FarmModule.production, from, to).where((p) => '${p['product']}' == product && (filter.batch == null || FarmRecord.refId(p['batch']) == filter.batch!.toLowerCase()));
      if (recs.isEmpty && _sold(product, from, to) == 0) continue;
      final unit = Units.baseOf(FarmModule.defaultProductUnit[product] ?? 'pcs');
      final total = recs.fold(0.0, (s, p) => s + Units.toBase(p.number('quantity'), '${p['unit']}'));
      final saleable = recs.fold(0.0, (s, p) => s + Units.toBase(FarmController.saleableOf(p), '${p['unit']}'));
      final stocked = FarmController.stockedProducts.contains(product);
      rows.add([product, unit, n1(total), n1(saleable), n1(total - saleable), n1(_sold(product, from, to)), n1(_used(product, from, to)), stocked ? n1(farm.productStock(product, asOf: to)) : '']);
    }
    // Laying rate per egg batch.
    final notes = <String>[
      'Unsold stock is cumulative up to the end date: saleable production − sold − used. Withheld or rejected milk is never saleable.',
    ];
    for (final b in farm.list(FarmModule.batches).where((b) => '${b['purpose']}' == 'Eggs')) {
      final rate = BatchAnalytics(farm, b, today: to).layingRate;
      if (rate != null) notes.add('${b.reference}: average laying rate ${n1(rate)}% (eggs ÷ hens alive each day).');
    }
    return ReportTable(
      title: ReportKind.production.label,
      columns: ['Product', 'Unit', 'Produced', 'Saleable', 'Not saleable', 'Sold', 'Used / wasted', 'Unsold stock now'],
      rows: rows,
      numericFrom: 2,
      notes: notes,
    );
  }

  double _sold(String product, DateTime from, DateTime to) =>
      farm.inRange(FarmModule.sales, from, to).where((s) => '${s['product']}' == product).fold(0.0, (t, s) => t + Units.toBase(s.number('qty'), '${s['unit']}'));
  double _used(String product, DateTime from, DateTime to) =>
      farm.inRange(FarmModule.productUsage, from, to).where((s) => '${s['product']}' == product).fold(0.0, (t, s) => t + Units.toBase(s.number('quantity'), '${s['unit']}'));

  ReportTable mortality() {
    final rows = <List<String>>[];
    final ids = <String?>[];
    for (final b in farm.list(FarmModule.batches)) {
      if (filter.batch != null && b.id != filter.batch) continue;
      if (filter.species != null && '${b['species']}' != filter.species) continue;
      final a = BatchAnalytics(farm, b, today: filter.to);
      final inPeriod = farm.inRange(FarmModule.mortality, filter.from, filter.to).where((m) => b.isReferencedBy(m['batch'])).fold(0.0, (s, m) => s + m.number('count'));
      final causes = <String, double>{};
      for (final m in farm.inRange(FarmModule.mortality, filter.from, filter.to).where((m) => b.isReferencedBy(m['batch']))) {
        causes['${m['cause']}'] = (causes['${m['cause']}'] ?? 0) + m.number('count');
      }
      rows.add(
          [b.reference, '${b['species']}', n0(inPeriod), n0(a.died), n1(a.mortalityRate * 100), n1(a.recentMortalityRate(7) * 100), causes.entries.map((c) => '${c.key} ${n0(c.value)}').join(', ')]);
      ids.add(b.id);
    }
    final animalDeaths = farm.inRange(FarmModule.mortality, filter.from, filter.to).where((m) => '${m['animal'] ?? ''}'.isNotEmpty).toList();
    for (final m in animalDeaths) {
      rows.add(['${m['animal']}', '${farm.resolve(FarmModule.animals, m['animal'])?['species'] ?? ''}', '1', '1', '', '', '${m['cause']} (${m['date']})']);
      ids.add(FarmRecord.refId(m['animal']).toUpperCase());
    }
    return ReportTable(
      title: ReportKind.mortality.label,
      columns: ['Animal', 'Species', 'Deaths in period', 'Deaths to date', 'Mortality % to date', 'Last 7 days %', 'Causes in period'],
      rows: rows,
      numericFrom: 2,
      linkIds: ids,
      notes: ['Alert threshold: more than ${formatQty(profile.mortalityAlertPercent)}% of a batch lost in 7 days (set in Calculation settings).'],
    );
  }

  ReportTable salesReport() {
    final sales = farm.inRange(FarmModule.sales, filter.from, filter.to).where((s) => filter.product == null || '${s['product']}' == filter.product).toList()
      ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    final rows = [
      for (final s in sales)
        [
          s.id,
          '${s['date']}',
          '${s['product']}',
          '${s['customer']}',
          '${s['qty']} ${s['unit']}',
          n0(s.number('gross')),
          n0(s.number('discount') + s.number('deductions')),
          n0(s.number('amount')),
          n0(s.number('paid')),
          n0(s.number('due')),
          '${s['status']}'
        ],
    ];
    final outstanding = <String, double>{};
    for (final s in farm.list(FarmModule.sales)) {
      if (s.number('due') > 0.005) outstanding['${s['customer']}'] = (outstanding['${s['customer']}'] ?? 0) + s.number('due');
    }
    final collections = farm.inRange(FarmModule.collections, filter.from, filter.to).fold(0.0, (t, c) => t + c.number('amount'));
    return ReportTable(
      title: ReportKind.sales.label,
      columns: ['Sale', 'Date', 'Product', 'Customer', 'Quantity', 'Gross', 'Discount & deductions', 'Net sales', 'Received', 'Outstanding', 'Status'],
      rows: rows,
      numericFrom: 5,
      summary: [
        ('Net sales', money(sales.fold(0.0, (t, s) => t + s.number('amount')))),
        ('Payments received in period', money(collections)),
        ('Outstanding (all time)', money(outstanding.values.fold(0.0, (a, b) => a + b))),
      ],
      notes: [
        'Net sales = gross − discount − sales deductions. Received = paid at sale + later payments.',
        if (outstanding.isNotEmpty) 'Outstanding by customer: ${outstanding.entries.map((e) => '${e.key} ${money(e.value)}').join('; ')}.',
      ],
    );
  }

  ReportTable expensive() {
    final e = engine;
    final units = e.unitProfits.toList()..sort((a, b) => b.totalCost.compareTo(a.totalCost));
    return ReportTable(
      title: ReportKind.expensive.label,
      columns: ['Animal', 'Species', 'Total cost', 'Feed', 'Health & breeding', 'Shared', 'Cost per day', 'Revenue'],
      rows: [
        for (final p in units)
          [
            p.label,
            p.species,
            n0(p.totalCost),
            n0(p.cost(FinanceEngine.catFeed)),
            n0(p.cost(FinanceEngine.catTreatment) + p.cost(FinanceEngine.catBreeding)),
            n0(p.allocatedCost),
            n0(p.totalCost / e.periodDays),
            n0(p.revenue)
          ],
      ],
      numericFrom: 2,
      linkIds: [for (final p in units) p.unit.id],
      notes: const ['Ranked by total operating cost in the period, including allocated shared costs.'],
    );
  }

  ReportTable breeding() {
    final herd = HerdAnalytics(farm, today: filter.to);
    final b = herd.breeding;
    final rows = [
      for (final cow in herd.cows)
        () {
          final a = herd.of(cow);
          return [
            cow.reference,
            '${cow['species']}',
            '${a.services.length}',
            a.avgServicesPerConception == null ? '' : n1(a.avgServicesPerConception!),
            a.expectedCalving == null ? '' : formatDate(a.expectedCalving!),
            a.reproStatus
          ];
        }(),
    ];
    String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';
    return ReportTable(
      title: ReportKind.breeding.label,
      columns: ['Animal', 'Species', 'Services', 'Services per conception', 'Expected calving', 'Status'],
      rows: rows,
      numericFrom: 2,
      linkIds: [for (final c in herd.cows) c.id],
      summary: [('Conception rate', pct(b.conceptionRate)), ('Services per conception', b.servicesPerConception?.toStringAsFixed(1) ?? '—'), ('Confirmed pregnant', '${b.pregnant}')],
      notes: const ['Expected calving dates are estimates (service date + 283 days for cattle).'],
    );
  }

  ReportTable healthSchedule() {
    final rows = <List<String>>[];
    final t = today;
    final horizon = t.add(const Duration(days: 30));
    final items = farm.list(FarmModule.health).where((h) {
      final next = h.dateOf('next') ?? (h.status == 'Scheduled' ? h.dateOf('date') : null);
      return next != null && !next.isAfter(horizon) && (h.status != 'Completed' || !next.isBefore(t));
    }).toList()
      ..sort((a, b) => '${a['next']}'.compareTo('${b['next']}'));
    for (final h in items) {
      final next = h.dateOf('next') ?? h.dateOf('date')!;
      final days = daysBetween(t, next);
      final who = '${h['animal'] ?? ''}'.isNotEmpty ? '${h['animal']}' : '${h['batch']}';
      rows.add([formatDate(next), days < 0 ? 'Overdue ${-days} d' : (days == 0 ? 'Today' : 'In $days d'), who, '${h['type']}', '${h['details']}', h.status]);
    }
    return ReportTable(
      title: ReportKind.health.label,
      columns: ['Due', 'When', 'Animal', 'Type', 'Details', 'Status'],
      rows: rows,
      numericFrom: 99,
      notes: const ['Shows overdue items and everything due in the next 30 days. The app records schedules only — it never prescribes medicines or doses.'],
    );
  }

  ReportTable inventory() {
    final items = farm.list(FarmModule.inventory);
    final rows = [
      for (final i in items) [i.reference, '${i['category']}', '${i['qty']} ${i['unit']}', '${i['reorder']}', n2(i.number('unitCost')), n0(i.number('qty') * i.number('unitCost')), i.status],
    ];
    return ReportTable(
      title: ReportKind.inventory.label,
      columns: ['Item', 'Category', 'In stock', 'Reorder level', 'Cost per unit', 'Stock value', 'Status'],
      rows: rows,
      numericFrom: 4,
      summary: [('Stock value', money(items.fold(0.0, (s, i) => s + i.number('qty') * i.number('unitCost')))), ('Low or out of stock', '${items.where((i) => i.isLowStock).length}')],
      notes: const ['Stock value = quantity × current cost per unit (the latest purchase price).'],
    );
  }

  /// Raw records of one module in the date range (all records if it has no date).
  ReportTable records(String module) {
    final all = farm.list(module);
    final dated = all.any((r) => r.dateOf('date') != null);
    final rows = dated ? farm.inRange(module, filter.from, filter.to) : all;
    final headers = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!headers.contains(k) && !FarmModule.isInternal(k)) headers.add(k);
      }
    }
    return ReportTable(
      title: '$module records',
      columns: headers,
      rows: [
        for (final r in rows) [for (final h in headers) '${r[h] ?? ''}']
      ],
      numericFrom: 99,
      notes: [dated ? '${rows.length} of ${all.length} records fall in the selected dates.' : 'This module has no dates — all ${all.length} records are exported.'],
    );
  }

  /// CSV text for [module] (all records), or null when it has none.
  String? buildCsv(String module) {
    if (farm.list(module).isEmpty) return null;
    final saved = filter;
    filter = filter.copyWith(from: DateTime(1900), to: DateTime(2200));
    final csv = records(module).toCsv();
    filter = saved;
    return csv;
  }
}
