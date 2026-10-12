import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import '../models/finance.dart';
import 'farm_controller.dart';
import 'finance_engine.dart';

/// Everything about one batch (flock, pond, hives) over its life so far.
class BatchAnalytics {
  BatchAnalytics(this.farm, this.batch, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final FarmRecord batch;
  final DateTime today;

  bool _mine(FarmRecord r) => batch.isReferencedBy(r['batch']);
  static int _byDate(FarmRecord a, FarmRecord b) => '${a['date']}'.compareTo('${b['date']}');

  DateTime get start => batch.dateOf('startDate') ?? today;

  /// End of the batch's life so far: its closing date, or today.
  DateTime get end {
    final closed = batch.dateOf('closeDate');
    return closed != null && closed.isBefore(today) ? dateOnly(closed) : today;
  }

  int get ageDays => daysBetween(start, end);

  String get unitName => '${batch['countUnit'] ?? ''}'.trim().isEmpty ? 'head' : '${batch['countUnit']}';

  String get purpose => '${batch['purpose'] ?? ''}';

  // Head count flow ----------------------------------------------------

  double get opening => batch.number('initialCount');

  List<FarmRecord> get movements => farm.list(FarmModule.batchMovements).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get deaths => farm.list(FarmModule.mortality).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get samples => farm.list(FarmModule.sampling).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get production => farm.list(FarmModule.production).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get sales => farm.list(FarmModule.sales).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get feed => farm.list(FarmModule.feedRecords).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get health => farm.list(FarmModule.health).where(_mine).toList()..sort(_byDate);

  double get additions => movements.where((m) => FarmModule.movementAdds.contains('${m['type']}')).fold(0.0, (s, m) => s + m.number('quantity'));
  double get removedByMovement => movements.where((m) => FarmModule.movementRemoves.contains('${m['type']}')).fold(0.0, (s, m) => s + m.number('quantity'));
  double get died => deaths.fold(0.0, (s, m) => s + m.number('count'));
  double get soldHead => sales.fold(0.0, (s, r) => s + r.number('headCount'));
  double get harvestedHead => production.fold(0.0, (s, r) => s + r.number('headCount'));
  double get closing => farm.batchCount(batch.reference, asOf: today);

  /// Deaths as a share of everything placed in the batch.
  double get mortalityRate {
    final placed = opening + additions;
    return placed <= 0 ? 0 : died / placed;
  }

  /// Deaths in the last [days] days as a share of the count at the start of
  /// that window.
  double recentMortalityRate(int days) {
    final from = today.subtract(Duration(days: days));
    final lost = deaths.where((d) => d.dateOf('date')?.isAfter(from) ?? false).fold(0.0, (s, d) => s + d.number('count'));
    final atStart = farm.batchCount(batch.reference, asOf: from);
    return atStart <= 0 ? 0 : lost / atStart;
  }

  // Weight and biomass --------------------------------------------------

  FarmRecord? get latestSample => samples.isEmpty ? null : samples.last;

  /// Latest sampled average weight in grams (or the opening weight).
  double? get avgWeightG {
    final s = latestSample;
    if (s != null) return s.number('avgWeight');
    final w = batch.number('initialAvgWeight');
    return w > 0 ? w : null;
  }

  /// Estimated live biomass now: head count × latest sample average.
  double? get biomassKg => avgWeightG == null ? null : closing * avgWeightG! / 1000;

  double get openingBiomassKg => opening * batch.number('initialAvgWeight') / 1000;

  String get biomassAssumption {
    final s = latestSample;
    if (s == null) return 'No sampling yet — biomass uses the opening average weight.';
    return 'Estimated as ${formatQty(closing)} $unitName × ${formatQty(s.number('avgWeight'))} g (sample of ${s['sampleSize']} on ${s['date']}).';
  }

  // Feed ---------------------------------------------------------------

  double get feedKg => feed.fold(0.0, (s, f) => s + (Units.kg(f.number('qty'), '${f['unit']}') ?? 0));

  double get feedCost => feed.fold(0.0, (s, f) => s + (f.number('totalCost') > 0 ? f.number('totalCost') : f.number('qty') * f.number('unitPrice')));

  // Production ---------------------------------------------------------

  double _produced(String product, {bool saleable = false}) =>
      production.where((p) => '${p['product']}' == product).fold(0.0, (s, p) => s + Units.toBase(saleable ? FarmController.saleableOf(p) : p.number('quantity'), '${p['unit']}'));

  double get eggs => _produced('Eggs');
  double get saleableEggs => _produced('Eggs', saleable: true);
  double get damagedEggs => production.where((p) => '${p['product']}' == 'Eggs').fold(0.0, (s, p) => s + Units.toBase(p.number('damaged'), '${p['unit']}'));

  /// Kilograms harvested (fish, shrimp, meat, honey…).
  double get harvestKg => production.where((p) => '${p['product']}' != 'Eggs').fold(0.0, (s, p) => s + (Units.kg(p.number('quantity'), '${p['unit']}') ?? 0));

  /// Live weight sold (kg) — e.g. broilers sold live.
  double get liveKgSold => sales.where((s) => '${s['product']}' == 'Live birds' || '${s['product']}' == 'Live animal').fold(0.0, (t, s) => t + (Units.kg(s.number('qty'), '${s['unit']}') ?? 0));

  /// Weight gained: what is there now plus what left (sold/harvested) minus
  /// what was placed. Null when no weight data exists.
  double? get weightGainKg {
    final now = biomassKg;
    if (now == null || latestSample == null) return null;
    return now + harvestKg + liveKgSold - openingBiomassKg;
  }

  /// Feed conversion ratio: kg of feed per kg of weight gained.
  double? get fcr {
    final gain = weightGainKg;
    if (gain == null || gain <= 0 || feedKg <= 0) return null;
    return feedKg / gain;
  }

  /// Average daily laying rate (%) on days with egg records.
  double? get layingRate {
    final eggRecords = production.where((p) => '${p['product']}' == 'Eggs').toList();
    if (eggRecords.isEmpty) return null;
    final byDay = <String, double>{};
    for (final p in eggRecords) {
      byDay['${p['date']}'] = (byDay['${p['date']}'] ?? 0) + Units.toBase(p.number('quantity'), '${p['unit']}');
    }
    final rates = <double>[];
    for (final e in byDay.entries) {
      final hens = farm.batchCount(batch.reference, asOf: FarmRecord.parseDate(e.key));
      if (hens > 0) rates.add(e.value / hens * 100);
    }
    return rates.isEmpty ? null : rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Daily eggs for the last [days] days (oldest first).
  List<(DateTime, double)> dailyEggs(int days) {
    final byDay = <String, double>{};
    for (final p in production.where((p) => '${p['product']}' == 'Eggs')) {
      byDay['${p['date']}'] = (byDay['${p['date']}'] ?? 0) + Units.toBase(p.number('quantity'), '${p['unit']}');
    }
    return [for (var i = days - 1; i >= 0; i--) (today.subtract(Duration(days: i)), byDay[formatDate(today.subtract(Duration(days: i)))] ?? 0)];
  }

  /// Unsold stock of this batch's products, in base units.
  Map<String, double> get unsold {
    final products = production.map((p) => '${p['product']}').where(FarmController.stockedProducts.contains).toSet();
    return {for (final p in products) p: farm.productStock(p, batchRef: batch.reference)};
  }

  // Money ---------------------------------------------------------------

  /// Profit and loss over the batch's whole life so far.
  late final FinanceEngine engine = FinanceEngine(farm, ReportFilter(from: start, to: end, batch: batch.id));

  late final UnitProfit profit = engine.unitProfits.firstWhere(
    (p) => p.unit.kind == UnitKind.batch && p.unit.id == batch.id,
    orElse: () => UnitProfit(unit: UnitRef.batch(batch.id), label: batch.reference, species: '${batch['species']}', location: '${batch['location']}'),
  );

  /// The output that costs are spread over, with its unit and label.
  (double, String, String)? get saleableOutput {
    switch (purpose) {
      case 'Eggs':
        return saleableEggs > 0 ? (saleableEggs, 'egg', 'Cost per saleable egg') : null;
      case 'Meat':
        final kg = liveKgSold + harvestKg;
        return kg > 0 ? (kg, 'kg', 'Cost per kg sold (live weight)') : null;
      case 'Grow-out (fish/shrimp)':
      case 'Honey':
        return harvestKg > 0 ? (harvestKg, 'kg', 'Cost per kg harvested') : null;
      default:
        return null;
    }
  }

  double? get costPerSaleableUnit {
    final out = saleableOutput;
    return out == null ? null : engine.productionCost(profit) / out.$1;
  }
}
