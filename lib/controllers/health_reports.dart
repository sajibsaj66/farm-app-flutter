import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import '../models/finance.dart';
import 'farm_controller.dart';
import 'health_analytics.dart';
import 'health_rules.dart';

/// Health reports, built only from saved records and filtered by the report
/// filter (dates, species, animal).
class HealthReports {
  HealthReports(this.farm, this.filter, {DateTime? today}) : today = dateOnly(today ?? farm.today);

  final FarmController farm;
  final ReportFilter filter;
  final DateTime today;

  String get _cur => farm.profile.currency;

  bool _inRange(dynamic date) {
    final d = FarmRecord.parseDate(date);
    return d != null && !dateOnly(d).isBefore(dateOnly(filter.from)) && !dateOnly(d).isAfter(dateOnly(filter.to));
  }

  /// Matches the species / animal filters through the record's animal.
  bool _animalOk(dynamic animalRef) {
    if (filter.animal != null && FarmRecord.refId(animalRef) != filter.animal!.toLowerCase()) return false;
    if (filter.species != null) {
      final a = farm.resolve(FarmModule.animals, animalRef);
      if (a == null || '${a['species']}' != filter.species) return false;
    }
    if (filter.location != null) {
      final a = farm.resolve(FarmModule.animals, animalRef);
      if (a == null || '${a['location']}' != filter.location) return false;
    }
    return true;
  }

  List<FarmRecord> _cases({bool dated = true}) =>
      farm.list(FarmModule.illness).where((c) => _animalOk(c['animal']) && (!dated || _inRange(c['noticedAt']))).toList()..sort((a, b) => '${b['noticedAt']}'.compareTo('${a['noticedAt']}'));

  ReportTable sickList() {
    final open = farm.list(FarmModule.illness).where((c) => HealthRules.isOpen(c.data) && _animalOk(c['animal'])).toList()..sort((a, b) => '${b['noticedAt']}'.compareTo('${a['noticedAt']}'));
    return ReportTable(
      title: 'Current sick-animal list',
      columns: ['Case', 'Animal', 'Species', 'Noticed', 'Severity', 'Stage', 'Diagnosis status', 'Veterinarian’s diagnosis', 'Urgent', 'Symptoms'],
      rows: [
        for (final c in open)
          [
            c.id,
            '${c['animal']}',
            '${c['species']}',
            '${c['noticedAt']}',
            '${c['severity']}',
            '${c['stage']}',
            '${c['diagnosisStatus']}',
            '${c['diagnosis'] ?? ''}',
            HealthRules.isUrgent(farm, c) ? 'Yes' : '',
            '${c['symptoms']}'
          ],
      ],
      numericFrom: 99,
      linkIds: [for (final c in open) c.id],
      summary: [('Open cases', '${open.length}'), ('Urgent', '${open.where((c) => HealthRules.isUrgent(farm, c)).length}')],
      notes: const ['All open cases regardless of dates. Reported symptoms are not a diagnosis; the diagnosis column shows only what a veterinarian recorded.'],
    );
  }

  ReportTable history() {
    final cases = _cases();
    return ReportTable(
      title: 'Illness history',
      columns: ['Case', 'Animal', 'Noticed', 'Severity', 'Symptoms', 'Diagnosis status', 'Diagnosis', 'Outcome', 'Closed on', 'Reopened'],
      rows: [
        for (final c in cases)
          [
            c.id,
            '${c['animal']}',
            '${c['noticedAt']}',
            '${c['severity']}',
            '${c['symptoms']}',
            '${c['diagnosisStatus']}',
            '${c['diagnosis'] ?? ''}',
            '${c['closure'] ?? ''}'.isEmpty ? 'Open · ${c['stage']}' : '${c['closure']}',
            '${c['closedOn'] ?? ''}',
            '${c['reopenedCount'] ?? '0'}'
          ],
      ],
      numericFrom: 99,
      linkIds: [for (final c in cases) c.id],
      notes: const ['Cases whose symptoms were first noticed in the selected dates.'],
    );
  }

