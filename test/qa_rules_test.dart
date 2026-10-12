import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/alerts_controller.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/records_controller.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/field_spec.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

/// QA findings: each test reproduces an issue found while reviewing the app.
void main() {
  late FarmController farm;
  late AuthController auth;

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance);
    await farm.init();
    auth = AuthController(LocalStorageService.instance);
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
  });

  FarmRecord first(String module) => farm.list(module).first;

  group('names and codes that other records point at are unique', () {
    for (final (module, field) in const [
      (FarmModule.inventory, 'name'),
      (FarmModule.species, 'name'),
      (FarmModule.locations, 'name'),
      (FarmModule.customers, 'name'),
      (FarmModule.semen, 'code'),
      (FarmModule.animals, 'tag'),
    ]) {
      test('$module: a second "$field" with the same value is refused', () async {
        final existing = farm.list(module).firstWhere((r) => '${r[field] ?? ''}'.isNotEmpty);
        final copy = {...existing.toJson()}..remove('id');
        copy[field] = ' ${'${existing[field]}'.toUpperCase()} ';
        final before = farm.count(module);
        await expectLater(farm.add(module, copy), throwsA(isA<FarmRuleException>().having((e) => e.message, 'message', contains('already'))));
        expect(farm.count(module), before);
        // Saving the record itself unchanged is still fine.
        await farm.update(module, existing);
      });
    }

    test('an animal without a tag never clashes with another untagged animal', () async {
      final a = farm.list(FarmModule.animals).first;
      await farm.add(FarmModule.animals, {...a.toJson()..remove('id'), 'name': 'Untagged 1', 'tag': ''});
      await farm.add(FarmModule.animals, {...a.toJson()..remove('id'), 'name': 'Untagged 2', 'tag': ''});
    });
  });

  group('renaming keeps the records that refer to it', () {
    test('location', () async {
      final loc = farm.byName(FarmModule.locations, '${first(FarmModule.animals)['location']}')!;
      final users = farm.linksTo(FarmModule.locations, loc).length;
      expect(users, greaterThan(0));
      await farm.update(FarmModule.locations, FarmRecord({...loc.toJson(), 'name': 'Renamed Shed'}));
      expect(farm.linksTo(FarmModule.locations, farm.find(FarmModule.locations, loc.id)!), hasLength(users));
      expect(farm.list(FarmModule.animals).where((a) => a['location'] == loc['name']), isEmpty);
    });

    test('species', () async {
      final sp = farm.species('Cattle')!;
      final users = farm.linksTo(FarmModule.species, sp).length;
      await farm.update(FarmModule.species, FarmRecord({...sp.toJson(), 'name': 'Dairy cattle'}));
      expect(farm.linksTo(FarmModule.species, farm.find(FarmModule.species, sp.id)!), hasLength(users));
      expect(farm.list(FarmModule.animals).any((a) => a['species'] == 'Cattle'), isFalse);
    });

    test('customer: sales and payments follow, and the outstanding amount is kept', () async {
      final sale = farm.list(FarmModule.sales).firstWhere((s) => s.number('due') > 0);
      final customer = farm.byName(FarmModule.customers, sale['customer'])!;
      final summary = RecordsController(FarmModule.customers, farm: farm, auth: auth).summaryFor(customer);
      await farm.update(FarmModule.customers, FarmRecord({...customer.toJson(), 'name': 'Renamed Traders'}));
      final renamed = farm.find(FarmModule.customers, customer.id)!;
      expect(farm.find(FarmModule.sales, sale.id)!['customer'], 'Renamed Traders');
      expect(RecordsController(FarmModule.customers, farm: farm, auth: auth).summaryFor(renamed), summary);
      expect(farm.list(FarmModule.collections).any((c) => c['customer'] == customer['name']), isFalse);
    });

    test('animal names in references', () async {
      final shona = farm.find(FarmModule.animals, 'AN-1001')!;
      final milk = farm.list(FarmModule.milkProduction).where((m) => shona.isReferencedBy(m['animal'])).length;
      await farm.update(FarmModule.animals, FarmRecord({...shona.toJson(), 'name': 'Shonali'}));
      expect(farm.list(FarmModule.milkProduction).where((m) => m['animal'] == 'AN-1001 · Shonali'), hasLength(milk));
      expect(farm.list(FarmModule.animals).where((a) => a['dam'] == 'AN-1001 · Shona'), isEmpty, reason: 'calves show the new dam name');
    });

    test('semen code', () async {
      final service = farm.list(FarmModule.breeding).firstWhere((b) => '${b['semen'] ?? ''}'.isNotEmpty);
      final semen = farm.semenByCode(service['semen'])!;
      await farm.update(FarmModule.semen, FarmRecord({...semen.toJson(), 'code': 'NEW-CODE-1'}));
      expect(farm.find(FarmModule.breeding, service.id)!['semen'], 'NEW-CODE-1');
    });
  });

  test('the reorder level must be a number', () {
    expect(FarmModule.specFor(FarmModule.inventory, 'reorder').type, FieldType.number);
  });

  test('a payment-due alert shows the amount still outstanding', () async {
    final alerts = AlertsController(farm: farm, auth: auth);
    final sale = farm.list(FarmModule.sales).firstWhere((s) => s.status == 'Partial');
    final alert = alerts.all.firstWhere((a) => a.id.startsWith('sale:${sale.id}:'));
    expect(alert.message, contains('${sale.number('due').toStringAsFixed(0)} due'));
  });

  test('search looks at what the user sees, not internal bookkeeping', () {
    final records = RecordsController(FarmModule.sales, farm: farm, auth: auth);
    records.setQuery('_createdAt');
    expect(records.filtered, isEmpty);
    records.setQuery('T'); // the "T" of an ISO timestamp is not a match by itself
    final stamp = farm.list(FarmModule.sales).first.toJson()..['_updatedAt'] = 'ZZZ-INTERNAL';
    expect(FarmRecord(stamp).matches(query: 'zzz-internal', filter: 'All'), isFalse);
  });

  test('illness cases and follow-ups list newest first', () {
    for (final (module, field) in const [(FarmModule.illness, 'reportedAt'), (FarmModule.followUps, 'dueDate'), (FarmModule.treatments, 'startDate'), (FarmModule.medication, 'givenAt')]) {
      final rows = RecordsController(module, farm: farm, auth: auth).filtered.map((r) => '${r[field] ?? ''}').where((d) => d.isNotEmpty).toList();
      final sorted = [...rows]..sort((a, b) => b.compareTo(a));
      expect(rows, sorted, reason: module);
    }
  });
}
