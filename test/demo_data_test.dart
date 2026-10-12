import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/data/demo_data.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

import 'support/mock_storage.dart';

void main() {
  test('a fresh install has at least 10 demo records on every screen, saved in Hive', () async {
    await mockStorage({});
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    final auth = AuthController(LocalStorageService.instance);
    await auth.init();
    final store = await openStorage();
    for (final m in FarmModule.all.where((m) => !FarmModule.outOfScope.contains(m.name))) {
      expect(farm.count(m.name), greaterThanOrEqualTo(10), reason: m.name);
      expect(store.readRecords(m.name), hasLength(farm.count(m.name)), reason: '${m.name} in Hive');
    }
    for (final role in UserRole.values) {
      expect(auth.users.where((u) => u.role == role), hasLength(10), reason: role.label);
    }
    expect(UserRole.values, [UserRole.owner, UserRole.manager], reason: 'Farm Owner and Farm Manager only');
    // Livestock only: no poultry, fish or bee records, species or products.
    for (final m in FarmModule.outOfScope) {
      expect(farm.count(m), 0, reason: m);
    }
    expect(farm.list(FarmModule.species).every(FarmController.isLivestockSpecies), isTrue);
    for (final m in [FarmModule.production, FarmModule.productUsage, FarmModule.sales]) {
      for (final r in farm.list(m)) {
        expect(FarmModule.saleProducts, contains(r['product']), reason: '$m ${r.id}');
        expect('${r['batch'] ?? ''}', isEmpty, reason: '$m ${r.id}');
      }
    }
    // The owner dashboard has every animal status to show.
    for (final status in ['Active', 'Sold', 'Dead', 'Transferred']) {
      expect(farm.list(FarmModule.animals).where((a) => a.status == status), isNotEmpty, reason: status);
    }
    // Activity log: at least 10 entries, each about a demo record that exists,
    // by a demo user, never in the future.
    expect(farm.activity.length, greaterThanOrEqualTo(10));
    final names = auth.users.map((u) => u.name).toSet();
    for (final a in farm.activity) {
      final m = RegExp(r'^New (.+) record added · (.+)$').firstMatch(a.title)!;
      expect(farm.find(m.group(1)!, m.group(2)!), isNotNull, reason: a.title);
      expect(names, contains(a.by));
      expect(DateTime.parse(a.time).isAfter(DateTime.now()), isFalse);
    }
    expect(store.readActivity(), hasLength(farm.activity.length));
  });

  /// An install made with the older, smaller demo set: the first 5 demo
  /// records of each module, and no demo version saved.
  Future<Map<String, Object>> oldDemoInstall({bool edited = false}) async {
    final demo = buildDemoRecords(DateTime.now());
    final saved = <String, Object>{'data_version': '${FarmController.dataVersion}'};
    for (final m in FarmModule.all) {
      final rows = (demo[m.name] ?? const []).take(5).map((r) => {...r}).toList();
      if (edited && m.name == FarmModule.animals) rows.first['_updatedAt'] = '2026-10-01T08:00:00';
      saved['records_${m.name}'] = jsonEncode(rows);
    }
    return saved;
  }

  test('an untouched older demo farm is upgraded to the full demo set (with a backup first)', () async {
    await mockStorage(await oldDemoInstall());
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    for (final m in FarmModule.all.where((m) => !FarmModule.outOfScope.contains(m.name))) {
      expect(farm.count(m.name), greaterThanOrEqualTo(10), reason: m.name);
    }
    expect(farm.activity.any((a) => a.title.contains('Demo farm updated')), isTrue);
    expect(farm.autoBackupDate, isNotNull, reason: 'the old data was backed up first');

    // Only once.
    final again = FarmController(LocalStorageService.instance);
    await again.init();
    expect(again.activity.where((a) => a.title.contains('Demo farm updated')), hasLength(1));
  });

  test('a farm with any user change is never replaced — the user is told how to load the new demo', () async {
    await mockStorage(await oldDemoInstall(edited: true));
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    expect(farm.count(FarmModule.animals), 5, reason: 'nothing overwritten');
    expect(farm.count(FarmModule.milkProduction), 5);
    expect(farm.activity.where((a) => a.title.contains('New demo records are available')), hasLength(1));

    final again = FarmController(LocalStorageService.instance);
    await again.init();
    expect(again.activity.where((a) => a.title.contains('New demo records are available')), hasLength(1), reason: 'told once');

    // Loading the demo from Settings then gives every screen 10+ records.
    await again.reset();
    for (final m in FarmModule.all.where((m) => !FarmModule.outOfScope.contains(m.name))) {
      expect(again.count(m.name), greaterThanOrEqualTo(10), reason: m.name);
    }
    expect(again.activity.length, greaterThanOrEqualTo(10));
  });
}