  ReportTable frequencyBySpecies() {
    final cases = _cases();
    final animalsBySpecies = <String, int>{};
    for (final a in farm.list(FarmModule.animals).where(FarmController.isActive)) {
      animalsBySpecies['${a['species']}'] = (animalsBySpecies['${a['species']}'] ?? 0) + 1;
    }
    final bySpecies = <String, List<FarmRecord>>{};
    for (final c in cases) {
      bySpecies.putIfAbsent('${c['species']}'.isEmpty ? 'Unspecified' : '${c['species']}', () => []).add(c);
    }
    return ReportTable(
      title: 'Illness frequency by species',
      columns: ['Species', 'Cases', 'Animals affected', 'Active animals', 'Cases per 100 animals', 'High / emergency', 'Recovered'],
      rows: [
        for (final e in (bySpecies.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))))
          () {
            final affected = e.value.map((c) => FarmRecord.refId(c['animal'])).toSet().length;
            final herd = animalsBySpecies[e.key] ?? 0;
            return [
              e.key,
              '${e.value.length}',
              '$affected',
              '$herd',
              herd == 0 ? '' : (e.value.length / herd * 100).toStringAsFixed(1),
              '${e.value.where((c) => c['severity'] == 'High' || c['severity'] == 'Emergency').length}',
              '${e.value.where((c) => c['closure'] == FarmModule.closeRecovered).length}',
            ];
          }(),
      ],
      numericFrom: 1,
      notes: const ['Counts of reported cases — not a diagnosis rate.'],
    );
  }

  ReportTable treatments() {
    final rows = farm.list(FarmModule.treatments).where((t) => _animalOk(t['animal']) && _inRange(t['startDate'])).toList()..sort((a, b) => '${b['startDate']}'.compareTo('${a['startDate']}'));
    return ReportTable(
      title: 'Treatment records',
      columns: ['Treatment', 'Case', 'Animal', 'Start', 'Planned end', 'Medicine', 'Prescribed dose', 'Route', 'Frequency', 'Prescribed by', 'Status', 'Doses given', 'Cost ($_cur)'],
      rows: [
        for (final t in rows)
          [
            t.id,
            FarmRecord.refId(t['illness']).toUpperCase(),
            '${t['animal']}',
            '${t['startDate']}',
            '${t['endDate'] ?? ''}',
            '${t['medicine']}',
            '${t['dose']} ${t['doseUnit']}',
            '${t['route'] ?? ''}',
            '${t['frequency']}',
            '${t['prescribedBy']}',
            '${t['outcome']}',
            '${farm.list(FarmModule.medication).where((m) => t.isReferencedBy(m['treatment']) && (m['status'] == FarmModule.medGiven || m['status'] == FarmModule.medDelayed)).length}',
            t.number('cost').toStringAsFixed(0),
          ],
      ],
      numericFrom: 11,
      linkIds: [for (final t in rows) FarmRecord.refId(t['illness']).toUpperCase()],
      notes: const ['Doses are recorded exactly as prescribed; the app does not verify prescriptions or calculate doses.'],
    );
  }

  ReportTable consultations() {
    final rows = farm.list(FarmModule.consultations).where((c) => _animalOk(c['animal']) && _inRange(c['date'])).toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return ReportTable(
      title: 'Veterinary consultation history',
      columns: ['Consultation', 'Case', 'Animal', 'Date', 'Veterinarian', 'Diagnosis status', 'Diagnosis', 'Recommended treatment', 'Next visit', 'Fee ($_cur)'],
      rows: [
        for (final c in rows)
          [
            c.id,
            FarmRecord.refId(c['illness']).toUpperCase(),
            '${c['animal']}',
            '${c['date']}',
            '${c['vetName']}',
            '${c['diagnosisStatus']}',
            '${c['diagnosis'] ?? ''}',
            '${c['recommendedTreatment'] ?? ''}',
            '${c['nextDate'] ?? ''}',
            c.number('fee').toStringAsFixed(0)
          ],
      ],
      numericFrom: 9,
      linkIds: [for (final c in rows) FarmRecord.refId(c['illness']).toUpperCase()],
    );
  }

  ReportTable medication() {
    final rows = farm.list(FarmModule.medication).where((m) {
      final when = '${m['givenAt'] ?? ''}'.isNotEmpty ? m['givenAt'] : m['scheduledAt'];
      return _animalOk(m['animal']) && _inRange(when);
    }).toList()
      ..sort((a, b) => '${b['givenAt']}${b['scheduledAt']}'.compareTo('${a['givenAt']}${a['scheduledAt']}'));
    final counts = <String, int>{};
    for (final m in rows) {
      counts['${m['status']}'] = (counts['${m['status']}'] ?? 0) + 1;
    }
    return ReportTable(
      title: 'Medication administration history',
      columns: ['Record', 'Animal', 'Medicine', 'Status', 'Scheduled', 'Given at', 'Dose given', 'Given by', 'Reason', 'Side effects'],
      rows: [
        for (final m in rows)
          [
            m.id,
            '${m['animal']}',
            '${m['medicine']}',
            '${m['status']}',
            '${m['scheduledAt'] ?? ''}',
            '${m['givenAt'] ?? ''}',
            '${m['doseGiven'] ?? ''}',
            '${m['administeredBy'] ?? ''}',
            '${m['reason'] ?? ''}',
            '${m['sideEffects'] ?? ''}'
          ],
      ],
      numericFrom: 99,
      linkIds: [for (final m in rows) FarmRecord.refId(m['illness']).toUpperCase()],
      summary: [for (final e in counts.entries) (e.key, '${e.value}')],
      notes: const ['Any side effects or reactions should be discussed with the veterinarian.'],
    );
  }

  ReportTable followUps() {
    final rows = farm.list(FarmModule.followUps).where((f) => _animalOk(f['animal']) && ('${f['status']}' == 'Scheduled' || _inRange(f['dueDate']))).toList()
      ..sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}'));
    bool overdue(FarmRecord f) => '${f['status']}' == 'Scheduled' && (f.dateOf('dueDate')?.isBefore(today) ?? false);
    return ReportTable(
      title: 'Upcoming and overdue follow-ups',
      columns: ['Follow-up', 'Case', 'Animal', 'Due', 'Type', 'Status', 'When', 'Progress', 'Next step'],
      rows: [
        for (final f in rows)
          [
            f.id,
            FarmRecord.refId(f['illness']).toUpperCase(),
            '${f['animal']}',
            '${f['dueDate']}',
            '${f['type']}',
            '${f['status']}',
            '${f['status']}' != 'Scheduled' ? '' : (overdue(f) ? 'Overdue ${daysBetween(f.dateOf('dueDate')!, today)} d' : 'In ${daysBetween(today, f.dateOf('dueDate')!)} d'),
            '${f['progress'] ?? ''}',
            '${f['nextAction'] ?? ''}',
          ],
      ],
      numericFrom: 99,
      linkIds: [for (final f in rows) FarmRecord.refId(f['illness']).toUpperCase()],
      summary: [('Scheduled', '${rows.where((f) => f['status'] == 'Scheduled').length}'), ('Overdue', '${rows.where(overdue).length}')],
      notes: const ['Shows every scheduled follow-up plus completed ones due in the selected dates.'],
    );
  }

  ReportTable recovered() {
    final rows = farm.list(FarmModule.illness).where((c) => c['closure'] == FarmModule.closeRecovered && _animalOk(c['animal']) && _inRange(c['closedOn'])).toList()
      ..sort((a, b) => '${b['closedOn']}'.compareTo('${a['closedOn']}'));
    return ReportTable(
      title: 'Recovered animals',
      columns: ['Case', 'Animal', 'Noticed', 'Recovered on', 'Days ill', 'Diagnosis', 'Recovery notes'],
      rows: [
        for (final c in rows)
          [
            c.id,
            '${c['animal']}',
            '${c['noticedAt']}',
            '${c['closedOn']}',
            c.dateOf('noticedAt') == null || c.dateOf('closedOn') == null ? '' : '${daysBetween(c.dateOf('noticedAt')!, c.dateOf('closedOn')!)}',
            '${c['diagnosis'] ?? ''}',
            '${c['closureNotes'] ?? ''}'
          ],
      ],
      numericFrom: 4,
      linkIds: [for (final c in rows) c.id],
      notes: const ['Recovery is only ever recorded by a person — never from a treatment end date.'],
    );
  }

  ReportTable recurring() {
    final byAnimal = <String, List<FarmRecord>>{};
    for (final c in farm.list(FarmModule.illness).where((c) => _animalOk(c['animal']))) {
      byAnimal.putIfAbsent(FarmRecord.refId(c['animal']), () => []).add(c);
    }
    final rows = <List<String>>[];
    final ids = <String?>[];
    for (final e in byAnimal.entries) {
      final reopened = e.value.fold(0.0, (s, c) => s + (FarmRecord.leadingNumber(c['reopenedCount']) ?? 0));
      final chronic = e.value.where((c) => c['closure'] == FarmModule.closeChronic).length;
      final open = e.value.where((c) => HealthRules.isOpen(c.data)).length;
      if (e.value.length < 2 && reopened == 0 && chronic == 0) continue;
      rows.add(
          ['${e.value.first['animal']}', '${e.value.length}', formatQty(reopened), '$chronic', '$open', e.value.map((c) => '${'${c['noticedAt']}'.split(' ').first} ${c['symptoms']}').join(' | ')]);
      ids.add(e.key.toUpperCase());
    }
    return ReportTable(
      title: 'Ongoing and recurring illness',
      columns: ['Animal', 'Cases', 'Times reopened', 'Chronic cases', 'Open now', 'Cases (date and symptoms)'],
      rows: rows,
      numericFrom: 1,
      linkIds: ids,
      notes: const ['Animals with two or more cases, a reopened case, or a chronic condition (all dates).'],
    );
  }

  ReportTable costs() {
    final rows = <List<String>>[];
    var total = 0.0;
    void add(String date, String type, String id, dynamic animal, String detail, double amount) {
      if (amount <= 0) return;
      rows.add([date, type, id, '$animal', detail, amount.toStringAsFixed(0)]);
      total += amount;
    }

    for (final c in farm.list(FarmModule.consultations).where((c) => _animalOk(c['animal']) && _inRange(c['date']))) {
      add('${c['date']}', 'Consultation fee', c.id, c['animal'], '${c['vetName']}', c.number('fee'));
    }
    for (final t in farm.list(FarmModule.treatments).where((t) => _animalOk(t['animal']) && _inRange(t['startDate']))) {
      add('${t['startDate']}', 'Treatment', t.id, t['animal'], '${t['medicine']}', t.number('cost'));
    }
    for (final h in farm.list(FarmModule.health).where((h) => '${h['animal'] ?? ''}'.isNotEmpty ? _animalOk(h['animal']) : filter.animal == null && filter.species == null)) {
      if (!_inRange(h['date'])) continue;
      add('${h['date']}', 'Health record (${h['type']})', h.id, '${h['animal'] ?? ''}'.isNotEmpty ? h['animal'] : h['batch'], '${h['details']}', h.number('cost'));
    }
    if (filter.animal == null && filter.species == null) {
      for (final e in farm
          .inRange(FarmModule.expenses, filter.from, filter.to)
          .where((e) => !FarmModule.awaitsOrRefused(e['approval']))
          .where((e) => e['category'] == 'Veterinary treatment' || e['category'] == 'Medicine and vaccines')) {
        add('${e['date']}', 'Expense: ${e['category']}', e.id, '${e['animal'] ?? ''}'.isEmpty ? (e['batch'] ?? 'Farm-wide') : e['animal'], '${e['description']}', e.number('amount'));
      }
    }
    rows.sort((a, b) => b.first.compareTo(a.first));
    return ReportTable(
      title: 'Veterinary and medicine costs',
      columns: ['Date', 'Type', 'Record', 'Animal', 'Details', 'Amount ($_cur)'],
      rows: rows,
      numericFrom: 5,
      summary: [('Total', '$_cur${total.toStringAsFixed(0)}')],
      notes: const [
        'Medicine taken from stock is not listed again here: its cost is the purchase expense.',
        'Expenses (vet retainers, bulk medicine) are included only when the report is not filtered to one animal or species.',
      ],
    );
  }

  ReportTable productionObservations() {
    final h = HealthAnalytics(farm, today: today);
    final rows = <List<String>>[];
    final ids = <String?>[];
    for (final c in _cases()) {
      for (final r in h.reviewAround(c)) {
        rows.add([
          c.id,
          '${c['animal']}',
          '${c['noticedAt']}',
          r.metric,
          '${r.baseline.toStringAsFixed(1)} ${r.unit}/day',
          '${r.recent.toStringAsFixed(1)} ${r.unit}/day',
          '${r.percent.toStringAsFixed(0)}%',
          r.triggered ? 'Below review level' : ''
        ]);
        ids.add(c.id);
      }
    }
    for (final a in farm.list(FarmModule.animals).where((a) => FarmController.isActive(a) && _animalOk(a.reference))) {
      for (final r in h.productionReview(a).where((r) => r.triggered)) {
        rows.add([
          '—',
          a.reference,
          '',
          '${r.metric} (last ${r.recentDays} days)',
          '${r.baseline.toStringAsFixed(1)} ${r.unit}/day',
          '${r.recent.toStringAsFixed(1)} ${r.unit}/day',
          '${r.percent.toStringAsFixed(0)}%',
          'Below review level'
        ]);
        ids.add(a.id);
      }
    }
    return ReportTable(
      title: 'Health-related production observations',
      columns: ['Case', 'Animal', 'Symptoms noticed', 'Measure', 'Before', 'After / recent', 'Change', 'Flag'],
      rows: rows,
      numericFrom: 99,
      linkIds: ids,
      notes: [
        'Before = average over the ${farm.profile.healthBaselineDays} days before symptoms were noticed (or before the recent window). Review levels: milk ${formatQty(farm.profile.lowMilkPercent)}%, feed ${formatQty(farm.profile.lowFeedPercent)}% (Health settings).',
        'Production changes are observations to review — they are not proof of disease. Historical records are never changed.',
      ],
    );
  }
}
