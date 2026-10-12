import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/farm_module.dart';
import '../models/farm_profile.dart';
import '../models/farm_record.dart';
import '../models/finance.dart';
import 'farm_controller.dart';

/// Turns farm records into recognised revenue, costs and cash for a period.
///
/// Accounting model (documented in README and shown as report notes):
/// * Revenue = net sales (gross − discount − deductions) on the sale date.
///   Sales without a named animal/batch are shared between the producing
///   animals/batches by their share of production in the period.
/// * Feed cost = quantity × unit price on the feed record (consumption basis),
///   or Feed expenses plus manual feed records (purchase basis) — never both.
/// * Treatment (health records), breeding (service + semen straw), batch
///   stocking and batch purchases are direct costs of their animal/batch.
/// * Expenses are direct when charged to an animal, batch or location; a
///   farm-wide expense is shared by its allocation method, or left as farm
///   overhead.
/// * An animal's purchase price is an asset. It is charged only as optional
///   straight-line depreciation and as book value when the animal is sold or
///   dies — never against every day's profit.
/// * Cash flow is separate: money actually received and paid.
class FinanceEngine {
  FinanceEngine(this.farm, this.filter) : profile = farm.profile;

  final FarmController farm;
  final ReportFilter filter;
  final FarmProfile profile;

  static const catFeed = 'Feed consumed';
  static const catFeedPurchases = 'Feed purchases (expenses)';
  static const catWastage = 'Feed wastage';
  static const catTreatment = 'Treatment, vaccination & vet fees';
  static const catBreeding = 'Breeding (service & semen)';
  static const catStocking = 'Birds, fish & colonies stocked';
  static const catDepreciation = 'Depreciation of animals';
  static const catDisposal = 'Book value of animals sold or lost';
  static const catAllocated = 'Allocated shared costs';

  DateTime get from => dateOnly(filter.from);
  DateTime get to => dateOnly(filter.to);

