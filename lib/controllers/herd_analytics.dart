import 'package:flutter/material.dart';

import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/finance.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'farm_controller.dart';
import 'finance_engine.dart';

/// Reproduction constants used for reminders and estimates.
class Repro {
  Repro._();

  /// Average cattle gestation; expected calving dates are estimates.
  static const gestationDays = 283;

  /// Earliest day after service for a pregnancy diagnosis.
  static const pregnancyCheckDays = 35;

  /// Oestrus cycle length — when to watch for a repeat heat.
  static const heatCycleDays = 21;

  /// Typical voluntary waiting period before re-breeding after calving.
  static const waitingPeriodDays = 45;

  static bool isConception(String result) => result == FarmModule.resultPregnant || result == FarmModule.resultCalved;
}

/// Feed attributed to one animal: either fed to it directly, or its equal
/// share of a ration given to its whole group.
class FeedShare {
  const FeedShare({required this.date, required this.feed, required this.kg, required this.cost, required this.shared, required this.costKnown});

  final String date;
  final String feed;
  final double kg;
  final double cost;

  /// True when this is a share of a group ration.
  final bool shared;

  /// False when the feed item has no cost per unit in Inventory.
  final bool costKnown;
}

class DayPoint {
  const DayPoint(this.day, this.milk, this.feed);

  final DateTime day;
  final double milk;
  final double feed;
}

/// Totals for one animal over a period.
class CowPeriodStats {
  const CowPeriodStats({
    required this.days,
    required this.milk,
    required this.sellableMilk,
    required this.withheldMilk,
    required this.daysWithMilk,
    required this.feedKg,
    required this.feedCost,
    required this.feedCostIncomplete,
    required this.healthCost,
    required this.breedingCost,
    required this.milkPrice,
  });

  /// Period length in days, or null for all time.
  final int? days;
  final double milk;
  final double sellableMilk;
  final double withheldMilk;
  final int daysWithMilk;
  final double feedKg;
  final double feedCost;

  /// Some feed items have no cost per unit, so [feedCost] is a minimum.
  final bool feedCostIncomplete;
  final double healthCost;
  final double breedingCost;
  final double milkPrice;

  double get avgMilkPerDay => daysWithMilk == 0 ? 0 : milk / daysWithMilk;
  double? get feedPerLitre => milk <= 0 ? null : feedKg / milk;
  double? get feedCostPerLitre => milk <= 0 ? null : feedCost / milk;

  /// Estimated value of the saleable milk at the farm's milk price. This is an
  /// estimate only; actual revenue comes from recorded sales.
  double get milkIncome => sellableMilk * milkPrice;
  double get totalCost => feedCost + healthCost + breedingCost;
  double get margin => milkIncome - totalCost;
}

class TimelineEvent {
  const TimelineEvent({required this.date, required this.icon, required this.title, this.detail = ''});

  final String date;
  final IconData icon;
  final String title;
  final String detail;
}

