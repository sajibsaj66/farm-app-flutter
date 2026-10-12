import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'farm_controller.dart';
import 'health_rules.dart';
import 'herd_analytics.dart';

/// One recorded value compared with the animal's own earlier level.
class ProductionReview {
  const ProductionReview(
      {required this.metric, required this.unit, required this.recent, required this.baseline, required this.recentDays, required this.baselineDays, required this.thresholdPercent});

  final String metric;
  final String unit;
  final double recent;
  final double baseline;
  final int recentDays;
  final int baselineDays;
  final double thresholdPercent;

  double get percent => baseline <= 0 ? 100 : recent / baseline * 100;

  /// Below the configured review level.
  bool get triggered => baseline > 0 && percent < thresholdPercent;

  String get explanation => '$metric: ${recent.toStringAsFixed(1)} $unit/day over the last $recentDays days vs ${baseline.toStringAsFixed(1)} $unit/day in the $baselineDays days before '
      '(${percent.toStringAsFixed(0)}%${triggered ? ', below the ${formatQty(thresholdPercent)}% review level' : ''}).';
}

/// A scheduled health activity on a given day.
class HealthActivity {
  const HealthActivity({required this.date, required this.title, required this.detail, required this.module, required this.recordId, this.overdue = false});

  final DateTime date;
  final String title;
  final String detail;
  final String module;
  final String recordId;
  final bool overdue;
}

/// An animal's row on the health dashboard.
class AnimalHealthRow {
  const AnimalHealthRow({required this.animal, required this.status, required this.openCases, required this.urgent, required this.activeTreatments, required this.nextFollowUp});

  final FarmRecord animal;
  final String status;
  final List<FarmRecord> openCases;
  final bool urgent;
  final int activeTreatments;
  final DateTime? nextFollowUp;

  FarmRecord? get latestCase => openCases.isEmpty ? null : openCases.first;
}

/// Dashboard filter values (null/empty = any).
class HealthFilter {
  const HealthFilter({this.query = '', this.species, this.breed, this.group, this.status, this.from, this.to, this.treatment, this.vet});

  final String query;
  final String? species;
  final String? breed;
  final String? group;
  final String? status;
  final DateTime? from;
  final DateTime? to;

  /// 'Active treatment' or 'No active treatment'.
  final String? treatment;
  final String? vet;
}

/// Read-only health figures worked out from saved records.
class HealthAnalytics {
  HealthAnalytics(this.farm, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final DateTime today;

  List<FarmRecord> get cases => farm.list(FarmModule.illness);

  List<FarmRecord> casesFor(FarmRecord animal) => cases.where((c) => animal.isReferencedBy(c['animal'])).toList()..sort((a, b) => '${b['noticedAt']}'.compareTo('${a['noticedAt']}'));

  List<FarmRecord> get openCases => cases.where((c) => HealthRules.isOpen(c.data)).toList()..sort((a, b) => '${b['noticedAt']}'.compareTo('${a['noticedAt']}'));

  /// Open cases that are not long-term (chronic) care.
  List<FarmRecord> get sickCases => openCases.where((c) => '${c['closure']}' != FarmModule.closeChronic).toList();

  List<FarmRecord> get urgentCases => openCases.where((c) => HealthRules.isUrgent(farm, c)).toList();

  List<FarmRecord> get activeAnimals => farm.list(FarmModule.animals).where(FarmController.isActive).toList();

  String statusOf(FarmRecord animal) =>
      '${animal['healthStatus'] ?? ''}'.isEmpty ? HealthRules.animalStatus(farm, animal, today: today, recoveredDays: farm.profile.recoveredShowDays) : '${animal['healthStatus']}';

  int countStatus(String status) => activeAnimals.where((a) => statusOf(a) == status).length;

  int get healthyCount => countStatus(FarmModule.healthHealthy);
  int get sickAnimalCount => sickCases.map((c) => FarmRecord.refId(c['animal'])).toSet().length;
  int get urgentAnimalCount => urgentCases.map((c) => FarmRecord.refId(c['animal'])).toSet().length;
  int get underTreatmentCount => countStatus(FarmModule.healthTreatment);
  int get followUpCount => countStatus(FarmModule.healthFollowUp);
  int get recoveredCount => countStatus(FarmModule.healthRecovered);

  List<FarmRecord> get scheduledFollowUps => farm.list(FarmModule.followUps).where((f) => '${f['status']}' == 'Scheduled').toList()..sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}'));

