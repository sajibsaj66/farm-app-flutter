/// Value objects produced by the finance engine. No UI or storage logic here.
library;

/// What a report covers.
class ReportFilter {
  const ReportFilter({required this.from, required this.to, this.species, this.animal, this.batch, this.location, this.product});

  final DateTime from;
  final DateTime to;

  /// Species name (e.g. "Cattle", "Layer chicken").
  final String? species;

  /// Animal id (e.g. "AN-1001").
  final String? animal;

  /// Batch id (e.g. "BT-01").
  final String? batch;

  /// Location name (e.g. "Shed A").
  final String? location;

  /// Product (e.g. "Milk", "Eggs").
  final String? product;

  bool get hasUnitFilter => species != null || animal != null || batch != null || location != null || product != null;

  ReportFilter copyWith(
          {DateTime? from,
          DateTime? to,
          String? species,
          String? animal,
          String? batch,
          String? location,
          String? product,
          bool clearSpecies = false,
          bool clearAnimal = false,
          bool clearBatch = false,
          bool clearLocation = false,
          bool clearProduct = false}) =>
      ReportFilter(
        from: from ?? this.from,
        to: to ?? this.to,
        species: clearSpecies ? null : species ?? this.species,
        animal: clearAnimal ? null : animal ?? this.animal,
        batch: clearBatch ? null : batch ?? this.batch,
        location: clearLocation ? null : location ?? this.location,
        product: clearProduct ? null : product ?? this.product,
      );

  String get description {
    final parts = <String>[
      if (species != null) 'species $species',
      if (animal != null) 'animal $animal',
      if (batch != null) 'batch $batch',
      if (location != null) 'location $location',
      if (product != null) 'product $product',
    ];
    return parts.isEmpty ? 'whole farm' : parts.join(', ');
  }
}

/// Where a cost or revenue belongs: an animal, a batch, or the farm as a whole.
class UnitRef {
  const UnitRef.animal(this.id) : kind = UnitKind.animal;
  const UnitRef.batch(this.id) : kind = UnitKind.batch;

  final UnitKind kind;
  final String id;

  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) => other is UnitRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

enum UnitKind { animal, batch }

/// One recognised cost in profit and loss.
class CostLine {
  const CostLine({required this.date, required this.category, required this.amount, required this.source, this.unit, this.species = '', this.location = '', this.allocation});

  final DateTime date;

  /// Report heading, e.g. "Feed consumed", "Labour and salaries".
  final String category;
  final double amount;

  /// Record id that produced the line (for audit).
  final String source;
  final UnitRef? unit;
  final String species;
  final String location;

  /// Set when a farm-wide cost was shared out; the allocation method.
  final String? allocation;

  CostLine withUnit(UnitRef u, double amount, String species, String location, String allocation) =>
      CostLine(date: date, category: category, amount: amount, source: source, unit: u, species: species, location: location, allocation: allocation);
}

/// One recognised revenue (net sales) line.
class RevenueLine {
  const RevenueLine({required this.date, required this.product, required this.amount, required this.source, this.unit, this.species = '', this.location = '', this.shared = false});

  final DateTime date;
  final String product;
  final double amount;
  final String source;
  final UnitRef? unit;
  final String species;
  final String location;

  /// True when a sale without a named animal/batch was shared between the
  /// producing animals/batches by their share of production.
  final bool shared;
}

/// One actual cash movement (positive in, negative out).
class CashLine {
  const CashLine({required this.date, required this.category, required this.amount, required this.source});

  final DateTime date;
  final String category;
  final double amount;
  final String source;
}

/// Profit and loss for one animal or batch over the report period.
class UnitProfit {
  UnitProfit({required this.unit, required this.label, required this.species, required this.location});

  final UnitRef unit;
  final String label;
  final String species;
  final String location;
  double revenue = 0;
  final Map<String, double> costs = {};
  final Map<String, double> allocatedByMethod = {};

  double get directCost => costs.entries.where((e) => !e.key.startsWith('Allocated:')).fold(0.0, (s, e) => s + e.value);
  double get allocatedCost => allocatedByMethod.values.fold(0.0, (s, v) => s + v);
  double get totalCost => costs.values.fold(0.0, (s, v) => s + v);
  double get profit => revenue - totalCost;
  double cost(String category) => costs[category] ?? 0;
}

/// Profit and loss for a period.
class ProfitAndLoss {
  const ProfitAndLoss({required this.revenueByProduct, required this.costsByCategory, required this.excludedOverhead});

  final Map<String, double> revenueByProduct;
  final Map<String, double> costsByCategory;

  /// Farm-wide costs left out because the report is filtered to some
  /// animals/batches and those costs were not allocated.
  final double excludedOverhead;

  double get revenue => revenueByProduct.values.fold(0.0, (s, v) => s + v);
  double get costs => costsByCategory.values.fold(0.0, (s, v) => s + v);
  double get operatingProfit => revenue - costs;
}

/// One report as rows and columns, used both for the screen and for CSV so
/// both always show the same figures.
class ReportTable {
  const ReportTable({required this.title, required this.columns, required this.rows, this.notes = const [], this.summary = const [], this.numericFrom = 1, this.linkIds = const []});

  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  /// Assumptions and methods behind the figures.
  final List<String> notes;

  /// Headline figures shown above the rows: (label, value).
  final List<(String, String)> summary;

  /// Columns from this index on hold numbers.
  final int numericFrom;

  /// Optional per-row record id (animal or batch) for drill-down.
  final List<String?> linkIds;

  String toCsv() {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    return [
      columns.map(esc).join(','),
      ...rows.map((r) => r.map(esc).join(',')),
    ].join('\n');
  }
}
