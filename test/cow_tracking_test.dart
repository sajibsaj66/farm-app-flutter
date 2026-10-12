import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/cow_profile_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/herd_analytics.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/core/utils/dates.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  late FarmController farm;
  late AuthController auth;
  final today = DateTime(2026, 10, 10);
  String d(int daysAgo) => formatDate(today.subtract(Duration(days: daysAgo)));

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => today);
    auth = AuthController(LocalStorageService.instance);
    await farm.init();
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  });

  FarmRecord animal(String id) => farm.find(FarmModule.animals, id)!;
  CowAnalytics cow(String id) => CowAnalytics(farm, animal(id), today: today);
  FarmRecord stock(String name) => farm.feedItem(name)!;

  group('feed consumed per cow', () {
    test('individual rations are counted per cow with cost from Inventory', () {
      final shona = cow('AN-1001').period(7);
      // 7 days × (6 kg concentrate + 25 kg Napier grass), plus her third of
      // this week's lactating-cow group ration (15 kg wheat bran + 5 kg molasses).
      expect(shona.feedKg, closeTo(7 * 31 + (15 + 5) / 3, 0.001));
      expect(shona.feedCost, closeTo(7 * (6 * 46 + 25 * 6) + (15 * 44 + 5 * 35) / 3, 0.001));
      expect(shona.feedCostIncomplete, isFalse);
    });

    test('group rations are shared equally between the animals in the group', () {
      final badsha = cow('AN-1003').feedShares;
      expect(badsha, isNotEmpty);
      expect(badsha.every((f) => f.shared && (f.kg == 30 || f.kg == 40)), isTrue, reason: 'only bull in the Bulls group (Napier daily, rice straw weekly)');
      expect(cow('AN-1005').period(7).feedKg, closeTo(7 * 1.5, 0.001), reason: 'the only calf');

      // A second calf halves the share.
      return farm.add(FarmModule.animals, {'name': 'Tuni', 'type': 'Calf', 'sex': 'Female', 'group': 'Calves', 'status': 'Active'}).then((_) {
        expect(cow('AN-1005').period(7).feedKg, closeTo(7 * 0.75, 0.001));
      });
    });
  });

  group('milk produced per cow', () {
    test('period totals, daily average and feed efficiency', () {
      final shona = cow('AN-1001');
      final week = shona.period(7);
      final expected = farm.list(FarmModule.milkProduction).where((m) => m['animal'] == 'AN-1001 · Shona' && '${m['date']}'.compareTo(d(6)) >= 0).fold(0.0, (s, m) => s + m.number('litres'));
      expect(week.milk, closeTo(expected, 0.001));
      expect(week.daysWithMilk, 7);
      expect(week.avgMilkPerDay, closeTo(expected / 7, 0.001));
      expect(week.feedPerLitre, closeTo(week.feedKg / week.milk, 0.0001));
      expect(week.milkIncome, closeTo(week.sellableMilk * 120, 0.001));
      expect(week.margin, closeTo(week.milkIncome - week.feedCost - week.healthCost - week.breedingCost, 0.001));
    });

    test('daily series lines up milk and feed by date', () {
      final points = cow('AN-1001').daily(14);
      expect(points, hasLength(14));
      expect(formatDate(points.last.day), d(0));
      // 31 kg a day, plus a third of the weekly group ration on its days.
      expect(points.every((p) => p.milk > 0 && ((p.feed - 31).abs() < 1e-9 || (p.feed - (31 + 20 / 3)).abs() < 1e-9)), isTrue);
    });

    test('milk in a withdrawal period is withheld and not counted as income', () {
      final moti = cow('AN-1004');
      expect(moti.withdrawalUntil, today.add(const Duration(days: 3)));
      final week = moti.period(7);
      expect(week.withheldMilk, greaterThan(0));
      expect(week.sellableMilk, lessThan(week.milk));
    });
  });

  group('business rules on save', () {
    test('milk recorded during withdrawal is forced to Withheld', () async {
      final moti = await farm.add(FarmModule.milkProduction, {'date': d(0), 'animal': 'AN-1004 · Moti', 'shift': 'Morning', 'litres': '5', 'quality': 'Accepted'});
      expect(moti['quality'], FarmModule.qualityWithheld);
      final shona = await farm.add(FarmModule.milkProduction, {'date': d(0), 'animal': 'AN-1001 · Shona', 'shift': 'Morning', 'litres': '5', 'quality': 'Accepted'});
      expect(shona['quality'], 'Accepted');
      // After the withdrawal period ends the milk may be sold again.
      final later =
          await farm.add(FarmModule.milkProduction, {'date': formatDate(today.add(const Duration(days: 3))), 'animal': 'AN-1004 · Moti', 'shift': 'Morning', 'litres': '5', 'quality': 'Accepted'});
      expect(later['quality'], 'Accepted');
    });

    test('feed entries take stock from Inventory, and give it back when edited or deleted', () async {
      final before = stock('Mineral Mixture').number('qty');
      final entry = await farm.add(FarmModule.feedRecords, {'date': d(0), 'animal': 'AN-1001 · Shona', 'group': '', 'feed': 'Mineral Mixture', 'qty': '4', 'shift': 'Morning'});
      expect(stock('Mineral Mixture').number('qty'), before - 4);
      await farm.update(FarmModule.feedRecords, FarmRecord({...entry.data, 'qty': '10'}));
      expect(stock('Mineral Mixture').number('qty'), before - 10);
      await farm.remove(FarmModule.feedRecords, entry.id);
      expect(stock('Mineral Mixture').number('qty'), before);
    });

    test('stock status follows quantity (changed only through stock transactions)', () async {
      final item = stock('Calf Starter');
      // Editing the item cannot change its stock directly.
      await farm.update(FarmModule.inventory, FarmRecord({...item.data, 'qty': '0'}));
      expect(stock('Calf Starter').number('qty'), 45);
      await farm.add(FarmModule.inventoryTx, {'date': d(0), 'item': 'Calf Starter', 'type': FarmModule.txCount, 'quantity': '0'});
      expect(stock('Calf Starter').status, 'Out of stock');
      await farm.add(FarmModule.inventoryTx, {'date': d(0), 'item': 'Calf Starter', 'type': FarmModule.txPurchase, 'quantity': '10', 'unitCost': '75'});
      expect(stock('Calf Starter').status, 'Low stock');
      expect(stock('Calf Starter').number('unitCost'), 75);
    });

    test('an AI service uses one semen straw and fills in the bull', () async {
      final service = await farm.add(FarmModule.breeding,
          {'animal': 'AN-1004 · Moti', 'date': d(0), 'method': 'AI', 'semen': 'SEM-7802', 'bull': '', 'technician': 'Rahim', 'result': FarmModule.resultPending, 'calvingDate': '', 'cost': ''});
      expect(service['bull'], 'BULL-025 · Raja');
      expect(farm.semenByCode('SEM-7802')!.number('straws'), 14);
      await farm.remove(FarmModule.breeding, service.id);
      expect(farm.semenByCode('SEM-7802')!.number('straws'), 15);
    });

    test('using the last straw marks the batch Used up', () async {
      for (var i = 0; i < 2; i++) {
        await farm.add(FarmModule.breeding, {'animal': 'AN-1004 · Moti', 'date': d(0), 'method': 'AI', 'semen': 'SEM-7720', 'result': FarmModule.resultPending});
      }
      expect(farm.semenByCode('SEM-7720')!.status, 'Used up');
    });

    test('a weight record updates the animal’s current weight', () async {
      await farm.add(FarmModule.weights, {'date': d(0), 'animal': 'AN-1001 · Shona', 'weight': '426', 'bcs': '3'});
      expect(animal('AN-1001')['weight'], '426');
      expect(cow('AN-1001').averageDailyGain, closeTo((426 - 405) / 90, 0.0001));
    });
  });

  group('form validation for cow records', () {
    test('feed needs an animal or a group, and cannot exceed stock', () {
      final form = RecordFormController(module: FarmModule.feedRecords, farm: farm, auth: auth, clock: () => today, initialValues: const {'feed': 'Mineral Mixture'});
      expect(form.validate('group', ''), contains('an animal or a group'));
      expect(form.validate('qty', '35'), contains('Only 34 kg'));
      expect(form.validate('qty', '20'), isNull);
      form.dispose();
    });

    test('AI needs a semen batch with straws left', () async {
      final form = RecordFormController(module: FarmModule.breeding, farm: farm, auth: auth, clock: () => today, initialValues: const {'method': 'AI'});
      expect(form.validate('semen', ''), contains('semen batch'));
      form.dispose();
      final semen = farm.semenByCode('SEM-7720')!;
      await farm.update(FarmModule.semen, FarmRecord({...semen.data, 'straws': '0'}));
      final again = RecordFormController(module: FarmModule.breeding, farm: farm, auth: auth, clock: () => today, initialValues: const {'method': 'AI'});
      expect(again.validate('semen', 'SEM-7720'), contains('No straws'));
      again.dispose();
    });

    test('profile shortcuts pre-fill the animal', () {
      final form = RecordFormController(module: FarmModule.milkProduction, farm: farm, auth: auth, clock: () => today, initialValues: const {'animal': 'AN-1001 · Shona'});
      expect(form.valueOf('animal'), 'AN-1001 · Shona');
      expect(form.valueOf('date'), d(0));
      form.dispose();
    });

    test('older records keep extra columns when edited', () {
      final old = FarmRecord({'id': 'AN-9', 'name': 'Old', 'age': '3 years'});
      expect(FarmModule.fieldsFor(FarmModule.animals, old.data), contains('age'));
      expect(FarmModule.fieldsFor(FarmModule.animals, old.data).first, 'name');
    });
  });

  group('reproduction history', () {
    test('Shona: calved 75 days ago, served again, pregnancy check due', () {
      final shona = cow('AN-1001');
      expect(shona.lastCalving, today.subtract(const Duration(days: 75)));
      expect(shona.daysInMilk, 75);
      expect(shona.lactationStage, 'Early lactation');
      expect(shona.currentCycleServices, hasLength(1));
      expect(shona.pendingCheck?.id, 'BR-2005');
      expect(shona.reproStatus, contains('pregnancy check due'));
      expect(shona.offspring.single['name'], 'Lali');
    });

    test('Rani: conceived on the second service, calving date estimated', () {
      final rani = cow('AN-1002');
      expect(rani.servicesPerConceptionHistory, [2]);
      expect(rani.avgServicesPerConception, 2);
      expect(rani.expectedCalving, today.subtract(const Duration(days: 108)).add(const Duration(days: Repro.gestationDays)));
      expect(rani.reproStatus, startsWith('Pregnant'));
    });

    test('herd breeding summary', () {
      final b = HerdAnalytics(farm, today: today).breeding;
      expect(b.services, 10);
      expect(b.conceptions, 3); // Shona calved, Rani and Mohini confirmed
      expect(b.conceptionRate, 0.3);
      expect(b.pregnant, 2);
    });

    test('recording a calving registers the calf with its parents', () async {
      final c = CowProfileController('AN-1002', farm: farm, auth: auth, clock: () => today);
      expect(await c.recordCalving(date: today, calfName: '', sex: 'Male'), contains('name'));
      expect(await c.recordCalving(date: today, calfName: 'Raju', sex: 'Male', tag: 'BD-2001', birthWeight: 32), isNull);

      final calf = farm.list(FarmModule.animals).firstWhere((a) => a['name'] == 'Raju');
      expect(calf['dam'], 'AN-1002 · Rani');
      expect(calf['sire'], 'BULL-018 · Sultan');
      expect(calf['breed'], 'Sahiwal Cross × Sahiwal');
      expect(calf['weight'], '32');
      expect(farm.find(FarmModule.breeding, 'BR-2003')!.status, FarmModule.resultCalved);
      expect(farm.find(FarmModule.breeding, 'BR-2003')!['calvingDate'], d(0));
      expect(animal('AN-1002')['group'], 'Lactating cows');
      expect(animal('AN-1002').status, 'Active');
      expect(cow('AN-1002').lastCalving, today);
    });
  });

  group('semen suitability (never declared safe on missing data)', () {
    SemenSuitability check(String cowId, String code) => SemenAdvisor(farm, today: today).check(animal(cowId), farm.semenByCode(code)!);

    test('father × daughter is not recommended', () {
      final r = check('AN-1001', 'SEM-7720'); // Hero is Shona's sire
      expect(r.level, SuitabilityLevel.notRecommended);
      expect(r.findings.map((f) => f.text), contains(contains('father × daughter')));
    });

    test('half-siblings through the sire are not recommended', () {
      final r = check('AN-1001', 'SEM-7802'); // Raja's sire is Hero, also Shona's sire
      expect(r.level, SuitabilityLevel.notRecommended);
      expect(r.findings.map((f) => f.text), contains(contains('half-siblings')));
    });

    test('a cow already confirmed pregnant is not recommended', () {
      expect(check('AN-1002', 'SEM-7802').findings.map((f) => f.text), contains(contains('already confirmed pregnant')));
    });

    test('maternal grandsire is detected through the dam', () {
      // Lali's dam is Shona, whose sire is Hero.
      final r = check('AN-1005', 'SEM-7720');
      expect(r.findings.map((f) => f.text), contains(contains('maternal grandsire')));
    });

    test('missing pedigree means "verify", not safe', () {
      final r = check('AN-1001', 'SEM-7781'); // Shona's dam is unknown
      expect(r.level, SuitabilityLevel.verify);
      expect(r.missing, contains('Shona’s dam'));
      expect(r.headline, isNot(contains('safe')));
    });

    test('only complete, unrelated pedigrees show "no conflicts found"', () async {
      await farm.add(FarmModule.animals,
          {'name': 'Kajol', 'type': 'Cow', 'breed': 'Sahiwal Cross', 'sex': 'Female', 'group': 'Lactating cows', 'status': 'Active', 'sire': 'BULL-030 · Babu', 'dam': 'AN-1002 · Rani'});
      final kajol = farm.list(FarmModule.animals).firstWhere((a) => a['name'] == 'Kajol');
      final r = SemenAdvisor(farm, today: today).check(kajol, farm.semenByCode('SEM-7781')!);
      // Rani (the dam) has a recorded sire (Tiger), the bull's parents are known.
      expect(r.missing, isEmpty);
      expect(r.level, SuitabilityLevel.noConflict);
      expect(r.headline, 'No conflicts found in recorded data');
    });

    test('expired or used-up semen is not recommended', () async {
      final s = farm.semenByCode('SEM-7781')!;
      await farm.update(FarmModule.semen, FarmRecord({...s.data, 'expiry': d(1)}));
      expect(check('AN-1004', 'SEM-7781').findings.map((f) => f.text), contains(contains('expired')));
    });
  });

  test('breeding and semen reminders', () {
    final titles = AlertsController(farm: farm, auth: auth, clock: () => today).active.map((a) => a.title).toList();
    expect(titles, contains('Shona: pregnancy check due'));
    expect(titles, contains('Moti: not pregnant — re-breed'));
    expect(titles, contains('Moti: milk withdrawal period'));
    expect(titles, contains('Semen SEM-7720 (Hero) expires soon'));
    expect(titles, contains('Only 2 straws of SEM-7720 (Hero) left'));
    // Rani is due in about 175 days — too far ahead for a reminder.
    expect(titles.any((t) => t.startsWith('Rani: calving')), isFalse);
    final nearCalving = AlertsController(farm: farm, auth: auth, clock: () => today.add(const Duration(days: 160))).active.map((a) => a.title);
    expect(nearCalving.any((t) => t.startsWith('Rani: calving expected in')), isTrue);
  });
}