/// Everything the app knows about one animal, worked out from all modules.
class CowAnalytics {
  CowAnalytics(this.farm, this.animal, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final FarmRecord animal;
  final DateTime today;

  bool _mine(FarmRecord r) => animal.isReferencedBy(r['animal']);

  static int _byDate(FarmRecord a, FarmRecord b) => '${a['date']}'.compareTo('${b['date']}');

  List<FarmRecord> get milkRecords => farm.list(FarmModule.milkProduction).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get healthRecords => farm.list(FarmModule.health).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get services => farm.list(FarmModule.breeding).where(_mine).toList()..sort(_byDate);
  List<FarmRecord> get weightRecords => farm.list(FarmModule.weights).where(_mine).toList()..sort(_byDate);

  // Identity --------------------------------------------------------------

  bool get isFemale => '${animal['sex']}'.toLowerCase() == 'female';

  String get group => '${animal['group'] ?? ''}';

  DateTime? get dob => animal.dateOf('dob');

  String get ageLabel {
    final born = dob;
    if (born == null) return '${animal['age'] ?? ''}'.trim().isEmpty ? 'Age unknown' : '${animal['age']}';
    final months = (today.year - born.year) * 12 + today.month - born.month - (today.day < born.day ? 1 : 0);
    if (months < 1) return '${daysBetween(born, today)} days';
    if (months < 24) return '$months months';
    return '${months ~/ 12} y ${months % 12} m';
  }

  FarmRecord? get dam => farm.resolve(FarmModule.animals, animal['dam']);

  List<FarmRecord> get offspring => farm.list(FarmModule.animals).where((a) => animal.isReferencedBy(a['dam'])).toList();

  // Feed --------------------------------------------------------------------

  static bool _inGroup(FarmRecord a, String group) {
    final status = '${a['status']}'.toLowerCase();
    final gone = status == 'sold' || status == 'dead' || status == 'transferred';
    return !gone && '${a['group']}'.trim().toLowerCase() == group.trim().toLowerCase();
  }

  /// Feed this animal received. Group rations are split equally between the
  /// animals currently in that group.
  List<FeedShare> get feedShares {
    final shares = <FeedShare>[];
    final groupSize = group.isEmpty ? 0 : farm.list(FarmModule.animals).where((a) => _inGroup(a, group)).length;
    for (final f in farm.list(FarmModule.feedRecords)) {
      final direct = _mine(f);
      final shared = !direct &&
          '${f['animal'] ?? ''}'.trim().isEmpty &&
          '${f['batch'] ?? ''}'.trim().isEmpty &&
          group.isNotEmpty &&
          groupSize > 0 &&
          '${f['group']}'.trim().toLowerCase() == group.trim().toLowerCase();
      if (!direct && !shared) continue;
      final share = shared ? groupSize : 1;
      // Weight in kg (feed in litres or pieces is costed but not weighed).
      final kg = (Units.kg(f.number('qty'), '${f['unit'] ?? 'kg'}') ?? 0) / share;
      final recorded = f.number('totalCost') > 0 ? f.number('totalCost') : f.number('qty') * f.number('unitPrice');
      final cost = recorded > 0 ? recorded : f.number('qty') * (farm.feedItem(f['feed'])?.number('unitCost') ?? 0);
      shares.add(FeedShare(date: '${f['date']}', feed: '${f['feed']}', kg: kg, cost: cost / share, shared: shared, costKnown: cost > 0));
    }
    return shares;
  }

  // Periods -------------------------------------------------------------------

  bool _inPeriod(dynamic date, int? days) {
    if (days == null) return true;
    final d = FarmRecord.parseDate(date);
    if (d == null) return false;
    final from = today.subtract(Duration(days: days - 1));
    return !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(today);
  }

  static bool isSellable(FarmRecord milk) {
    final q = '${milk['quality']}';
    return q != FarmModule.qualityWithheld && q != FarmModule.qualityRejected;
  }

  CowPeriodStats period(int? days) {
    final milk = milkRecords.where((m) => _inPeriod(m['date'], days)).toList();
    final total = milk.fold(0.0, (s, m) => s + m.number('litres'));
    final sellable = milk.where(isSellable).fold(0.0, (s, m) => s + m.number('litres'));
    final withheld = milk.where((m) => '${m['quality']}' == FarmModule.qualityWithheld).fold(0.0, (s, m) => s + m.number('litres'));
    final feed = feedShares.where((f) => _inPeriod(f.date, days)).toList();
    final semenCost = services.where((s) => _inPeriod(s['date'], days)).fold(0.0, (sum, s) {
      final straw = farm.semenByCode(s['semen'])?.number('costPerStraw') ?? 0;
      return sum + s.number('cost') + ('${s['method']}' == 'Natural mating' ? 0 : straw);
    });
    return CowPeriodStats(
      days: days,
      milk: total,
      sellableMilk: sellable,
      withheldMilk: withheld,
      daysWithMilk: milk.map((m) => '${m['date']}').toSet().length,
      feedKg: feed.fold(0.0, (s, f) => s + f.kg),
      feedCost: feed.fold(0.0, (s, f) => s + f.cost),
      feedCostIncomplete: feed.any((f) => !f.costKnown),
      healthCost: [
        ...healthRecords.where((h) => _inPeriod(h['date'], days)).map((h) => h.number('cost')),
        ...farm.list(FarmModule.treatments).where((t) => _mine(t) && _inPeriod(t['startDate'], days)).map((t) => t.number('cost')),
        ...farm.list(FarmModule.consultations).where((c) => _mine(c) && _inPeriod(c['date'], days)).map((c) => c.number('fee')),
      ].fold(0.0, (s, v) => s + v),
      breedingCost: semenCost,
      milkPrice: farm.profile.milkPrice,
    );
  }

  /// Milk (litres) and feed (kg) per day for the last [days] days, oldest first.
  List<DayPoint> daily(int days) {
    final milk = <String, double>{};
    for (final m in milkRecords) {
      milk['${m['date']}'] = (milk['${m['date']}'] ?? 0) + m.number('litres');
    }
    final feed = <String, double>{};
    for (final f in feedShares) {
      feed[f.date] = (feed[f.date] ?? 0) + f.kg;
    }
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = today.subtract(Duration(days: i));
          final key = formatDate(day);
          return DayPoint(day, milk[key] ?? 0, feed[key] ?? 0);
        }(),
    ];
  }

  /// Actual revenue (from sales) and operating costs, including allocated
  /// shared costs, from the finance engine.
  UnitProfit actualProfit(int? days) {
    final from = days == null ? (dob ?? animal.dateOf('purchaseDate') ?? DateTime(2000)) : today.subtract(Duration(days: days - 1));
    final engine = FinanceEngine(farm, ReportFilter(from: from, to: today, animal: animal.id));
    return engine.unitProfits.firstWhere((p) => p.unit.id == animal.id,
        orElse: () => UnitProfit(unit: UnitRef.animal(animal.id), label: animal.reference, species: '${animal['species']}', location: '${animal['location']}'));
  }

  // Reproduction -----------------------------------------------------------

  DateTime? get lastCalving {
    DateTime? latest;
    for (final s in services) {
      final d = s.dateOf('calvingDate');
      if (s.status == FarmModule.resultCalved && d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    for (final calf in offspring) {
      final d = calf.dateOf('dob');
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  bool get isMilking => milkRecords.any((m) => _inPeriod(m['date'], 7));

  int? get daysInMilk {
    final calved = lastCalving;
    return calved == null || !isMilking ? null : daysBetween(calved, today);
  }

  String? get lactationStage {
    final dim = daysInMilk;
    if (dim == null) return null;
    if (dim <= 100) return 'Early lactation';
    if (dim <= 200) return 'Mid lactation';
    if (dim <= 305) return 'Late lactation';
    return 'Extended lactation — consider drying off';
  }

  /// Services since the last calving (or all, if it never calved).
  List<FarmRecord> get currentCycleServices {
    final calved = lastCalving;
    return services.where((s) => calved == null || (s.dateOf('date')?.isAfter(calved) ?? false)).toList();
  }

  FarmRecord? get currentPregnancy {
    for (final s in currentCycleServices.reversed) {
      if (s.status == FarmModule.resultPregnant) return s;
    }
    return null;
  }

  DateTime? get expectedCalving => currentPregnancy?.dateOf('date')?.add(const Duration(days: Repro.gestationDays));

  FarmRecord? get pendingCheck {
    final cycle = currentCycleServices;
    if (cycle.isEmpty) return null;
    final last = cycle.last;
    return last.status == FarmModule.resultPending ? last : null;
  }

  /// For each conception in the record, how many services it took.
  List<int> get servicesPerConceptionHistory {
    final out = <int>[];
    var count = 0;
    for (final s in services) {
      count++;
      if (Repro.isConception(s.status)) {
        out.add(count);
        count = 0;
      }
    }
    return out;
  }

  double? get avgServicesPerConception {
    final h = servicesPerConceptionHistory;
    return h.isEmpty ? null : h.reduce((a, b) => a + b) / h.length;
  }

  /// One-line reproductive status for the profile header.
  String get reproStatus {
    if (!isFemale) return 'Male';
    final preg = currentPregnancy;
    if (preg != null) {
      final due = expectedCalving!;
      final left = daysBetween(today, due);
      final pregnantFor = daysBetween(preg.dateOf('date')!, today);
      return 'Pregnant · $pregnantFor days · calving expected ${formatDate(due)}${left >= 0 ? ' ($left days)' : ' (overdue)'}';
    }
    final pending = pendingCheck;
    if (pending != null) {
      final since = daysBetween(pending.dateOf('date')!, today);
      return since >= Repro.pregnancyCheckDays ? 'Served $since days ago · pregnancy check due now' : 'Served $since days ago · pregnancy check from day ${Repro.pregnancyCheckDays}';
    }
    final cycle = currentCycleServices;
    final calved = lastCalving;
    if (cycle.isEmpty) return calved == null ? 'Not yet served' : 'Open · not served since calving ${daysBetween(calved, today)} days ago';
    return 'Open · ${cycle.length} service${cycle.length == 1 ? '' : 's'} since ${calved == null ? 'records began' : 'calving'} — re-breed at next heat';
  }

  // Health & growth -------------------------------------------------------

  DateTime? get withdrawalUntil => farm.withdrawalEnd(animal.reference, today);

  double? get latestWeight => weightRecords.isEmpty ? FarmRecord.leadingNumber(animal['weight']) : weightRecords.last.number('weight');

  /// Average daily gain (kg/day) across the weight history.
  double? get averageDailyGain {
    final w = weightRecords;
    if (w.length < 2) return null;
    final days = daysBetween(w.first.dateOf('date')!, w.last.dateOf('date')!);
    return days <= 0 ? null : (w.last.number('weight') - w.first.number('weight')) / days;
  }

  // Timeline ------------------------------------------------------------

  List<TimelineEvent> get timeline {
    final events = <TimelineEvent>[];
    if (dob != null) {
      events.add(TimelineEvent(
          date: formatDate(dob!),
          icon: Icons.cake_outlined,
          title: 'Born',
          detail: [if ('${animal['sire']}'.trim().isNotEmpty) 'Sire ${animal['sire']}', if ('${animal['dam']}'.trim().isNotEmpty) 'Dam ${animal['dam']}'].join(' · ')));
    }
    for (final s in services) {
      final bull = '${s['bull'] ?? ''}'.trim();
      events.add(TimelineEvent(
          date: '${s['date']}',
          icon: Icons.biotech_outlined,
          title: '${s['method'] ?? 'Service'}${bull.isEmpty ? '' : ' · $bull'}',
          detail: [s.status, if ('${s['semen'] ?? ''}'.isNotEmpty) 'Semen ${s['semen']}', if ('${s['technician'] ?? ''}'.isNotEmpty) '${s['technician']}'].join(' · ')));
      final calved = s.dateOf('calvingDate');
      if (s.status == FarmModule.resultCalved && calved != null) {
        events.add(TimelineEvent(date: formatDate(calved), icon: Icons.child_friendly_outlined, title: 'Calved', detail: bull.isEmpty ? '' : 'Sire $bull'));
      }
    }
    for (final calf in offspring) {
      events.add(TimelineEvent(date: '${calf['dob']}', icon: Icons.pets_outlined, title: 'Calf ${calf['name']} (${calf.id})', detail: '${calf['sex']} · ${calf['breed']}'));
    }
    for (final h in healthRecords) {
      final wd = FarmRecord.leadingNumber(h['withdrawalDays']);
      events.add(TimelineEvent(
          date: '${h['date']}',
          icon: Icons.medical_services_outlined,
          title: '${h['type']} · ${h['details']}',
          detail: [if ('${h['medicine'] ?? ''}'.isNotEmpty) '${h['medicine']}', if (wd != null && wd > 0) '${formatQty(wd)}-day milk withdrawal', h.status].join(' · ')));
    }
    for (final w in weightRecords) {
      events.add(TimelineEvent(date: '${w['date']}', icon: Icons.monitor_weight_outlined, title: 'Weighed ${w['weight']} kg', detail: '${w['bcs'] ?? ''}'.isEmpty ? '' : 'Body condition ${w['bcs']}'));
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }
}

// -----------------------------------------------------------------------------
// Semen suitability

enum SuitabilityLevel { notRecommended, verify, noConflict }

class SuitabilityFinding {
  const SuitabilityFinding(this.level, this.text);

  final SuitabilityLevel level;
  final String text;
}

class SemenSuitability {
  const SemenSuitability({required this.semen, required this.findings, required this.missing});

  final FarmRecord semen;
  final List<SuitabilityFinding> findings;

  /// Pedigree/breed facts that are not recorded, so could not be checked.
  final List<String> missing;

  static const disclaimer = 'Based only on the data recorded in this app. It is not a guarantee of safety — confirm with your veterinarian or AI technician before use.';

  SuitabilityLevel get level {
    if (findings.any((f) => f.level == SuitabilityLevel.notRecommended)) return SuitabilityLevel.notRecommended;
    if (missing.isNotEmpty || findings.any((f) => f.level == SuitabilityLevel.verify)) return SuitabilityLevel.verify;
    return SuitabilityLevel.noConflict;
  }

  String get headline => switch (level) {
        SuitabilityLevel.notRecommended => 'Not recommended',
        SuitabilityLevel.verify => 'Verify before use',
        SuitabilityLevel.noConflict => 'No conflicts found in recorded data',
      };
}

/// Checks whether a semen batch suits a cow, following the rule: check breed,
/// pedigree and breeding history first, and when information is missing say
/// so clearly instead of declaring the semen safe.
class SemenAdvisor {
  SemenAdvisor(this.farm, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final DateTime today;

  static String _id(dynamic ref) => FarmRecord.refId(ref);
  static bool _known(dynamic v) => '${v ?? ''}'.trim().isNotEmpty;

  SemenSuitability check(FarmRecord cow, FarmRecord semen) {
    final findings = <SuitabilityFinding>[];
    final missing = <String>[];
    void block(String t) => findings.add(SuitabilityFinding(SuitabilityLevel.notRecommended, t));
    void verify(String t) => findings.add(SuitabilityFinding(SuitabilityLevel.verify, t));
    void ok(String t) => findings.add(SuitabilityFinding(SuitabilityLevel.noConflict, t));

    // Stock and expiry.
    final straws = semen.number('straws');
    final expiry = semen.dateOf('expiry');
    if ('${semen['status']}' == 'Damaged') block('This batch is marked as damaged.');
    if (straws <= 0) block('No straws left in stock.');
    if (expiry != null && dateOnly(expiry).isBefore(today)) {
      block('Semen expired on ${formatDate(expiry)}.');
    } else if (expiry != null && daysBetween(today, expiry) <= 30) {
      verify('Semen expires in ${daysBetween(today, expiry)} days (${formatDate(expiry)}).');
    } else if (expiry == null) {
      missing.add('Semen expiry date');
    }

    // The cow's own condition.
    final analytics = CowAnalytics(farm, cow, today: today);
    if ('${cow['sex']}'.toLowerCase() != 'female') block('${cow['name']} is not recorded as female.');
    if (analytics.currentPregnancy != null) block('${cow['name']} is already confirmed pregnant.');
    final calved = analytics.lastCalving;
    if (calved != null && daysBetween(calved, today) < Repro.waitingPeriodDays) {
      verify('Only ${daysBetween(calved, today)} days since calving (the usual waiting period is ${Repro.waitingPeriodDays}–60 days).');
    }
    if ('${cow['status']}'.toLowerCase() == 'treatment' || analytics.withdrawalUntil != null) {
      verify('${cow['name']} is under treatment — check with the vet before breeding.');
    }

    // Inbreeding: compare the bull with the cow's recorded relatives.
    final bull = _id(semen['bull']);
    final bullSire = _id(semen['bullSire']);
    final bullDam = _id(semen['bullDam']);
    final cowSire = _id(cow['sire']);
    final cowId = cow.id.toLowerCase();
    final dam = farm.resolve(FarmModule.animals, cow['dam']);
    final damSire = _id(dam?['sire']);
    final damId = _id(cow['dam']);

    if (bull.isEmpty) missing.add('Bull ID for this semen');
    if (!_known(semen['bullSire'])) missing.add('Bull’s sire');
    if (!_known(semen['bullDam'])) missing.add('Bull’s dam');
    if (!_known(cow['sire'])) missing.add('${cow['name']}’s sire');
    if (!_known(cow['dam'])) {
      missing.add('${cow['name']}’s dam');
    } else if (dam == null) {
      missing.add('${cow['name']}’s dam is not in the register, so her sire is unknown');
    } else if (!_known(dam['sire'])) {
      missing.add('Sire of ${dam['name']} (the dam)');
    }

    var related = false;
    if (bull.isNotEmpty && bull == cowSire) {
      block('The bull is ${cow['name']}’s sire (father × daughter).');
      related = true;
    }
    if (bullSire.isNotEmpty && bullSire == cowSire) {
      block('The bull and ${cow['name']} share the same sire (half-siblings).');
      related = true;
    }
    if (bull.isNotEmpty && bull == damSire) {
      block('The bull is ${cow['name']}’s maternal grandsire.');
      related = true;
    }
    if (bullSire.isNotEmpty && (bullSire == damSire)) {
      block('The bull’s sire is also ${cow['name']}’s maternal grandsire (closely related).');
      related = true;
    }
    if (bullDam.isNotEmpty && bullDam == cowId) {
      block('The bull is ${cow['name']}’s own son.');
      related = true;
    }
    if (bullDam.isNotEmpty && damId.isNotEmpty && bullDam == damId) {
      block('The bull and ${cow['name']} share the same dam (half-siblings).');
      related = true;
    }
    if (!related && bull.isNotEmpty) ok('No relationship found between the bull and ${cow['name']}’s recorded parents.');

    // Breeding history with this bull.
    final withBull = analytics.services.where((s) => bull.isNotEmpty && _id(s['bull']) == bull).toList();
    final failed = withBull.where((s) => s.status == FarmModule.resultOpen).length;
    if (failed >= 2) {
      verify('$failed earlier services with this bull did not result in pregnancy.');
    } else if (withBull.isNotEmpty) {
      ok('${withBull.length} earlier service${withBull.length == 1 ? '' : 's'} with this bull (${withBull.where((s) => Repro.isConception(s.status)).length} conceived).');
    }

    // Breed information.
    final cowBreed = '${cow['breed'] ?? ''}'.trim();
    final bullBreed = '${semen['breed'] ?? ''}'.trim();
    if (cowBreed.isEmpty) missing.add('${cow['name']}’s breed');
    if (bullBreed.isEmpty) missing.add('Bull breed');
    if (cowBreed.isNotEmpty && bullBreed.isNotEmpty) ok('Breeds: ${cow['name']} is $cowBreed, the bull is $bullBreed.');

    return SemenSuitability(semen: semen, findings: findings, missing: missing);
  }

  /// Every semen batch, best options first.
  List<SemenSuitability> rank(FarmRecord cow) {
    final results = farm.list(FarmModule.semen).map((s) => check(cow, s)).toList();
    results.sort((a, b) => b.level.index.compareTo(a.level.index));
    return results;
  }
}

// -----------------------------------------------------------------------------
// Herd-level summaries

class CowPerformance {
  const CowPerformance(this.animal, this.stats);

  final FarmRecord animal;
  final CowPeriodStats stats;
}

class BreedingSummary {
  const BreedingSummary({required this.services, required this.conceptions, required this.pregnant, required this.calvingsDue});

  final int services;
  final int conceptions;
  final int pregnant;

  /// Cows expected to calve within the next 60 days.
  final List<(FarmRecord, DateTime)> calvingsDue;

  double? get conceptionRate => services == 0 ? null : conceptions / services;
  double? get servicesPerConception => conceptions == 0 ? null : services / conceptions;
}

class HerdAnalytics {
  HerdAnalytics(this.farm, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final DateTime today;

  /// Animals that produce milk or are bred: females other than calves.
  List<FarmRecord> get cows => farm.list(FarmModule.animals).where((a) {
        final status = '${a['status']}'.toLowerCase();
        return '${a['sex']}'.toLowerCase() == 'female' && !const {'Calf', 'Kid', 'Lamb'}.contains('${a['type']}') && FarmController.isActive(a) && status.isNotEmpty;
      }).toList();

  CowAnalytics of(FarmRecord animal) => CowAnalytics(farm, animal, today: today);

  /// Per-cow milk, feed and margin for the last [days] days, best margin first.
  List<CowPerformance> performance(int days) => cows.map((c) => CowPerformance(c, of(c).period(days))).toList()..sort((a, b) => b.stats.margin.compareTo(a.stats.margin));

  BreedingSummary get breeding {
    final services = farm.list(FarmModule.breeding);
    final calvingsDue = <(FarmRecord, DateTime)>[];
    var pregnant = 0;
    for (final c in cows) {
      final due = of(c).expectedCalving;
      if (due == null) continue;
      pregnant++;
      if (daysBetween(today, due) <= 60) calvingsDue.add((c, due));
    }
    calvingsDue.sort((a, b) => a.$2.compareTo(b.$2));
    return BreedingSummary(
      services: services.length,
      conceptions: services.where((s) => Repro.isConception(s.status)).length,
      pregnant: pregnant,
      calvingsDue: calvingsDue,
    );
  }
}