  List<FarmRecord> get overdueFollowUps => scheduledFollowUps.where((f) => f.dateOf('dueDate')?.isBefore(today) ?? false).toList();

  List<FarmRecord> upcomingFollowUps(int days) => scheduledFollowUps.where((f) {
        final d = f.dateOf('dueDate');
        return d != null && !d.isBefore(today) && !d.isAfter(today.add(Duration(days: days)));
      }).toList();

  String _name(dynamic ref) => FarmRecord.displayName(ref);

  /// Everything scheduled for [day] (default today), plus overdue items.
  List<HealthActivity> activitiesOn([DateTime? day]) {
    final d = dateOnly(day ?? today);
    bool on(DateTime? x) => x != null && dateOnly(x) == d;
    final out = <HealthActivity>[];
    for (final f in scheduledFollowUps) {
      final due = f.dateOf('dueDate');
      if (on(due) || (due != null && due.isBefore(d))) {
        out.add(HealthActivity(
            date: due!,
            title: '${_name(f['animal'])}: ${f['type']}',
            detail: 'Follow-up ${f.id} for ${FarmRecord.refId(f['illness']).toUpperCase()}',
            module: FarmModule.followUps,
            recordId: f.id,
            overdue: due.isBefore(d)));
      }
    }
    for (final m in farm.list(FarmModule.medication).where((m) => '${m['status']}' == FarmModule.medScheduled)) {
      final at = m.dateOf('scheduledAt');
      if (on(at) || (at != null && at.isBefore(d))) {
        out.add(HealthActivity(
            date: at!,
            title: '${_name(m['animal'])}: ${m['medicine']} dose',
            detail: 'Scheduled ${m['scheduledAt']} — mark it Given, Delayed or Missed',
            module: FarmModule.medication,
            recordId: m.id,
            overdue: dateOnly(at).isBefore(d)));
      }
    }
    for (final c in farm.list(FarmModule.consultations)) {
      final next = c.dateOf('nextDate');
      if (!on(next)) continue;
      out.add(HealthActivity(date: next!, title: '${_name(c['animal'])}: veterinary consultation', detail: 'Booked with ${c['vetName']}', module: FarmModule.consultations, recordId: c.id));
    }
    for (final h in farm.list(FarmModule.health)) {
      final next = h.dateOf('next') ?? (h.status == 'Scheduled' ? h.dateOf('date') : null);
      if (on(next) && h.status != 'Completed') {
        final who = '${h['animal'] ?? ''}'.isNotEmpty ? _name(h['animal']) : _name(h['batch']);
        out.add(HealthActivity(date: next!, title: '$who: ${h['type']}', detail: '${h['details']}', module: FarmModule.health, recordId: h.id));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Dashboard rows: every active animal, plus any inactive animal that still
  /// has an open case.
  List<AnimalHealthRow> rows(HealthFilter f) {
    final animals = farm.list(FarmModule.animals).where((a) => FarmController.isActive(a) || openCases.any((c) => a.isReferencedBy(c['animal'])));
    final out = <AnimalHealthRow>[];
    for (final a in animals) {
      final all = casesFor(a);
      final open = all.where((c) => HealthRules.isOpen(c.data)).toList();
      final status = statusOf(a);
      final treatments = farm.list(FarmModule.treatments).where((t) => a.isReferencedBy(t['animal']) && HealthRules.isActiveTreatment(t)).length;
      final followUps = scheduledFollowUps.where((x) => a.isReferencedBy(x['animal'])).map((x) => x.dateOf('dueDate')).whereType<DateTime>().toList()..sort();
      if (!_matches(f, a, status, all, treatments)) continue;
      out.add(AnimalHealthRow(
        animal: a,
        status: status,
        openCases: open,
        urgent: open.any((c) => HealthRules.isUrgent(farm, c)),
        activeTreatments: treatments,
        nextFollowUp: followUps.isEmpty ? null : followUps.first,
      ));
    }
    out.sort((a, b) {
      if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
      if (a.openCases.isEmpty != b.openCases.isEmpty) return a.openCases.isEmpty ? 1 : -1;
      return '${a.animal['name']}'.compareTo('${b.animal['name']}');
    });
    return out;
  }

  /// Extra choices in the health-status filter (matching the dashboard tiles).
  static const filterSick = 'Reported sick (open case)';
  static const filterUrgent = 'Urgent vet attention';
  static const statusFilters = [filterSick, filterUrgent, ...FarmModule.healthStatuses];

  bool _matches(HealthFilter f, FarmRecord a, String status, List<FarmRecord> cases, int activeTreatments) {
    final q = f.query.trim().toLowerCase();
    if (q.isNotEmpty && !'${a.id} ${a['tag'] ?? ''} ${a['name'] ?? ''}'.toLowerCase().contains(q)) return false;
    if (f.species != null && '${a['species']}' != f.species) return false;
    if (f.breed != null && '${a['breed']}' != f.breed) return false;
    if (f.group != null && '${a['group']}' != f.group) return false;
    if (f.status == filterSick) {
      if (!cases.any((c) => HealthRules.isOpen(c.data) && '${c['closure']}' != FarmModule.closeChronic)) return false;
    } else if (f.status == filterUrgent) {
      if (!cases.any((c) => HealthRules.isOpen(c.data) && HealthRules.isUrgent(farm, c))) return false;
    } else if (f.status != null && status != f.status) {
      return false;
    }
    if (f.treatment == 'Active treatment' && activeTreatments == 0) return false;
    if (f.treatment == 'No active treatment' && activeTreatments > 0) return false;
    if (f.from != null || f.to != null) {
      final inRange = cases.any((c) {
        final d = c.dateOf('noticedAt');
        if (d == null) return false;
        if (f.from != null && dateOnly(d).isBefore(dateOnly(f.from!))) return false;
        if (f.to != null && dateOnly(d).isAfter(dateOnly(f.to!))) return false;
        return true;
      });
      if (!inRange) return false;
    }
    if (f.vet != null) {
      final vets = vetsFor(a);
      if (!vets.contains(f.vet)) return false;
    }
    return true;
  }

  /// Veterinarians recorded on an animal's cases, consultations and treatments.
  Set<String> vetsFor(FarmRecord a) => {
        for (final c in casesFor(a)) '${c['vetName'] ?? ''}'.trim(),
        for (final c in farm.list(FarmModule.consultations).where((x) => a.isReferencedBy(x['animal']))) '${c['vetName'] ?? ''}'.trim(),
        for (final t in farm.list(FarmModule.treatments).where((x) => a.isReferencedBy(x['animal']))) '${t['prescribedBy'] ?? ''}'.trim(),
      }..remove('');

  Set<String> get allVets => {for (final a in farm.list(FarmModule.animals)) ...vetsFor(a)};

  // ------------------------------------------------- production comparison

  /// Milk (only for animals that have milk records) and feed intake over the
  /// recent window, against the animal's own earlier average. Ending on
  /// [asOf] (default today).
  List<ProductionReview> productionReview(FarmRecord animal, {DateTime? asOf}) {
    final p = farm.profile;
    final end = dateOnly(asOf ?? today);
    final recentFrom = end.subtract(Duration(days: p.healthRecentDays - 1));
    final baseFrom = recentFrom.subtract(Duration(days: p.healthBaselineDays));
    final a = CowAnalytics(farm, animal, today: end);

    double avg(Map<String, double> byDay, DateTime from, DateTime to) {
      final days = byDay.entries.where((e) {
        final d = FarmRecord.parseDate(e.key);
        return d != null && !d.isBefore(from) && !d.isAfter(to);
      }).toList();
      return days.isEmpty ? 0 : days.fold(0.0, (s, e) => s + e.value) / days.length;
    }

    final out = <ProductionReview>[];
    final milk = <String, double>{};
    for (final m in a.milkRecords) {
      milk['${m['date']}'] = (milk['${m['date']}'] ?? 0) + m.number('litres');
    }
    // Species without milk records are never compared on milk.
    if (milk.isNotEmpty) {
      final baseline = avg(milk, baseFrom, recentFrom.subtract(const Duration(days: 1)));
      if (baseline > 0) {
        out.add(ProductionReview(
            metric: 'Milk', unit: 'L', recent: avg(milk, recentFrom, end), baseline: baseline, recentDays: p.healthRecentDays, baselineDays: p.healthBaselineDays, thresholdPercent: p.lowMilkPercent));
      }
    }
    final feed = <String, double>{};
    for (final f in a.feedShares) {
      feed[f.date] = (feed[f.date] ?? 0) + f.kg;
    }
    if (feed.isNotEmpty) {
      final baseline = avg(feed, baseFrom, recentFrom.subtract(const Duration(days: 1)));
      if (baseline > 0) {
        out.add(ProductionReview(
            metric: 'Feed intake',
            unit: 'kg',
            recent: avg(feed, recentFrom, end),
            baseline: baseline,
            recentDays: p.healthRecentDays,
            baselineDays: p.healthBaselineDays,
            thresholdPercent: p.lowFeedPercent));
      }
    }
    return out;
  }

  /// Production in the days before the symptoms were noticed against the days
  /// since — to compare a health report with production changes.
  List<ProductionReview> reviewAround(FarmRecord illness) {
    final animal = farm.resolve(FarmModule.animals, illness['animal']);
    final noticed = illness.dateOf('noticedAt');
    if (animal == null || noticed == null) return const [];
    final closed = illness.dateOf('closedOn');
    final end = closed != null && closed.isBefore(today) ? dateOnly(closed) : today;
    final days = daysBetween(noticed, end) + 1;
    if (days <= 0) return const [];
    final p = farm.profile;
    final a = CowAnalytics(farm, animal, today: end);
    final baseFrom = dateOnly(noticed).subtract(Duration(days: p.healthBaselineDays));
    final baseTo = dateOnly(noticed).subtract(const Duration(days: 1));
    double avg(Map<String, double> byDay, DateTime from, DateTime to) {
      final xs = byDay.entries.where((e) {
        final d = FarmRecord.parseDate(e.key);
        return d != null && !d.isBefore(from) && !d.isAfter(to);
      }).toList();
      return xs.isEmpty ? 0 : xs.fold(0.0, (s, e) => s + e.value) / xs.length;
    }

    final out = <ProductionReview>[];
    final milk = <String, double>{};
    for (final m in a.milkRecords) {
      milk['${m['date']}'] = (milk['${m['date']}'] ?? 0) + m.number('litres');
    }
    final mBase = avg(milk, baseFrom, baseTo);
    if (mBase > 0) {
      out.add(ProductionReview(
          metric: 'Milk since symptoms',
          unit: 'L',
          recent: avg(milk, dateOnly(noticed), end),
          baseline: mBase,
          recentDays: days,
          baselineDays: p.healthBaselineDays,
          thresholdPercent: p.lowMilkPercent));
    }
    final feed = <String, double>{};
    for (final f in a.feedShares) {
      feed[f.date] = (feed[f.date] ?? 0) + f.kg;
    }
    final fBase = avg(feed, baseFrom, baseTo);
    if (fBase > 0) {
      out.add(ProductionReview(
          metric: 'Feed intake since symptoms',
          unit: 'kg',
          recent: avg(feed, dateOnly(noticed), end),
          baseline: fBase,
          recentDays: days,
          baselineDays: p.healthBaselineDays,
          thresholdPercent: p.lowFeedPercent));
    }
    return out;
  }
}
