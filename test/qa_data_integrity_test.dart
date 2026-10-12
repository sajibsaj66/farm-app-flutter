import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/core/utils/units.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/field_spec.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

void main() {
  test('demo data is internally consistent and every record re-saves under the rules', () async {
    await mockStorage({});
    final farm = FarmController(LocalStorageService.instance);
    await farm.init();
    final problems = <String>[];
    for (final m in FarmModule.all) {
      final rows = farm.list(m.name);
      final ids = <String>{};
      for (final r in rows) {
        if (!ids.add(r.id)) problems.add('${m.name}: duplicate id ${r.id}');
        final extra = r.keys.where((k) => k != 'id' && !FarmModule.isInternal(k) && !m.fields.contains(k));
        if (extra.isNotEmpty) problems.add('${m.name} ${r.id}: extra fields $extra');
        for (final s in m.specs) {
          final v = '${r[s.key] ?? ''}'.trim();
          if (s.required && !s.computed && v.isEmpty) problems.add('${m.name} ${r.id}: missing required ${s.key}');
          if (v.isEmpty) continue;
          switch (s.type) {
            case FieldType.animal:
              if (farm.resolve(FarmModule.animals, v) == null) problems.add('${m.name} ${r.id}: ${s.key} -> unknown animal $v');
            case FieldType.batch:
              if (farm.resolve(FarmModule.batches, v) == null) problems.add('${m.name} ${r.id}: unknown batch $v');
            case FieldType.illness:
              if (farm.resolve(FarmModule.illness, v) == null) problems.add('${m.name} ${r.id}: unknown illness $v');
            case FieldType.treatment:
              if (farm.resolve(FarmModule.treatments, v) == null) problems.add('${m.name} ${r.id}: unknown treatment $v');
            case FieldType.sale:
              if (farm.resolve(FarmModule.sales, v) == null) problems.add('${m.name} ${r.id}: unknown sale $v');
            case FieldType.customer:
              if (farm.byName(FarmModule.customers, v) == null) problems.add('${m.name} ${r.id}: unknown customer $v');
            case FieldType.species:
              if (farm.species(v) == null) problems.add('${m.name} ${r.id}: unknown species $v');
            case FieldType.location:
              if (farm.byName(FarmModule.locations, v) == null) problems.add('${m.name} ${r.id}: unknown location $v');
            case FieldType.feedItem || FieldType.inventoryItem:
              if (farm.feedItem(v) == null && !(m.name == FarmModule.feedRecords && '${r['source']}' != FarmModule.fromInventory)) problems.add('${m.name} ${r.id}: unknown item $v');
            case FieldType.semen:
              if (farm.semenByCode(v) == null) problems.add('${m.name} ${r.id}: unknown semen $v');
            case FieldType.choice:
              final system = m.name == FarmModule.inventoryTx && s.key == 'type' && (v == FarmModule.txIssue || v == FarmModule.txTreatment || v == FarmModule.txOpening);
              if (!system && s.options.isNotEmpty && !s.options.contains(v)) problems.add('${m.name} ${r.id}: ${s.key}="$v" not an option');
            case FieldType.date:
              if (FarmRecord.parseDate(v) == null) problems.add('${m.name} ${r.id}: bad date ${s.key}=$v');
            case FieldType.number:
              if (FarmRecord.leadingNumber(v) == null) problems.add('${m.name} ${r.id}: bad number ${s.key}=$v');
            default:
          }
        }
      }
    }
    // Names unique
    for (final m in [FarmModule.inventory, FarmModule.species, FarmModule.locations, FarmModule.customers, FarmModule.batches]) {
      final names = <String>{};
      for (final r in farm.list(m)) {
        if (!names.add('${r['name']}'.toLowerCase())) problems.add('$m: duplicate name ${r['name']}');
      }
    }
    // Inventory = sum of its transactions
    for (final item in farm.list(FarmModule.inventory)) {
      var total = 0.0;
      for (final t in farm.list(FarmModule.inventoryTx).where((t) => '${t['item']}' == '${item['name']}')) {
        final q = t.number('quantity');
        total += switch ('${t['type']}') {
          FarmModule.txOpening || FarmModule.txPurchase || FarmModule.txAdjustUp => q,
          FarmModule.txIssue || FarmModule.txTreatment || FarmModule.txAdjustDown || FarmModule.txWastage => -q,
          FarmModule.txCount => t.number('_delta'),
          _ => 0,
        };
      }
      if ((total - item.number('qty')).abs() > 0.01) problems.add('Inventory ${item['name']}: qty ${item['qty']} but transactions add to $total');
      if (item.number('qty') < 0) problems.add('Inventory ${item['name']} negative');
    }
    for (final b in farm.list(FarmModule.batches)) {
      final c = farm.batchCount(b.reference);
      if (c < 0) problems.add('Batch ${b.id} count $c');
      if (FarmController.isActive(b) && c == 0) problems.add('Active batch ${b.id} with 0 head');
    }
    for (final p in FarmController.stockedProducts) {
      final s = farm.productStock(p);
      if (s < -0.001) problems.add('Product $p stock $s');
    }
    for (final s in farm.list(FarmModule.sales)) {
      if (s.number('due') < -0.005) problems.add('Sale ${s.id} overpaid');
      final unitBase = Units.baseOf('${s['unit']}');
      if (unitBase.isEmpty) problems.add('Sale ${s.id} unit');
    }
    for (final mo in farm.list(FarmModule.mortality).where((m) => '${m['animal']}'.isNotEmpty)) {
      final a = farm.resolve(FarmModule.animals, mo['animal'])!;
      if (a.status != 'Dead') problems.add('Mortality ${mo.id}: ${a.id} is ${a.status}');
    }
    for (final s in farm.list(FarmModule.sales).where((m) => '${m['product']}' == 'Live animal')) {
      final a = farm.resolve(FarmModule.animals, s['animal'])!;
      if (a.status != 'Sold') problems.add('Sale ${s.id}: ${a.id} is ${a.status}');
    }
    for (final s in farm.list(FarmModule.semen)) {
      if (s.number('straws') < 0) problems.add('Semen ${s.id} negative');
    }
    // Re-saving each record unchanged must pass the rules.
    for (final m in FarmModule.all) {
      if (m.name == FarmModule.inventoryTx) continue;
      for (final r in [...farm.list(m.name)]) {
        try {
          await farm.update(m.name, r);
        } on FarmRuleException catch (e) {
          problems.add('Re-save ${m.name} ${r.id}: $e');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