  bool _inRange(DateTime? d) => d != null && !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);

  int get periodDays => daysBetween(from, to) + 1;

  // ---------------------------------------------------------------- units

  FarmRecord? animal(String id) => farm.find(FarmModule.animals, id);
  FarmRecord? batch(String id) => farm.find(FarmModule.batches, id);

  UnitRef? unitOf(FarmRecord r) {
    final a = farm.resolve(FarmModule.animals, r['animal']);
    if (a != null) return UnitRef.animal(a.id);
    final b = farm.resolve(FarmModule.batches, r['batch']);
    if (b != null) return UnitRef.batch(b.id);
    return null;
  }

  FarmRecord? recordOf(UnitRef u) => u.kind == UnitKind.animal ? animal(u.id) : batch(u.id);

  String speciesOf(UnitRef? u) => u == null ? '' : '${recordOf(u)?['species'] ?? ''}';
  String locationOf(UnitRef? u) => u == null ? '' : '${recordOf(u)?['location'] ?? ''}';

  String labelOf(UnitRef u) {
    final r = recordOf(u);
    return r == null ? u.id : '${r.id} · ${r['name']}';
  }

  /// When an animal left the farm (sold or died), if recorded.
  DateTime? disposalDate(FarmRecord a) {
    DateTime? d;
    for (final s in farm.list(FarmModule.sales)) {
      if ('${s['product']}' == 'Live animal' && a.isReferencedBy(s['animal'])) d = s.dateOf('date');
    }
    for (final m in farm.list(FarmModule.mortality)) {
      if (a.isReferencedBy(m['animal'])) d = m.dateOf('date');
    }
    return d;
  }

  /// Animals and batches that existed during the period.
  late final List<UnitRef> activeUnits = [
    for (final a in farm.list(FarmModule.animals))
      if (_existed(a.dateOf('purchaseDate') ?? a.dateOf('dob'), FarmController.isActive(a) ? null : disposalDate(a), alwaysIfUnknownEnd: FarmController.isActive(a))) UnitRef.animal(a.id),
    for (final b in farm.list(FarmModule.batches))
      if (_existed(b.dateOf('startDate'), b.dateOf('closeDate'), alwaysIfUnknownEnd: true)) UnitRef.batch(b.id),
  ];

  bool _existed(DateTime? start, DateTime? end, {required bool alwaysIfUnknownEnd}) {
    if (start != null && dateOnly(start).isAfter(to)) return false;
    if (end == null) return alwaysIfUnknownEnd;
    return !dateOnly(end).isBefore(from);
  }

  // --------------------------------------------------------------- revenue

  late final List<RevenueLine> _revenueAll = _buildRevenue();

  List<RevenueLine> _buildRevenue() {
    final out = <RevenueLine>[];
    for (final s in farm.inRange(FarmModule.sales, from, to)) {
      final amount = s.number('amount');
      final product = '${s['product']}';
      final date = s.dateOf('date')!;
      final u = unitOf(s);
      if (u != null) {
        out.add(RevenueLine(date: date, product: product, amount: amount, source: s.id, unit: u, species: speciesOf(u), location: locationOf(u)));
        continue;
      }
      final producers = producersOf(product);
      final total = producers.values.fold(0.0, (a, b) => a + b);
      if (total <= 0) {
        out.add(RevenueLine(date: date, product: product, amount: amount, source: s.id));
        continue;
      }
      for (final e in producers.entries) {
        out.add(RevenueLine(date: date, product: product, amount: amount * e.value / total, source: s.id, unit: e.key, species: speciesOf(e.key), location: locationOf(e.key), shared: true));
      }
    }
    return out;
  }

  /// Saleable production of [product] in the period, per animal/batch.
  Map<UnitRef, double> producersOf(String product) {
    final out = <UnitRef, double>{};
    if (product == 'Milk') {
      for (final m in farm.inRange(FarmModule.milkProduction, from, to)) {
        if (!FarmController.isSellableMilk(m)) continue;
        final u = unitOf(m);
        if (u != null) out[u] = (out[u] ?? 0) + m.number('litres');
      }
      return out;
    }
    for (final p in farm.inRange(FarmModule.production, from, to)) {
      if ('${p['product']}' != product) continue;
      final u = unitOf(p);
      if (u != null) out[u] = (out[u] ?? 0) + Units.toBase(FarmController.saleableOf(p), '${p['unit']}');
    }
    return out;
  }

  // ----------------------------------------------------------------- costs

  late final List<CostLine> _directCosts = _buildDirectCosts();
  late final List<CostLine> _costsAll = [..._directCosts, ..._allocate()];

  /// Farm-wide expenses waiting to be shared: (line, allocation method).
  final List<(CostLine, String)> _toAllocate = [];

  double _feedCost(FarmRecord f) {
    final total = f.number('totalCost');
    return total > 0 ? total : f.number('qty') * f.number('unitPrice');
  }

  List<CostLine> _buildDirectCosts() {
    final out = <CostLine>[];
    void add(DateTime date, String category, double amount, String source, UnitRef? u, {String location = ''}) {
      if (amount == 0) return;
      out.add(CostLine(date: date, category: category, amount: amount, source: source, unit: u, species: speciesOf(u), location: u == null ? location : locationOf(u)));
    }

    final consumption = profile.feedCostBasis == FeedCostBasis.consumption;

    // Feed.
    for (final f in farm.inRange(FarmModule.feedRecords, from, to)) {
      final manual = '${f['source']}' == FarmModule.manualExpense;
      if (!consumption && !manual) continue;
      final date = f.dateOf('date')!;
      final cost = _feedCost(f);
      final u = unitOf(f);
      if (u != null) {
        add(date, catFeed, cost, f.id, u);
        continue;
      }
      final mates = groupMembers('${f['group']}');
      if (mates.isEmpty) {
        out.add(CostLine(date: date, category: catFeed, amount: cost, source: f.id, species: '${f['species'] ?? ''}'));
      } else {
        for (final m in mates) {
          add(date, catFeed, cost / mates.length, f.id, UnitRef.animal(m.id));
        }
      }
    }
    if (consumption) {
      for (final t in farm.inRange(FarmModule.inventoryTx, from, to)) {
        if ('${t['type']}' != FarmModule.txWastage) continue;
        final item = farm.feedItem(t['item']);
        if (item == null || '${item['category']}' != 'Feed') continue;
        final unitCost = t.number('unitCost') > 0 ? t.number('unitCost') : item.number('unitCost');
        add(t.dateOf('date')!, catWastage, t.number('quantity') * unitCost, t.id, null);
      }
    }

    // Health and breeding.
    for (final h in farm.inRange(FarmModule.health, from, to)) {
      add(h.dateOf('date')!, catTreatment, h.number('cost'), h.id, unitOf(h));
    }
    // Illness care: treatment plan costs and consultation fees. Medicine taken
    // from stock is not costed again (its purchase is an expense).
    for (final t in farm.inRange(FarmModule.treatments, from, to, field: 'startDate')) {
      add(t.dateOf('startDate')!, catTreatment, t.number('cost'), t.id, unitOf(t));
    }
    for (final c in farm.inRange(FarmModule.consultations, from, to)) {
      add(c.dateOf('date')!, catTreatment, c.number('fee'), c.id, unitOf(c));
    }
    for (final s in farm.inRange(FarmModule.breeding, from, to)) {
      final straw = '${s['method']}' == 'Natural mating' ? 0.0 : (farm.semenByCode(s['semen'])?.number('costPerStraw') ?? 0);
      add(s.dateOf('date')!, catBreeding, s.number('cost') + straw, s.id, unitOf(s));
    }

    // Batch stocking and purchased additions.
    for (final b in farm.list(FarmModule.batches)) {
      final start = b.dateOf('startDate');
      if (_inRange(start)) add(start!, catStocking, b.number('stockingCost'), b.id, UnitRef.batch(b.id));
    }
    for (final m in farm.inRange(FarmModule.batchMovements, from, to)) {
      add(m.dateOf('date')!, catStocking, m.number('cost'), m.id, unitOf(m));
    }

    // Animal asset cost: depreciation and book value at disposal.
    for (final a in farm.list(FarmModule.animals)) {
      final price = a.number('purchasePrice');
      if (price <= 0) continue;
      final u = UnitRef.animal(a.id);
      final disposed = disposalDate(a);
      final bought = a.dateOf('purchaseDate');
      if (profile.assetMethod == AssetMethod.depreciate && bought != null) {
        final perDay = price * (1 - profile.residualPercent / 100) / (profile.depreciationYears * 365);
        final fullyDepreciated = bought.add(Duration(days: (profile.depreciationYears * 365).round()));
        final start = dateOnly(bought).isAfter(from) ? dateOnly(bought) : from;
        var end = to;
        if (disposed != null && dateOnly(disposed).isBefore(end)) end = dateOnly(disposed);
        if (dateOnly(fullyDepreciated).isBefore(end)) end = dateOnly(fullyDepreciated);
        final days = daysBetween(start, end) + 1;
        if (days > 0) add(end, catDepreciation, perDay * days, a.id, u);
      }
      if (disposed != null && _inRange(disposed)) add(disposed, catDisposal, bookValue(a, disposed), a.id, u);
    }

    // Expenses.
    // Expenses waiting for (or refused) the owner's approval are not costs.
    for (final e in farm.inRange(FarmModule.expenses, from, to).where((e) => !FarmModule.awaitsOrRefused(e['approval']))) {
      final category = '${e['category']}';
      final date = e.dateOf('date')!;
      if (category == 'Feed' && consumption) continue; // stock bought — charged when fed
      final scope = '${e['scope'] ?? FarmModule.scopeFarm}';
      final amount = e.number('amount');
      if (scope == 'Animal' || scope == 'Batch') {
        add(date, category, amount, e.id, unitOf(e));
      } else if (scope == 'Location') {
        add(date, category, amount, e.id, null, location: '${e['location'] ?? ''}');
      } else {
        final line = CostLine(date: date, category: category, amount: amount, source: e.id);
        final method = '${e['allocation'] ?? ''}';
        if (method.isEmpty || method == FarmModule.allocNone) {
          out.add(line);
        } else {
          _toAllocate.add((line, method));
        }
      }
    }
    if (!consumption) {
      // Purchase basis: label feed expenses clearly.
      for (var i = 0; i < out.length; i++) {
        final l = out[i];
        if (l.category == 'Feed') out[i] = CostLine(date: l.date, category: catFeedPurchases, amount: l.amount, source: l.source, unit: l.unit, species: l.species, location: l.location);
      }
    }
    return out;
  }

  /// Animals currently in a feeding group (shares a group ration equally).
  List<FarmRecord> groupMembers(String group) {
    final g = group.trim().toLowerCase();
    if (g.isEmpty) return const [];
    return farm.list(FarmModule.animals).where((a) => FarmController.isActive(a) && '${a['group']}'.trim().toLowerCase() == g).toList();
  }

  /// Purchase price less depreciation charged up to [at].
  double bookValue(FarmRecord a, DateTime at) {
    final price = a.number('purchasePrice');
    final bought = a.dateOf('purchaseDate');
    if (profile.assetMethod != AssetMethod.depreciate || bought == null) return price;
    final perDay = price * (1 - profile.residualPercent / 100) / (profile.depreciationYears * 365);
    final maxDays = (profile.depreciationYears * 365).round();
    final days = daysBetween(bought, at).clamp(0, maxDays);
    return price - perDay * days;
  }

  List<CostLine> _allocate() {
    // _directCosts must be built first (it fills _toAllocate).
    final direct = _directCosts;
    final out = <CostLine>[];
    if (_toAllocate.isEmpty) return out;
    final feedByUnit = <UnitRef, double>{};
    for (final l in direct) {
      if (l.unit != null && l.category == catFeed) feedByUnit[l.unit!] = (feedByUnit[l.unit!] ?? 0) + l.amount;
    }
    final revenueByUnit = <UnitRef, double>{};
    for (final r in _revenueAll) {
      if (r.unit != null) revenueByUnit[r.unit!] = (revenueByUnit[r.unit!] ?? 0) + r.amount;
    }
    double weight(UnitRef u, String method) => switch (method) {
          FarmModule.allocEqual => 1,
          FarmModule.allocHead => u.kind == UnitKind.animal ? 1 : _batchHead(u.id),
          FarmModule.allocFeed => feedByUnit[u] ?? 0,
          FarmModule.allocProduction => revenueByUnit[u] ?? 0,
          _ => 0,
        };
    for (final (line, method) in _toAllocate) {
      final weights = {for (final u in activeUnits) u: weight(u, method)}..removeWhere((_, w) => w <= 0);
      final total = weights.values.fold(0.0, (a, b) => a + b);
      if (total <= 0) {
        out.add(line); // nothing to share it with — stays farm overhead
        continue;
      }
      for (final e in weights.entries) {
        out.add(line.withUnit(e.key, line.amount * e.value / total, speciesOf(e.key), locationOf(e.key), method));
      }
    }
    return out;
  }

  double _batchHead(String id) {
    final n = farm.batchCount(id, asOf: to);
    return n > 0 ? n : (batch(id)?.number('initialCount') ?? 0);
  }

  // ------------------------------------------------------------- filtering

  /// Animals/batches that produced the filter's product in the period.
  late final Set<UnitRef>? _productUnits = filter.product == null ? null : producersOf(filter.product!).keys.toSet();

  bool _unitMatches(UnitRef? u, String location) {
    if (!filter.hasUnitFilter) return true;
    if (u == null) {
      // Location-scoped costs match a location filter only.
      return filter.location != null && filter.species == null && filter.animal == null && filter.batch == null && filter.product == null && location == filter.location;
    }
    if (filter.animal != null && !(u.kind == UnitKind.animal && u.id == filter.animal)) return false;
    if (filter.batch != null && !(u.kind == UnitKind.batch && u.id == filter.batch)) return false;
    if (filter.species != null && speciesOf(u) != filter.species) return false;
    if (filter.location != null && locationOf(u) != filter.location) return false;
    final producing = _productUnits;
    if (producing != null && !producing.contains(u)) return false;
    return true;
  }

  List<CostLine> get costs => _costsAll.where((l) => _unitMatches(l.unit, l.location)).toList();

  List<RevenueLine> get revenue => _revenueAll.where((r) => _unitMatches(r.unit, r.location) && (filter.product == null || r.product == filter.product)).toList();

  // --------------------------------------------------------------- results

  ProfitAndLoss get profitAndLoss {
    final rev = <String, double>{};
    for (final r in revenue) {
      rev[r.product] = (rev[r.product] ?? 0) + r.amount;
    }
    final cost = <String, double>{};
    for (final c in costs) {
      cost[c.category] = (cost[c.category] ?? 0) + c.amount;
    }
    final excluded = filter.hasUnitFilter ? _costsAll.where((l) => l.unit == null && !_unitMatches(null, l.location)).fold(0.0, (s, l) => s + l.amount) : 0.0;
    return ProfitAndLoss(revenueByProduct: rev, costsByCategory: cost, excludedOverhead: excluded);
  }

  /// Profit per animal and batch (every unit active in the period appears,
  /// even with no revenue).
  List<UnitProfit> get unitProfits {
    final map = <UnitRef, UnitProfit>{};
    UnitProfit of(UnitRef u) => map.putIfAbsent(u, () => UnitProfit(unit: u, label: labelOf(u), species: speciesOf(u), location: locationOf(u)));
    for (final u in activeUnits) {
      if (_unitMatches(u, '')) of(u);
    }
    for (final r in revenue) {
      if (r.unit != null) of(r.unit!).revenue += r.amount;
    }
    for (final c in costs) {
      if (c.unit == null) continue;
      final p = of(c.unit!);
      final key = c.allocation == null ? c.category : catAllocated;
      p.costs[key] = (p.costs[key] ?? 0) + c.amount;
      if (c.allocation != null) p.allocatedByMethod[c.allocation!] = (p.allocatedByMethod[c.allocation!] ?? 0) + c.amount;
    }
    return map.values.toList();
  }

  /// Actual money in (positive) and out (negative) in the period.
  List<CashLine> get cashFlow {
    final out = <CashLine>[];
    bool keep(FarmRecord r) => !filter.hasUnitFilter || _unitMatches(unitOf(r), '${r['location'] ?? ''}');
    for (final s in farm.inRange(FarmModule.sales, from, to).where(keep)) {
      if (s.number('paidAtSale') > 0) out.add(CashLine(date: s.dateOf('date')!, category: 'Received at sale', amount: s.number('paidAtSale'), source: s.id));
    }
    for (final c in farm.inRange(FarmModule.collections, from, to)) {
      final sale = farm.resolve(FarmModule.sales, c['sale']);
      if (sale != null && !keep(sale)) continue;
      out.add(CashLine(date: c.dateOf('date')!, category: 'Payments received', amount: c.number('amount'), source: c.id));
    }
    for (final e in farm.inRange(FarmModule.expenses, from, to).where(keep).where((e) => !FarmModule.awaitsOrRefused(e['approval']))) {
      if ('${e['payment']}' == 'Due') continue;
      if (filter.hasUnitFilter && '${e['scope'] ?? FarmModule.scopeFarm}' == FarmModule.scopeFarm) continue;
      out.add(CashLine(date: e.dateOf('date')!, category: 'Expenses: ${e['category']}', amount: -e.number('amount'), source: e.id));
    }
    for (final f in farm.inRange(FarmModule.feedRecords, from, to).where(keep)) {
      if ('${f['source']}' == FarmModule.manualExpense) out.add(CashLine(date: f.dateOf('date')!, category: 'Feed bought for immediate use', amount: -_feedCost(f), source: f.id));
    }
    for (final h in farm.inRange(FarmModule.health, from, to).where(keep)) {
      if (h.number('cost') > 0) out.add(CashLine(date: h.dateOf('date')!, category: 'Treatment & vaccination', amount: -h.number('cost'), source: h.id));
    }
    for (final t in farm.inRange(FarmModule.treatments, from, to, field: 'startDate').where(keep)) {
      if (t.number('cost') > 0) out.add(CashLine(date: t.dateOf('startDate')!, category: 'Treatment & vaccination', amount: -t.number('cost'), source: t.id));
    }
    for (final c in farm.inRange(FarmModule.consultations, from, to).where(keep)) {
      if (c.number('fee') > 0) out.add(CashLine(date: c.dateOf('date')!, category: 'Veterinary consultations', amount: -c.number('fee'), source: c.id));
    }
    for (final s in farm.inRange(FarmModule.breeding, from, to).where(keep)) {
      if (s.number('cost') > 0) out.add(CashLine(date: s.dateOf('date')!, category: 'Breeding services', amount: -s.number('cost'), source: s.id));
    }
    for (final a in farm.list(FarmModule.animals).where(keep)) {
      final d = a.dateOf('purchaseDate');
      if (_inRange(d) && a.number('purchasePrice') > 0) out.add(CashLine(date: d!, category: 'Animals bought', amount: -a.number('purchasePrice'), source: a.id));
    }
    for (final b in farm.list(FarmModule.batches)) {
      if (filter.hasUnitFilter && !_unitMatches(UnitRef.batch(b.id), '')) continue;
      final d = b.dateOf('startDate');
      if (_inRange(d) && b.number('stockingCost') > 0) out.add(CashLine(date: d!, category: 'Birds, fish & colonies stocked', amount: -b.number('stockingCost'), source: b.id));
    }
    for (final m in farm.inRange(FarmModule.batchMovements, from, to).where(keep)) {
      if (m.number('cost') > 0) out.add(CashLine(date: m.dateOf('date')!, category: 'Birds, fish & colonies stocked', amount: -m.number('cost'), source: m.id));
    }
    return out;
  }

  double get cashIn => cashFlow.where((c) => c.amount > 0).fold(0.0, (s, c) => s + c.amount);
  double get cashOut => -cashFlow.where((c) => c.amount < 0).fold(0.0, (s, c) => s + c.amount);
  double get netCashFlow => cashIn - cashOut;

  /// Revenue, costs and cash per calendar month in the period.
  List<(String, double, double, double, double)> get monthly {
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final months = <String>[];
    for (var d = DateTime(from.year, from.month); !d.isAfter(to); d = DateTime(d.year, d.month + 1)) {
      months.add(key(d));
    }
    final rev = <String, double>{}, cost = <String, double>{}, cin = <String, double>{}, cout = <String, double>{};
    for (final r in revenue) {
      rev[key(r.date)] = (rev[key(r.date)] ?? 0) + r.amount;
    }
    for (final c in costs) {
      cost[key(c.date)] = (cost[key(c.date)] ?? 0) + c.amount;
    }
    for (final c in cashFlow) {
      if (c.amount > 0) {
        cin[key(c.date)] = (cin[key(c.date)] ?? 0) + c.amount;
      } else {
        cout[key(c.date)] = (cout[key(c.date)] ?? 0) - c.amount;
      }
    }
    return [for (final m in months) (m, rev[m] ?? 0, cost[m] ?? 0, cin[m] ?? 0, cout[m] ?? 0)];
  }

  // --------------------------------------------------------- production

  /// Milk produced in the period per animal (all litres, incl. withheld).
  Map<UnitRef, double> get milkByAnimal {
    final out = <UnitRef, double>{};
    for (final m in farm.inRange(FarmModule.milkProduction, from, to)) {
      final u = unitOf(m);
      if (u != null && _unitMatches(u, '')) out[u] = (out[u] ?? 0) + m.number('litres');
    }
    return out;
  }

  /// (total, saleable) of [product] produced in the period per unit, in base units.
  Map<UnitRef, (double, double)> productionOf(String product) {
    final out = <UnitRef, (double, double)>{};
    for (final p in farm.inRange(FarmModule.production, from, to)) {
      if ('${p['product']}' != product) continue;
      final u = unitOf(p);
      if (u == null || !_unitMatches(u, '')) continue;
      final prev = out[u] ?? (0.0, 0.0);
      out[u] = (prev.$1 + Units.toBase(p.number('quantity'), '${p['unit']}'), prev.$2 + Units.toBase(FarmController.saleableOf(p), '${p['unit']}'));
    }
    return out;
  }

  /// Live weight (kg) and head sold per batch in the period.
  Map<UnitRef, (double, double)> get liveSales {
    final out = <UnitRef, (double, double)>{};
    for (final s in farm.inRange(FarmModule.sales, from, to)) {
      if ('${s['product']}' != 'Live birds' && '${s['product']}' != 'Live animal') continue;
      final u = unitOf(s);
      if (u == null || !_unitMatches(u, '')) continue;
      final kg = Units.kg(s.number('qty'), '${s['unit']}') ?? 0;
      final prev = out[u] ?? (0.0, 0.0);
      out[u] = (prev.$1 + kg, prev.$2 + s.number('headCount'));
    }
    return out;
  }

  /// Operating cost of a unit for cost-per-unit figures (excludes the book
  /// value of animals disposed of, which is not a production cost).
  double productionCost(UnitProfit p) => p.totalCost - p.cost(catDisposal);
}
