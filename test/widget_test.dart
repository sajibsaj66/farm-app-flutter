import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/records_controller.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  test('default module registry includes core farm workflows', () {
    final store = FarmController.instance;
    expect(store.defaults.keys, contains('Animals'));
    expect(store.defaults.keys, contains('Breeding'));
    expect(store.defaults.keys, contains('Milk Production'));
    expect(store.defaults.keys, contains('Inventory'));
  });

  test('every demo module has a FarmModule definition covering its columns', () {
    for (final entry in FarmController.instance.defaults.entries) {
      final module = FarmModule.byName(entry.key);
      expect(module, isNotNull, reason: entry.key);
      for (final row in entry.value) {
        for (final key in row.keys.where((k) => k != 'id' && !FarmModule.isInternal(k))) {
          expect(module!.fields, contains(key), reason: '${entry.key}.$key');
        }
        for (final spec in module!.specs.where((s) => s.required && !s.computed)) {
          expect(row.containsKey(spec.key), isTrue, reason: '${entry.key} ${row['id']} lacks ${spec.key}');
        }
      }
    }
  });

  test('FarmRecord derives title, status, numbers and search matches', () {
    final r = FarmRecord({'id': 'ST-1', 'name': 'Mineral Mixture', 'qty': '34', 'reorder': '40 kg', 'status': 'Low stock'});
    expect(r.title, 'Mineral Mixture');
    expect(r.needsAttention, isTrue);
    expect(r.isLowStock, isTrue);
    expect(FarmRecord.leadingNumber('150 kg'), 150);
    expect(FarmRecord.displayName('AN-1004 · Moti'), 'Moti');
    expect(r.matches(query: 'mineral', filter: 'Low stock'), isTrue);
    expect(r.matches(query: 'mineral', filter: 'Paid'), isFalse);
  });

  test('controller add / update / remove / reset round-trip, with role checks', () async {
    await mockStorage({});
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    final before = farm.count(FarmModule.animals);

    await farm.add(FarmModule.animals, {'name': 'Zebulon', 'status': 'Active'});
    expect(farm.count(FarmModule.animals), before + 1);
    final added = farm.list(FarmModule.animals).first;
    expect(added.id, startsWith('A-'));

    await farm.update(FarmModule.animals, FarmRecord({...added.data, 'status': 'Sold'}));
    expect(farm.list(FarmModule.animals).first.status, 'Sold');

    final auth = AuthController(LocalStorageService.instance);
    await auth.init();
    final manager = RecordsController(FarmModule.animals, farm: farm, auth: auth);
    await auth.login(role: UserRole.manager, username: 'manager', password: 'manager123');
    expect(manager.canDelete, isFalse, reason: 'only the owner deletes');
    expect(() => manager.delete(added), throwsStateError);

    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    final records = RecordsController(FarmModule.animals, farm: farm, auth: auth)..setQuery('zebulon');
    expect(records.filtered, hasLength(1));
    await records.delete(records.filtered.single);
    expect(farm.count(FarmModule.animals), before);

    await farm.reset();
    expect(farm.activity.first.title, startsWith('Demo data loaded'));
    expect(farm.activity.skip(1).every((a) => a.title.startsWith('New ')), isTrue, reason: 'old activity cleared; demo activity loaded');
    expect(farm.activity.length, greaterThanOrEqualTo(11));
  });

  test('record filters come from the statuses actually in the module', () async {
    await mockStorage({});
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    final sales = RecordsController(FarmModule.sales, farm: farm);
    expect(sales.filters.first, 'All');
    expect(sales.filters, containsAll(['Paid', 'Partial']));
    sales.setFilter('Partial');
    expect(sales.filtered, isNotEmpty);
    expect(sales.filtered.every((s) => s.status == 'Partial'), isTrue);
    // Rahman Grocery's milk sale has a later part-payment, so it is Partial, not Due.
    expect(sales.filtered.map((s) => s['customer']), contains('Rahman Grocery'));
  });
}
