import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/finance_engine.dart';
import 'package:technovate_farm_management/controllers/health_analytics.dart';
import 'package:technovate_farm_management/controllers/health_rules.dart';
import 'package:technovate_farm_management/controllers/illness_controller.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/controllers/records_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/core/utils/dates.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/finance.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  late FarmController farm;
  late AuthController auth;
  final today = DateTime(2026, 10, 10, 12);
  String d(int daysAgo) => formatDate(today.subtract(Duration(days: daysAgo)));
  String dt(int daysAgo, [String time = '08:00']) => '${d(daysAgo)} $time';

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => today);
    auth = AuthController(LocalStorageService.instance);
    farm.actor = () => auth.currentUser?.name;
    await farm.init();
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  });

  FarmRecord animal(String id) => farm.find(FarmModule.animals, id)!;
  FarmRecord illness(String id) => farm.find(FarmModule.illness, id)!;
  FarmRecord stock(String name) => farm.feedItem(name)!;
  Matcher rule([String? text]) => throwsA(isA<FarmRuleException>().having((e) => e.message, 'message', text == null ? anything : contains(text)));

  /// Reports Rani (a healthy, milking cow) as sick.
  Future<FarmRecord> reportRani({String severity = 'Moderate', String danger = '', String symptoms = 'Coughing, not eating'}) => farm.add(FarmModule.illness, {
        'animal': 'AN-1002 · Rani',
        'noticedAt': dt(0, '06:00'),
        'reportedAt': dt(0, '07:00'),
        'reportedBy': 'Sabbir Hossain',
        'symptoms': symptoms,
        'dangerSigns': danger,
        'appetite': 'Not eating',
        'water': 'Not checked',
        'milkChange': 'Decreased',
        'temperature': '',
        'severity': severity,
        'suspectedCause': 'Pneumonia',
      });

  group('1–5: reporting illness', () {
    test('1. creating an illness record saves it and updates only the health status', () async {
      final milkBefore = farm.count(FarmModule.milkProduction);
      expect(animal('AN-1002')['healthStatus'], FarmModule.healthHealthy);
      final c = await reportRani();
      expect(c.id, startsWith('IC-'));
      expect(c['species'], 'Cattle');
      expect(c['stage'], FarmModule.healthAwaitingVet);
      expect(c['_createdAt'], isNotEmpty);
      expect(animal('AN-1002')['healthStatus'], FarmModule.healthAwaitingVet);
      expect(animal('AN-1002').status, 'Pregnant', reason: 'operational status is untouched');
      expect(farm.count(FarmModule.milkProduction), milkBefore, reason: 'production records are never changed');
      expect(c['temperature'], '', reason: 'an unmeasured temperature stays blank');
      // Low severity starts as "Symptoms reported".
      final low = await farm.add(FarmModule.illness, {
        'animal': 'AN-1006 · Kali',
        'noticedAt': dt(0),
        'reportedAt': dt(0),
        'reportedBy': 'X',
        'symptoms': 'Runny nose',
        'appetite': 'Normal',
        'water': 'Normal',
        'milkChange': 'Not checked',
        'severity': 'Low'
      });
      expect(low['stage'], FarmModule.healthSymptoms);
    });

    test('2. updating an illness record keeps its id and creation time', () async {
      final c = await reportRani();
      final created = c['_createdAt'];
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await farm.update(FarmModule.illness, FarmRecord({...c.data, 'symptoms': 'Coughing, not eating, nasal discharge', 'severity': 'Low'}));
      final after = illness(c.id);
      expect(after['symptoms'], contains('nasal discharge'));
      expect(after['_createdAt'], created);
      expect('${after['_updatedAt']}'.compareTo('$created'), greaterThan(0));
      expect(after['stage'], FarmModule.healthSymptoms, reason: 'stage follows the new severity');
    });

    test('3. health records are restored after an app restart', () async {
      final c = await reportRani();
      await farm.add(
          FarmModule.consultations, {'illness': '${c.id} · Rani', 'date': d(0), 'vetName': 'Dr. Vet', 'observations': 'Fever', 'diagnosis': 'Pneumonia', 'diagnosisStatus': FarmModule.diagSuspected});
      final restarted = FarmController(LocalStorageService.instance, clock: () => today);
      await restarted.init();
      final again = restarted.find(FarmModule.illness, c.id)!;
      expect(again['symptoms'], 'Coughing, not eating');
      expect(again['diagnosisStatus'], FarmModule.diagSuspected);
      expect(restarted.count(FarmModule.consultations), farm.count(FarmModule.consultations));
      expect(restarted.find(FarmModule.animals, 'AN-1002')!['healthStatus'], FarmModule.healthFollowUp);
    });

    test('4. an illness links to an existing, active animal only', () async {
      final c = await reportRani();
      expect(animal('AN-1002').isReferencedBy(c['animal']), isTrue);
      expect(HealthAnalytics(farm, today: today).casesFor(animal('AN-1002')).map((x) => x.id), contains(c.id));
      expect(
          () => farm.add(FarmModule.illness, {'animal': 'AN-9999 · Ghost', 'noticedAt': dt(0), 'reportedAt': dt(0), 'reportedBy': 'x', 'symptoms': 'x', 'severity': 'Low'}), rule('Choose an animal'));
      await farm.archive(FarmModule.animals, animal('AN-1006'));
      expect(() => farm.add(FarmModule.illness, {'animal': 'AN-1006 · Kali', 'noticedAt': dt(0), 'reportedAt': dt(0), 'reportedBy': 'x', 'symptoms': 'x', 'severity': 'Low'}), rule('active animal'));
      expect(() => farm.remove(FarmModule.animals, 'AN-1002'), rule('cannot be deleted'));
    });

    test('5. symptoms are recorded without any diagnosis — a suspected cause is not one', () async {
      final c = await reportRani();
      expect(c['diagnosisStatus'], FarmModule.diagNotEvaluated);
      expect(c['diagnosis'], '');
      expect(c['suspectedCause'], 'Pneumonia');
    });
  });

  group('6: veterinary consultation and diagnosis', () {
    test('diagnosis comes only from the vet, is never silently confirmed, and the report is kept', () async {
      final c = await reportRani();
      final ref = '${c.id} · Rani';
      await farm.add(
          FarmModule.consultations, {'illness': ref, 'date': d(0), 'vetName': 'Dr. Vet', 'observations': 'Crackles in chest', 'diagnosis': 'Pneumonia', 'diagnosisStatus': FarmModule.diagSuspected});
      expect(illness(c.id)['diagnosisStatus'], FarmModule.diagSuspected);
      expect(illness(c.id)['stage'], FarmModule.healthFollowUp);
      // Confirming needs the vet's name and the diagnosis.
      expect(() => farm.add(FarmModule.consultations, {'illness': ref, 'date': d(0), 'vetName': '', 'observations': 'x', 'diagnosis': 'Pneumonia', 'diagnosisStatus': FarmModule.diagConfirmed}),
          rule('confirmed diagnosis'));
      expect(() => farm.add(FarmModule.consultations, {'illness': ref, 'date': d(0), 'vetName': 'Dr. Vet', 'observations': 'x', 'diagnosis': '', 'diagnosisStatus': FarmModule.diagConfirmed}),
          rule('confirmed diagnosis'));
      await farm.add(FarmModule.consultations,
          {'illness': ref, 'date': d(0), 'vetName': 'Dr. Vet', 'observations': 'X-ray', 'diagnosis': 'Bacterial pneumonia', 'diagnosisStatus': FarmModule.diagConfirmed, 'fee': '700'});
      final after = illness(c.id);
      expect(after['diagnosisStatus'], FarmModule.diagConfirmed);
      expect(after['diagnosis'], 'Bacterial pneumonia');
      expect(after['symptoms'], 'Coughing, not eating', reason: 'original report preserved');
      expect(after['suspectedCause'], 'Pneumonia');
      expect(() => farm.add(FarmModule.consultations, {'illness': ref, 'date': d(-1), 'vetName': 'Dr. Vet', 'observations': 'x', 'diagnosisStatus': FarmModule.diagNotEvaluated}), rule('future'));
    });
  });

  group('7–9: treatment, medication and stock', () {
    Future<FarmRecord> treat(String illnessRef, {String stockItem = 'Oxytetracycline Inj.', String perDose = '1'}) => farm.add(FarmModule.treatments, {
          'illness': illnessRef,
          'startDate': d(0),
          'endDate': d(-2),
          'medicine': 'Oxytetracycline Inj.',
          'medicineType': 'Antibiotic',
          'dose': '10',
          'doseUnit': 'ml',
          'route': 'Intramuscular (IM)',
          'frequency': 'Once daily for 3 days',
          'prescribedBy': 'Dr. Vet',
          'stockItem': stockItem,
          'stockPerDose': perDose,
          'withdrawalDays': '3',
          'outcome': FarmModule.treatmentOngoing,
        });

    test('7. a treatment plan moves the case to treatment and holds back milk', () async {
      final c = await reportRani();
      final t = await treat('${c.id} · Rani');
      expect(t['animal'], 'AN-1002 · Rani', reason: 'animal comes from the illness case');
      expect(illness(c.id)['stage'], FarmModule.healthTreatment);
      expect(animal('AN-1002')['healthStatus'], FarmModule.healthTreatment);
      final milk = await farm.add(FarmModule.milkProduction, {'date': d(0), 'animal': 'AN-1002 · Rani', 'shift': 'Evening', 'litres': '6', 'quality': 'Accepted'});
      expect(milk['quality'], FarmModule.qualityWithheld);
      expect(
          () => farm.add(FarmModule.treatments, {
                'illness': '${c.id} · Rani',
                'startDate': d(0),
                'endDate': d(2),
                'medicine': 'X',
                'medicineType': 'Other',
                'dose': '1',
                'doseUnit': 'ml',
                'frequency': 'once',
                'prescribedBy': 'V',
                'outcome': 'Ongoing'
              }),
          rule('before the start'));
    });

    test('8. medication administration: given, delayed, missed, discontinued and scheduled', () async {
      final c = await reportRani();
      final t = await treat('${c.id} · Rani', stockItem: '');
      final ref = '${t.id} · ${t['medicine']} · Rani';
      final given = await farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medGiven, 'givenAt': dt(0, '08:00'), 'administeredBy': 'Sabbir'});
      expect(given['doseGiven'], '10 ml', reason: 'defaults to the prescribed dose');
      expect(given['illness'], '${c.id} · Rani');
      expect(() => farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medMissed, 'scheduledAt': dt(0, '20:00')}), rule('reason'));
      await farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medMissed, 'scheduledAt': dt(0, '20:00'), 'reason': 'Animal could not be caught'});
      expect(() => farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medDelayed, 'givenAt': dt(0, '10:00'), 'administeredBy': 'S'}), rule('reason'));
      expect(() => farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medScheduled}), rule('scheduled'));
      await farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medDiscontinued, 'scheduledAt': dt(-1), 'reason': 'Vet stopped the course'});
      expect(farm.find(FarmModule.treatments, t.id)!['outcome'], FarmModule.treatmentOngoing, reason: 'a dose record never changes the treatment plan');
      expect(() => farm.add(FarmModule.medication, {'treatment': 'TR-9 · x', 'status': FarmModule.medGiven, 'givenAt': dt(0), 'administeredBy': 'S'}), rule('treatment plan'));
    });

    test('9. medicine from stock is taken once — edits and repeat saves never deduct twice', () async {
      final c = await reportRani();
      final t = await treat('${c.id} · Rani');
      final ref = '${t.id} · ${t['medicine']} · Rani';
      final before = stock('Oxytetracycline Inj.').number('qty');
      final dose = await farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medGiven, 'givenAt': dt(0, '08:00'), 'administeredBy': 'Sabbir'});
      expect(stock('Oxytetracycline Inj.').number('qty'), before - 1);
      expect(farm.find(FarmModule.inventoryTx, 'TX-${dose.id}')!['type'], FarmModule.txTreatment);

      // Repeated save of the same record, and an edit, leave stock unchanged.
      await farm.update(FarmModule.medication, farm.find(FarmModule.medication, dose.id)!);
      await farm.update(FarmModule.medication, FarmRecord({...farm.find(FarmModule.medication, dose.id)!.data, 'givenAt': dt(0, '08:30')}));
      expect(stock('Oxytetracycline Inj.').number('qty'), before - 1);
      expect(farm.list(FarmModule.inventoryTx).where((x) => x['reference'] == dose.id), hasLength(1));

      // A second submit of the same dose is refused.
      expect(() => farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medGiven, 'givenAt': dt(0, '08:30'), 'administeredBy': 'Sabbir'}), rule('already recorded'));

      // Changing the plan's stock-per-dose later does not change what that dose took.
      await farm.update(FarmModule.treatments, FarmRecord({...farm.find(FarmModule.treatments, t.id)!.data, 'stockPerDose': '2'}));
      await farm.update(FarmModule.medication, FarmRecord({...farm.find(FarmModule.medication, dose.id)!.data, 'status': FarmModule.medMissed, 'reason': 'Recorded by mistake'}));
      expect(stock('Oxytetracycline Inj.').number('qty'), before, reason: 'a Missed dose gives the stock back');
      await farm.update(FarmModule.medication, FarmRecord({...farm.find(FarmModule.medication, dose.id)!.data, 'status': FarmModule.medGiven}));
      expect(stock('Oxytetracycline Inj.').number('qty'), before - 2, reason: 'now uses the updated 2 per dose');
      await farm.remove(FarmModule.medication, dose.id);
      expect(stock('Oxytetracycline Inj.').number('qty'), before);
      expect(() => farm.remove(FarmModule.inventoryTx, 'TX-MA-02'), rule('medication record'));

      // Not enough stock: refused, nothing changes.
      await farm.update(FarmModule.treatments, FarmRecord({...farm.find(FarmModule.treatments, t.id)!.data, 'stockPerDose': '500'}));
      expect(() => farm.add(FarmModule.medication, {'treatment': ref, 'status': FarmModule.medGiven, 'givenAt': dt(0, '09:00'), 'administeredBy': 'S'}), rule('in stock'));
      expect(stock('Oxytetracycline Inj.').number('qty'), before);
    });
  });

  group('10–12: follow-up, no automatic recovery, recovery', () {
    test('10. follow-ups are scheduled, flagged when overdue, and completed with progress', () async {
      final c = await reportRani(severity: 'Low');
      final ref = '${c.id} · Rani';
      final f = await farm.add(FarmModule.followUps, {'illness': ref, 'dueDate': d(1), 'type': 'Farm check', 'status': 'Scheduled'});
      expect(illness(c.id)['stage'], FarmModule.healthFollowUp);
      final h = HealthAnalytics(farm, today: today);
      expect(h.overdueFollowUps.map((x) => x.id), contains(f.id));
      expect(h.activitiesOn().any((a) => a.recordId == f.id && a.overdue), isTrue);
      final alerts = AlertsController(farm: farm, auth: auth, clock: () => today);
      expect(alerts.active.where((a) => a.id.startsWith('followup:${f.id}')), hasLength(1));
      // Editing the record does not duplicate the reminder.
      await farm.update(FarmModule.followUps, FarmRecord({...farm.find(FarmModule.followUps, f.id)!.data, 'assignedTo': 'Rahim'}));
      expect(AlertsController(farm: farm, auth: auth, clock: () => today).active.where((a) => a.id.startsWith('followup:${f.id}')), hasLength(1));
      expect(() => farm.update(FarmModule.followUps, FarmRecord({...farm.find(FarmModule.followUps, f.id)!.data, 'status': 'Done', 'doneDate': d(0)})), rule('improved'));
      await farm.update(FarmModule.followUps, FarmRecord({...farm.find(FarmModule.followUps, f.id)!.data, 'status': 'Done', 'doneDate': d(0), 'progress': 'Improved', 'observations': 'Eating again'}));
      expect(HealthAnalytics(farm, today: today).overdueFollowUps.map((x) => x.id), isNot(contains(f.id)));
      expect(illness(c.id)['stage'], FarmModule.healthFollowUp, reason: 'still needs an explicit recovery decision');
    });

    test('11. a passed treatment end date never marks the animal recovered', () async {
      final ic = IllnessController('IL-01', farm: farm, auth: auth, clock: () => today);
      final t = farm.find(FarmModule.treatments, 'TR-01')!;
      expect(t.dateOf('endDate')!.isBefore(today.add(const Duration(days: 30))), isTrue);
      final later = FarmController(LocalStorageService.instance, clock: () => today.add(const Duration(days: 30)));
      await later.init();
      final case1 = later.find(FarmModule.illness, 'IL-01')!;
      expect(HealthRules.stage(later, case1.data), FarmModule.healthTreatment);
      expect(HealthRules.animalStatus(later, later.find(FarmModule.animals, 'AN-1004')!), isNot(FarmModule.healthRecovered));
      expect(ic.isOpen, isTrue);
    });

    test('12. recovery is recorded explicitly by an owner/manager; history is kept; cases can be reopened', () async {
      final ic = IllnessController('IL-01', farm: farm, auth: auth, clock: () => today);
      // Blocked while the treatment is ongoing and a follow-up is scheduled.
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: 'Udder normal', confirmed: true), contains('still ongoing'));
      final t = farm.find(FarmModule.treatments, 'TR-01')!;
      expect(() => farm.update(FarmModule.treatments, FarmRecord({...t.data, 'outcome': 'Discontinued by vet'})), rule('reason'));
      await farm.update(FarmModule.treatments, FarmRecord({...t.data, 'outcome': 'Completed'}));
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: 'Udder normal', confirmed: true), contains('still scheduled'));
      final f = farm.find(FarmModule.followUps, 'FU-01')!;
      await farm.update(FarmModule.followUps, FarmRecord({...f.data, 'dueDate': d(0), 'status': 'Done', 'doneDate': d(0), 'progress': 'Improved'}));
      // A signed-out user cannot close a case; confirmation and notes are required.
      await auth.logout();
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: 'Udder normal', confirmed: true), contains('Only the Farm Owner'));
      await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: 'Udder normal', confirmed: false), contains('Confirm'));
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: '', confirmed: true), contains('notes'));
      expect(await ic.close(outcome: FarmModule.closeRecovered, date: today, notes: 'Udder normal, milk clear', confirmed: true), isNull);
      final closed = illness('IL-01');
      expect(closed['closure'], FarmModule.closeRecovered);
      expect(closed['stage'], FarmModule.healthRecovered);
      expect(animal('AN-1004')['healthStatus'], FarmModule.healthRecovered);
      expect(farm.find(FarmModule.consultations, 'VC-01'), isNotNull, reason: 'history kept');
      expect(farm.list(FarmModule.medication).where((m) => FarmRecord.refId(m['illness']) == 'il-01'), isNotEmpty);
      // A closed case takes no new treatment until reopened.
      expect(() => farm.add(FarmModule.followUps, {'illness': 'IL-01 · Moti', 'dueDate': d(-1), 'type': 'Farm check', 'status': 'Scheduled'}), rule('closed'));
      expect(await ic.reopen('Swelling returned'), isNull);
      final reopened = illness('IL-01');
      expect(reopened['closure'], '');
      expect(reopened['reopenedCount'], '1');
      expect(reopened['notes'], contains('Previous outcome: Recovered'));
      expect(reopened['stage'], FarmModule.healthFollowUp);
    });
  });

  group('13–16: search, invalid input, malformed data, regression', () {
    test('13. health dashboard search and filters', () async {
      await reportRani(severity: 'Emergency', danger: 'Severe breathing difficulty');
      final h = HealthAnalytics(farm, today: today);
      expect(h.rows(const HealthFilter(query: 'rani')).map((r) => r.animal.id), ['AN-1002']);
      expect(h.rows(const HealthFilter(query: 'BD-1004')).single.animal.id, 'AN-1004');
      expect(h.rows(const HealthFilter(status: FarmModule.healthTreatment)).map((r) => r.animal.id), ['AN-1004', 'AN-1008']);
      expect(h.rows(const HealthFilter(treatment: 'Active treatment')).map((r) => r.animal.id), ['AN-1004', 'AN-1008']);
      expect(h.rows(const HealthFilter(species: 'Goat')).map((r) => r.animal.id), ['AN-1006']);
      expect(h.rows(const HealthFilter(vet: 'Dr. Karim Ali')).map((r) => r.animal.id), containsAll(['AN-1004', 'AN-1005']));
      expect(h.rows(HealthFilter(from: today.subtract(const Duration(days: 45)), to: today.subtract(const Duration(days: 35)))).map((r) => r.animal.id), ['AN-1005']);
      // Urgent animals are listed first.
      expect(h.rows(const HealthFilter()).first.animal.id, 'AN-1002');
      expect(h.urgentAnimalCount, 1);
      final list = RecordsController(FarmModule.illness, farm: farm, auth: auth)..setQuery('limping');
      expect(list.filtered.single['animal'], 'AN-1003 · Badsha');
      // Reports read only saved records, and CSV matches the screen.
      final r = ReportsController(farm: farm, auth: auth, clock: () => today)..applyPreset('All time');
      for (final k in ReportKind.values.where((k) => k.name.startsWith('health'))) {
        r.setKind(k);
        final t = r.build();
        expect(t.toCsv().split('\n'), hasLength(t.rows.length + 1), reason: k.label);
      }
      r.setKind(ReportKind.healthSick);
      expect(r.build().rows.map((x) => x.first), containsAll(['IL-01', 'IL-03']));
      r.setQuery('badsha');
      expect(r.build().rows, hasLength(1));
    });

    test('14. invalid or missing input is rejected with a clear message', () async {
      Map<String, dynamic> base() => {'animal': 'AN-1002 · Rani', 'noticedAt': dt(0, '06:00'), 'reportedAt': dt(0, '07:00'), 'reportedBy': 'S', 'symptoms': 'Cough', 'severity': 'Low'};
      expect(() => farm.add(FarmModule.illness, {...base(), 'noticedAt': dt(-2)}), rule('future'));
      expect(() => farm.add(FarmModule.illness, {...base(), 'reportedAt': dt(1)}), rule('before the symptoms'));
      expect(() => farm.add(FarmModule.illness, {...base(), 'temperature': '39.5'}), rule('unit'));
      expect(() => farm.add(FarmModule.illness, {...base(), 'temperature': '395', 'tempUnit': '°C'}), rule('not possible'));
      await farm.add(FarmModule.illness, {...base(), 'temperature': '103', 'tempUnit': '°F'});
      expect(() => farm.add(FarmModule.illness, {...base(), 'temperature': '103', 'tempUnit': '°F'}), rule('already reported'));
      expect(() => farm.add(FarmModule.followUps, {'illness': 'IL-99 · x', 'dueDate': d(0), 'type': 'Farm check', 'status': 'Scheduled'}), rule('existing illness'));
      // The form controller validates before saving.
      final form = RecordFormController(module: FarmModule.illness, farm: farm, auth: auth, clock: () => today);
      expect(form.valueOf('appetite'), 'Not checked', reason: 'unknown observations are never assumed normal');
      expect(form.valueOf('temperature'), '');
      expect(form.validate('severity', ''), contains('choose'));
      expect(form.validate('noticedAt', '2026-10-10'), contains('date and time'));
      expect(form.validate('temperature', 'hot'), contains('number'));
      expect(form.isVisible('tempUnit'), isFalse);
      form.setValue('severity', 'Emergency');
      expect(form.isEmergency, isTrue);
      expect(form.illnessAdvice, contains('veterinarian immediately'));
      form.dispose();
    });

    test('15. malformed stored data never crashes the app and is kept aside', () async {
      await mockStorage({
        'records_Animals': '[{"id":"AN-1","name":"Old Cow","species":"Cattle","sex":"Female","status":"Active"}]',
        'records_${FarmModule.illness}': '{not valid json',
        'records_${FarmModule.followUps}': '[42, "text", {"id":"FU-1","illness":"IL-1 · x","dueDate":"2026-10-01","status":"Scheduled"}]',
        'records_${FarmModule.treatments}': '[{"medicine":"No id"}]',
      });
      final f = FarmController(LocalStorageService.instance, clock: () => today);
      await f.init();
      expect(f.count(FarmModule.illness), 0);
      expect(f.count(FarmModule.followUps), 1, reason: 'valid entries are kept');
      expect(f.list(FarmModule.treatments).single.id, startsWith('REPAIRED-'));
      expect(f.find(FarmModule.animals, 'AN-1')!['healthStatus'], FarmModule.healthHealthy);
      final store = await openStorage();
      final kept = store.keys.where((k) => k.startsWith('unreadable_records_${FarmModule.illness}'));
      expect(kept, hasLength(1));
      expect(store.readValue(kept.single), '{not valid json', reason: 'the original text is preserved');
      expect(f.activity.any((a) => a.title.contains('could not be read')), isTrue);
    });

    test('16. existing modules still work: costs, feed, milk and integrity', () async {
      final e = FinanceEngine(farm, ReportFilter(from: today.subtract(const Duration(days: 45)), to: today));
      final units = {for (final p in e.unitProfits) p.unit.id: p};
      // Moti: treatment 1 200 + consultation 500; Lali: treatment 450 + consultation 300.
      expect(units['AN-1004']!.cost(FinanceEngine.catTreatment), 1700);
      expect(units['AN-1005']!.cost(FinanceEngine.catTreatment), 1750); // + navel-ill treatment 600 and consultation 400
      // Medicine taken from stock is not costed again.
      // Cattle, goat and sheep vaccinations: anthrax 50, HS 60, PPR 40.
      expect(e.profitAndLoss.costsByCategory[FinanceEngine.catTreatment], 1700 + 1750 + 85 + 150 + 50 + 60 + 650 + 310 + 550 + 40 + 85 + 60);
      // Duplicate cost entry is refused.
      expect(
          () => farm
              .add(FarmModule.expenses, {'date': d(1), 'category': 'Veterinary treatment', 'amount': '500', 'description': 'Vet', 'scope': 'Animal', 'animal': 'AN-1004 · Moti', 'payment': 'Paid'}),
          rule('already counted'));
      // Feed and milk keep working, and the illness modules don't change them.
      final feedBefore = farm.count(FarmModule.feedRecords);
      await reportRani();
      expect(farm.count(FarmModule.feedRecords), feedBefore);
      expect(HealthAnalytics(farm, today: today).productionReview(animal('AN-1003')).where((r) => r.metric == 'Milk'), isEmpty, reason: 'a bull is never compared on milk');
      expect(HealthAnalytics(farm, today: today).productionReview(animal('AN-1001')).map((r) => r.metric), containsAll(['Milk', 'Feed intake']));
      expect(() => farm.remove(FarmModule.illness, 'IL-01'), rule('cannot be deleted'));
      expect(() => farm.remove(FarmModule.treatments, 'TR-01'), rule('cannot be deleted'));
      // Demo stock history still adds up after medicine issues.
      expect(stock('Oxytetracycline Inj.').number('qty'), 6);
    });
  });

  test('emergency and danger signs are urgent, with a vet warning — never a diagnosis', () async {
    final c = await reportRani(severity: 'Moderate', danger: 'Collapse / cannot get up');
    expect(HealthRules.isUrgent(farm, c), isTrue);
    final advice = HealthRules.severityAdvice('Moderate', dangerSigns: true);
    expect(advice, contains('veterinarian immediately'));
    for (final s in FarmModule.severities) {
      final text = HealthRules.severityAdvice(s);
      expect(text.toLowerCase(), isNot(contains('diagnos')), reason: s);
      expect(text.toLowerCase(), isNot(contains('healthy')), reason: s);
    }
    final alerts = AlertsController(farm: farm, auth: auth, clock: () => today).active;
    expect(alerts.any((a) => a.title.startsWith('URGENT: Rani')), isTrue);
    expect(alerts.any((a) => a.title == 'Badsha: awaiting veterinary assessment'), isFalse, reason: 'low severity is not pending assessment');
    expect(alerts.any((a) => a.title.contains('Moti') && a.title.contains('dose')), isTrue, reason: 'scheduled dose reminder');
    expect(alerts.any((a) => a.title.contains('Moti: vet appointment')), isFalse, reason: 'the visit is 2 days away; the default lead time is 1 day');
    await farm.updateProfile(farm.profile.copyWith(reminderLeadDays: 3));
    final later = AlertsController(farm: farm, auth: auth, clock: () => today).active;
    expect(later.any((a) => a.title.contains('Moti: vet appointment')), isTrue);
  });

  test('regression: a fresh install keeps every module after a restart', () async {
    final counts = {for (final m in farm.modules) m: farm.count(m)};
    final restarted = FarmController(LocalStorageService.instance, clock: () => today);
    await restarted.init();
    for (final m in farm.modules) {
      expect(restarted.count(m), counts[m], reason: m);
    }
  });
}
