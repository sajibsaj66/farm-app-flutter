import 'package:flutter_test/flutter_test.dart';
import 'support/mock_storage.dart';
import 'package:technovate_farm_management/controllers/auth_controller.dart';
import 'package:technovate_farm_management/controllers/batch_analytics.dart';
import 'package:technovate_farm_management/controllers/farm_controller.dart';
import 'package:technovate_farm_management/controllers/finance_engine.dart';
import 'package:technovate_farm_management/controllers/record_form_controller.dart';
import 'package:technovate_farm_management/controllers/reports_controller.dart';
import 'package:technovate_farm_management/models/farm_module.dart';
import 'package:technovate_farm_management/models/farm_profile.dart';
import 'package:technovate_farm_management/models/farm_record.dart';
import 'package:technovate_farm_management/models/finance.dart';
import 'package:technovate_farm_management/models/user_role.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

/// A small, hand-checkable farm (October 2026):
/// * Cow A1 (bought for 100 000 on 2026-01-01) and cow A2, 100 L + 50 L milk.
/// * Layer batch B1: 100 birds, stocked 2026-09-01 for 40 000, 500 eggs.
/// * Feed: A1 10 kg × 50 from stock, A2 5 kg × 40 manual, B1 20 kg × 50 from stock.
/// * Sales: 120 L milk × 100 (no animal named), 300 eggs × 10 − 100 discount.
/// * Expenses: feed purchase 50 000, labour 3 000 shared equally, electricity 600 overhead.
/// * Health: A1 treatment 400.
Map<String, dynamic> scenario() => {
      'app': 'technovate_farm',
      'version': 1,
      'dataVersion': 3,
      'profile': const FarmProfile(name: 'Test Farm').toJson(),
      'records': {
        FarmModule.species: [
          {'id': 'SP-1', 'name': 'Cattle', 'category': 'Livestock', 'tracking': 'Individual', 'products': 'Milk', 'countUnit': 'head', 'status': 'Active'},
          {'id': 'SP-2', 'name': 'Layer chicken', 'category': 'Poultry & birds', 'tracking': 'Batch', 'products': 'Eggs', 'countUnit': 'birds', 'status': 'Active'},
        ],
        FarmModule.locations: [
          {'id': 'LC-1', 'name': 'Shed A', 'kind': 'Shed', 'capacity': '10', 'status': 'Active'},
          {'id': 'LC-2', 'name': 'House 1', 'kind': 'Poultry house', 'capacity': '200', 'status': 'Active'},
        ],
        FarmModule.animals: [
          {
            'id': 'A1',
            'name': 'Alpha',
            'species': 'Cattle',
            'type': 'Cow',
            'breed': 'HF',
            'sex': 'Female',
            'group': 'Lactating cows',
            'status': 'Active',
            'location': 'Shed A',
            'purchaseDate': '2026-01-01',
            'purchasePrice': '100000'
          },
          {
            'id': 'A2',
            'name': 'Beta',
            'species': 'Cattle',
            'type': 'Cow',
            'breed': 'HF',
            'sex': 'Female',
            'group': 'Lactating cows',
            'status': 'Active',
            'location': 'Shed A',
            'purchaseDate': '',
            'purchasePrice': ''
          },
        ],
        FarmModule.batches: [
          {
            'id': 'B1',
            'name': 'Layers',
            'species': 'Layer chicken',
            'purpose': 'Eggs',
            'startDate': '2026-09-01',
            'initialCount': '100',
            'countUnit': 'birds',
            'location': 'House 1',
            'stockingCost': '40000',
            'status': 'Active'
          },
        ],
        FarmModule.inventory: [
          {'id': 'I1', 'name': 'Feed X', 'category': 'Feed', 'feedType': 'Dairy concentrate', 'qty': '970', 'unit': 'kg', 'reorder': '100 kg', 'unitCost': '50', 'status': 'In stock'},
        ],
        FarmModule.inventoryTx: [
          {'id': 'T0', 'date': '2026-09-01', 'item': 'Feed X', 'type': FarmModule.txOpening, 'quantity': '1000', 'unitCost': '50', 'reference': 'Opening balance'},
          {'id': 'TX-F1', 'date': '2026-10-05', 'item': 'Feed X', 'type': FarmModule.txIssue, 'quantity': '10', 'unitCost': '50', 'reference': 'F1'},
          {'id': 'TX-F3', 'date': '2026-10-05', 'item': 'Feed X', 'type': FarmModule.txIssue, 'quantity': '20', 'unitCost': '50', 'reference': 'F3'},
        ],
        FarmModule.feedRecords: [
          {
            'id': 'F1',
            'date': '2026-10-05',
            'animal': 'A1 · Alpha',
            'batch': '',
            'group': '',
            'species': 'Cattle',
            'feed': 'Feed X',
            'source': FarmModule.fromInventory,
            'qty': '10',
            'unit': 'kg',
            'unitPrice': '50',
            'totalCost': '500',
            'shift': 'Morning'
          },
          {
            'id': 'F2',
            'date': '2026-10-05',
            'animal': 'A2 · Beta',
            'batch': '',
            'group': '',
            'species': 'Cattle',
            'feed': 'Market grass',
            'source': FarmModule.manualExpense,
            'qty': '5',
            'unit': 'kg',
            'unitPrice': '40',
            'totalCost': '200',
            'shift': 'Morning'
          },
          {
            'id': 'F3',
            'date': '2026-10-05',
            'animal': '',
            'batch': 'B1 · Layers',
            'group': '',
            'species': 'Layer chicken',
            'feed': 'Feed X',
            'source': FarmModule.fromInventory,
            'qty': '20',
            'unit': 'kg',
            'unitPrice': '50',
            'totalCost': '1000',
            'shift': 'Morning'
          },
        ],
        FarmModule.milkProduction: [
          {'id': 'M1', 'date': '2026-10-05', 'animal': 'A1 · Alpha', 'shift': 'Morning', 'litres': '100', 'quality': 'Accepted'},
          {'id': 'M2', 'date': '2026-10-05', 'animal': 'A2 · Beta', 'shift': 'Morning', 'litres': '50', 'quality': 'Accepted'},
        ],
        FarmModule.production: [
          {'id': 'P1', 'date': '2026-10-05', 'product': 'Eggs', 'batch': 'B1 · Layers', 'quantity': '500', 'unit': 'pcs', 'saleable': '', 'damaged': ''},
        ],
        FarmModule.sales: [
          {
            'id': 'S1',
            'date': '2026-10-06',
            'product': 'Milk',
            'customer': 'Dairy Co',
            'qty': '120',
            'unit': 'L',
            'unitPrice': '100',
            'gross': '12000',
            'discount': '',
            'deductions': '',
            'amount': '12000',
            'paidAtSale': '12000',
            'paid': '12000',
            'due': '0',
            'status': 'Paid'
          },
          {
            'id': 'S2',
            'date': '2026-10-06',
            'product': 'Eggs',
            'customer': 'Shop',
            'batch': 'B1 · Layers',
            'qty': '300',
            'unit': 'pcs',
            'unitPrice': '10',
            'gross': '3000',
            'discount': '100',
            'deductions': '',
            'amount': '2900',
            'paidAtSale': '2900',
            'paid': '2900',
            'due': '0',
            'status': 'Paid'
          },
        ],
        FarmModule.customers: [
          {'id': 'C1', 'name': 'Dairy Co', 'phone': '01700000000', 'type': 'Wholesale', 'balance': '0', 'status': 'Active'},
          {'id': 'C2', 'name': 'Shop', 'phone': '01700000001', 'type': 'Retail', 'balance': '0', 'status': 'Active'},
        ],
        FarmModule.expenses: [
          {
            'id': 'E1',
            'date': '2026-10-01',
            'category': 'Feed',
            'amount': '50000',
            'description': 'Feed X 1000 kg',
            'scope': FarmModule.scopeFarm,
            'allocation': FarmModule.allocNone,
            'payment': 'Paid'
          },
          {
            'id': 'E2',
            'date': '2026-10-10',
            'category': 'Labour and salaries',
            'amount': '3000',
            'description': 'Wages',
            'scope': FarmModule.scopeFarm,
            'allocation': FarmModule.allocEqual,
            'payment': 'Paid'
          },
          {'id': 'E3', 'date': '2026-10-12', 'category': 'Electricity', 'amount': '600', 'description': 'Power', 'scope': FarmModule.scopeFarm, 'allocation': FarmModule.allocNone, 'payment': 'Paid'},
        ],
        FarmModule.health: [
          {'id': 'H1', 'animal': 'A1 · Alpha', 'batch': '', 'date': '2026-10-08', 'type': 'Treatment', 'details': 'Hoof', 'cost': '400', 'status': 'Completed'},
        ],
      },
      'activity': [],
    };

void main() {
  late FarmController farm;
  late AuthController auth;
  final today = DateTime(2026, 10, 31);
  final october = ReportFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));

  setUp(() async {
    await mockStorage({});
    farm = FarmController(LocalStorageService.instance, clock: () => today);
    auth = AuthController(LocalStorageService.instance);
    farm.actor = () => auth.currentUser?.name;
    await farm.init();
    await auth.init();
    await auth.login(role: UserRole.owner, username: 'owner', password: 'owner123');
    await farm.restore(scenario());
  });

  FarmRecord item() => farm.feedItem('Feed X')!;
  FinanceEngine engine([ReportFilter? f]) => FinanceEngine(farm, f ?? october);

  group('profit and loss (hand-checked)', () {
    test('consumption basis: feed counted when fed, feed purchases not counted twice', () {
      final pnl = engine().profitAndLoss;
      expect(pnl.revenueByProduct, {'Milk': 12000, 'Eggs': 2900});
      expect(pnl.costsByCategory[FinanceEngine.catFeed], 1700); // 500 + 200 + 1000
      expect(pnl.costsByCategory.containsKey('Feed'), isFalse, reason: 'feed purchase expense is stock, not cost');
      expect(pnl.costsByCategory[FinanceEngine.catTreatment], 400);
      expect(pnl.costsByCategory['Labour and salaries'], closeTo(3000, 0.001));
      expect(pnl.costsByCategory['Electricity'], 600);
      expect(pnl.costs, closeTo(5700, 0.001));
      expect(pnl.operatingProfit, closeTo(9200, 0.001));
    });

    test('purchase basis: feed expenses counted, stock-issued feed not added again', () async {
      await farm.updateProfile(farm.profile.copyWith(feedCostBasis: FeedCostBasis.purchases));
      final pnl = engine().profitAndLoss;
      expect(pnl.costsByCategory[FinanceEngine.catFeedPurchases], 50000);
      expect(pnl.costsByCategory[FinanceEngine.catFeed], 200, reason: 'only the manual expense-only feed record');
      expect(pnl.costs, closeTo(50000 + 200 + 400 + 3000 + 600, 0.001));
    });

    test('cash flow is separate from profit', () {
      final e = engine();
      expect(e.cashIn, 14900);
      // Feed purchase 50 000 + labour 3 000 + electricity 600 + manual feed 200 + treatment 400.
      expect(e.cashOut, closeTo(54200, 0.001));
      expect(e.netCashFlow, closeTo(-39300, 0.001));
      expect(e.profitAndLoss.operatingProfit, isNot(closeTo(e.netCashFlow, 1)));
    });

    test('stocking cost is recognised when the batch starts (September), not in October', () {
      final sep = engine(ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30))).profitAndLoss;
      expect(sep.costsByCategory[FinanceEngine.catStocking], 40000);
      expect(engine().profitAndLoss.costsByCategory[FinanceEngine.catStocking], isNull);
    });

    test('monthly rows add up to the period total', () {
      final e = engine(ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 31)));
      final months = e.monthly;
      expect(months.map((m) => m.$1), ['2026-09', '2026-10']);
      expect(months.fold(0.0, (s, m) => s + m.$2), closeTo(e.profitAndLoss.revenue, 0.001));
      expect(months.fold(0.0, (s, m) => s + m.$3), closeTo(e.profitAndLoss.costs, 0.001));
    });
  });

  group('animal and batch profitability', () {
    test('bulk milk sales are shared by each cow’s milk; shared labour by the chosen method', () {
      final units = {for (final p in engine().unitProfits) p.unit.id: p};
      final a1 = units['A1']!, a2 = units['A2']!, b1 = units['B1']!;
      expect(a1.revenue, closeTo(8000, 0.001)); // 100 of 150 L
      expect(a2.revenue, closeTo(4000, 0.001));
      expect(b1.revenue, 2900);
      expect(a1.cost(FinanceEngine.catFeed), 500);
      expect(a1.cost(FinanceEngine.catTreatment), 400);
      expect(a1.allocatedCost, closeTo(1000, 0.001)); // 3 000 equally over A1, A2, B1
      expect(a1.allocatedByMethod.keys, [FarmModule.allocEqual]);
      expect(a1.profit, closeTo(8000 - 500 - 400 - 1000, 0.001));
      expect(a1.cost(FinanceEngine.catDepreciation), 0, reason: 'purchase price is not charged daily by default');
    });

    test('allocation by head count weights batches by birds', () async {
      final labour = farm.find(FarmModule.expenses, 'E2')!;
      await farm.update(FarmModule.expenses, FarmRecord({...labour.data, 'allocation': FarmModule.allocHead}));
      final units = {for (final p in engine().unitProfits) p.unit.id: p};
      // 1 + 1 + 100 birds = 102 head.
      expect(units['B1']!.allocatedCost, closeTo(3000 * 100 / 102, 0.001));
      expect(units['A1']!.allocatedCost, closeTo(3000 / 102, 0.001));
    });

    test('cost per litre and per saleable egg', () {
      final table = (ReportsController(farm: farm, auth: auth, clock: () => today)..setFilter(october)).costPerUnit();
      final milk = table.rows.firstWhere((r) => r.first.startsWith('Milk'));
      // (A1: 500 + 400 + 1000) + (A2: 200 + 1000) = 3 100 ÷ 150 L.
      expect(double.parse(milk[4]), closeTo(3100 / 150, 0.01));
      final eggs = table.rows.firstWhere((r) => r[1] == 'saleable egg');
      // B1: feed 1 000 + labour 1 000 = 2 000 ÷ 500 eggs.
      expect(double.parse(eggs[4]), closeTo(4, 0.01));
    });

    test('depreciation and book value on sale follow the asset method', () async {
      await farm.updateProfile(farm.profile.copyWith(assetMethod: AssetMethod.depreciate, depreciationYears: 5, residualPercent: 20));
      final dep = engine().profitAndLoss.costsByCategory[FinanceEngine.catDepreciation]!;
      expect(dep, closeTo(100000 * 0.8 / (5 * 365) * 31, 0.01));

      await farm.updateProfile(farm.profile.copyWith(assetMethod: AssetMethod.capitalize));
      await farm.add(
          FarmModule.sales, {'date': '2026-10-20', 'product': 'Live animal', 'customer': 'Dairy Co', 'animal': 'A1 · Alpha', 'qty': '1', 'unit': 'head', 'unitPrice': '90000', 'paidAtSale': '90000'});
      expect(farm.find(FarmModule.animals, 'A1')!.status, 'Sold');
      final pnl = engine().profitAndLoss;
      expect(pnl.revenueByProduct['Live animal'], 90000);
      expect(pnl.costsByCategory[FinanceEngine.catDisposal], 100000, reason: 'book value charged once, at sale');
    });

    test('species report adds up to the farm total, with overhead shown separately', () {
      final table = (ReportsController(farm: farm, auth: auth, clock: () => today)..setFilter(october)).species();
      final profit = table.rows.fold(0.0, (s, r) => s + double.parse(r[4]));
      expect(profit, closeTo(9200, 1));
      expect(table.rows.map((r) => r.first), containsAll(['Cattle', 'Layer chicken', 'Farm-wide (not allocated)']));
    });

    test('filters: species and animal filters leave out unallocated overhead', () {
      final cattle = engine(october.copyWith(species: 'Cattle')).profitAndLoss;
      expect(cattle.revenueByProduct.keys, ['Milk']);
      expect(cattle.excludedOverhead, 600);
      final a2 = engine(october.copyWith(animal: 'A2')).profitAndLoss;
      expect(a2.revenue, closeTo(4000, 0.001));
    });

    test('report CSV contains exactly the rows on screen', () {
      final r = ReportsController(farm: farm, auth: auth, clock: () => today)..setFilter(october);
      for (final kind in ReportKind.values) {
        r.setKind(kind);
        final t = r.build();
        final lines = t.toCsv().split('\n');
        expect(lines.first.split('","').length, t.columns.length, reason: kind.label);
        expect(lines.length, t.rows.length + 1, reason: kind.label);
      }
    });
  });

  group('feed inventory integration', () {
    test('issue, edit and delete keep stock and history exact (no double deduction)', () async {
      expect(item().number('qty'), 970);
      final f = await farm.add(FarmModule.feedRecords,
          {'date': '2026-10-20', 'animal': 'A1 · Alpha', 'feed': 'Feed X', 'source': FarmModule.fromInventory, 'qty': '30', 'unit': 'kg', 'unitPrice': '50', 'shift': 'Morning'});
      expect(item().number('qty'), 940);
      expect(f['totalCost'], '1500.00');
      expect(farm.find(FarmModule.inventoryTx, 'TX-${f.id}')!['quantity'], '30');

      // Edit twice: stock reflects only the latest quantity.
      await farm.update(FarmModule.feedRecords, FarmRecord({...f.data, 'qty': '12'}));
      await farm.update(FarmModule.feedRecords, FarmRecord({...farm.find(FarmModule.feedRecords, f.id)!.data, 'qty': '12'}));
      expect(item().number('qty'), 958);
      expect(farm.list(FarmModule.inventoryTx).where((t) => t['reference'] == f.id), hasLength(1));

      // Grams are converted to the item's unit.
      await farm.update(FarmModule.feedRecords, FarmRecord({...farm.find(FarmModule.feedRecords, f.id)!.data, 'qty': '500', 'unit': 'g', 'unitPrice': '0.05'}));
      expect(item().number('qty'), 969.5);

      await farm.remove(FarmModule.feedRecords, f.id);
      expect(item().number('qty'), 970);
      expect(farm.find(FarmModule.inventoryTx, 'TX-${f.id}'), isNull);
    });

    test('negative stock is refused and nothing changes', () async {
      expect(
        () => farm.add(FarmModule.feedRecords,
            {'date': '2026-10-20', 'batch': 'B1 · Layers', 'feed': 'Feed X', 'source': FarmModule.fromInventory, 'qty': '971', 'unit': 'kg', 'unitPrice': '50', 'shift': 'Morning'}),
        throwsA(isA<FarmRuleException>()),
      );
      expect(item().number('qty'), 970);
      expect(farm.count(FarmModule.feedRecords), 3);
    });

    test('manual expense-only feed does not touch stock', () async {
      await farm.add(FarmModule.feedRecords,
          {'date': '2026-10-20', 'animal': 'A2 · Beta', 'feed': 'Roadside grass', 'source': FarmModule.manualExpense, 'qty': '8', 'unit': 'kg', 'unitPrice': '10', 'shift': 'Evening'});
      expect(item().number('qty'), 970);
    });

    test('purchase, wastage and physical count; system movements cannot be edited', () async {
      final p = await farm.add(FarmModule.inventoryTx, {'date': '2026-10-21', 'item': 'Feed X', 'type': FarmModule.txPurchase, 'quantity': '100', 'unitCost': '55'});
      expect(item().number('qty'), 1070);
      expect(item().number('unitCost'), 55);
      await farm.add(FarmModule.inventoryTx, {'date': '2026-10-22', 'item': 'Feed X', 'type': FarmModule.txWastage, 'quantity': '20'});
      expect(item().number('qty'), 1050);
      final count = await farm.add(FarmModule.inventoryTx, {'date': '2026-10-23', 'item': 'Feed X', 'type': FarmModule.txCount, 'quantity': '1040'});
      expect(item().number('qty'), 1040);
      expect(count['_delta'], '-10');
      await farm.remove(FarmModule.inventoryTx, count.id);
      expect(item().number('qty'), 1050);
      await farm.remove(FarmModule.inventoryTx, p.id);
      expect(item().number('qty'), 950);
      expect(() => farm.remove(FarmModule.inventoryTx, 'TX-F1'), throwsA(isA<FarmRuleException>()));
      expect(() => farm.update(FarmModule.inventoryTx, farm.find(FarmModule.inventoryTx, 'T0')!), throwsA(isA<FarmRuleException>()));
      expect(() => farm.add(FarmModule.inventoryTx, {'date': '2026-10-24', 'item': 'Feed X', 'type': FarmModule.txWastage, 'quantity': '5000'}), throwsA(isA<FarmRuleException>()));
    });

    test('wastage is a cost under the consumption basis', () async {
      await farm.add(FarmModule.inventoryTx, {'date': '2026-10-22', 'item': 'Feed X', 'type': FarmModule.txWastage, 'quantity': '4'});
      expect(engine().profitAndLoss.costsByCategory[FinanceEngine.catWastage], 200);
    });
  });

  group('batches, production, sales and payments', () {
    test('head count flow: opening + added − died − sold − harvested − moved', () async {
      await farm.add(FarmModule.batchMovements, {'date': '2026-10-02', 'batch': 'B1 · Layers', 'type': 'Hatching', 'quantity': '10'});
      await farm.add(FarmModule.mortality, {'date': '2026-10-03', 'batch': 'B1 · Layers', 'count': '4', 'cause': 'Disease'});
      await farm.add(FarmModule.batchMovements, {'date': '2026-10-04', 'batch': 'B1 · Layers', 'type': 'Culling', 'quantity': '6'});
      await farm.add(FarmModule.sales,
          {'date': '2026-10-25', 'product': 'Live birds', 'customer': 'Shop', 'batch': 'B1 · Layers', 'qty': '30', 'unit': 'kg', 'unitPrice': '200', 'headCount': '20', 'paidAtSale': '0'});
      final a = BatchAnalytics(farm, farm.find(FarmModule.batches, 'B1')!, today: today);
      expect(a.opening, 100);
      expect(a.additions, 10);
      expect(a.died, 4);
      expect(a.removedByMovement, 6);
      expect(a.soldHead, 20);
      expect(a.closing, 80);
      expect(a.mortalityRate, closeTo(4 / 110, 1e-9));
      expect(() => farm.add(FarmModule.mortality, {'date': '2026-10-26', 'batch': 'B1 · Layers', 'count': '81', 'cause': 'Disease'}), throwsA(isA<FarmRuleException>()));
    });

    test('unsold stock: production − sold − used; overselling is refused', () async {
      expect(farm.productStock('Eggs'), 200); // 500 produced − 300 sold
      expect(farm.productStock('Milk'), 30); // 150 L − 120 L
      await farm.add(FarmModule.productUsage, {'date': '2026-10-07', 'product': 'Eggs', 'usage': 'Internal use', 'quantity': '1', 'unit': 'dozen'});
      expect(farm.productStock('Eggs'), 188);
      expect(() => farm.add(FarmModule.sales, {'date': '2026-10-07', 'product': 'Eggs', 'customer': 'Shop', 'qty': '7', 'unit': 'tray', 'unitPrice': '300'}), throwsA(isA<FarmRuleException>()));
      expect(() => farm.add(FarmModule.productUsage, {'date': '2026-10-07', 'product': 'Milk', 'usage': 'Spoiled', 'quantity': '31', 'unit': 'L'}), throwsA(isA<FarmRuleException>()));
      // Withheld milk never becomes saleable stock.
      await farm.add(FarmModule.health, {'animal': 'A2 · Beta', 'date': '2026-10-06', 'type': 'Treatment', 'details': 'Mastitis', 'withdrawalDays': '3', 'status': 'Follow-up'});
      final m = await farm.add(FarmModule.milkProduction, {'date': '2026-10-07', 'animal': 'A2 · Beta', 'shift': 'Morning', 'litres': '10', 'quality': 'Accepted'});
      expect(m['quality'], FarmModule.qualityWithheld);
      expect(farm.productStock('Milk'), 30);
    });

    test('sale totals, later payments and outstanding amounts', () async {
      final s = await farm.add(FarmModule.sales, {
        'date': '2026-10-07',
        'product': 'Eggs',
        'customer': 'Shop',
        'batch': 'B1 · Layers',
        'qty': '5',
        'unit': 'dozen',
        'unitPrice': '120',
        'discount': '20',
        'deductions': '40',
        'paidAtSale': '100'
      });
      expect(s['gross'], '600.00');
      expect(s['amount'], '540.00');
      expect(s['due'], '440.00');
      expect(s.status, 'Partial');
      final p = await farm.add(FarmModule.collections, {'date': '2026-10-15', 'sale': '${s.id} · Shop', 'amount': '440', 'method': 'Cash'});
      expect(p['customer'], 'Shop');
      expect(farm.find(FarmModule.sales, s.id)!.status, 'Paid');
      expect(() => farm.add(FarmModule.collections, {'date': '2026-10-16', 'sale': '${s.id} · Shop', 'amount': '1', 'method': 'Cash'}), throwsA(isA<FarmRuleException>()));
      expect(() => farm.remove(FarmModule.sales, s.id), throwsA(isA<FarmRuleException>()), reason: 'has a payment');
      await farm.remove(FarmModule.collections, p.id);
      expect(farm.find(FarmModule.sales, s.id)!.number('due'), 440);
      // Cash flow counts the payment on its own date.
      await farm.add(FarmModule.collections, {'date': '2026-11-02', 'sale': '${s.id} · Shop', 'amount': '440', 'method': 'Cash'});
      expect(engine().cashIn, 14900 + 100);
    });

    test('mortality and sale set Dead/Sold; deleting the record restores the animal', () async {
      final d = await farm.add(FarmModule.mortality, {'date': '2026-10-20', 'animal': 'A2 · Beta', 'cause': 'Accident'});
      expect(farm.find(FarmModule.animals, 'A2')!.status, 'Dead');
      expect(d['count'], '1');
      expect(() => farm.add(FarmModule.mortality, {'date': '2026-10-21', 'animal': 'A2 · Beta', 'cause': 'Accident'}), throwsA(isA<FarmRuleException>()));
      await farm.remove(FarmModule.mortality, d.id);
      expect(farm.find(FarmModule.animals, 'A2')!.status, 'Active');
    });

    test('animals with history are archived, never deleted', () async {
      expect(() => farm.remove(FarmModule.animals, 'A1'), throwsA(isA<FarmRuleException>()));
      await farm.archive(FarmModule.animals, farm.find(FarmModule.animals, 'A1')!);
      expect(farm.find(FarmModule.animals, 'A1')!.status, 'Archived');
      final form = RecordFormController(module: FarmModule.milkProduction, farm: farm, auth: auth, clock: () => today);
      expect(form.optionsFor('animal'), isNot(contains('A1 · Alpha')));
      form.dispose();
      // History stays in reports.
      expect(engine().unitProfits.map((p) => p.unit.id), contains('A1'));
    });

    test('expenses that duplicate other records are refused', () async {
      expect(
          () => farm.add(
              FarmModule.expenses, {'date': '2026-10-08', 'category': 'Veterinary treatment', 'amount': '400', 'description': 'Hoof', 'scope': 'Animal', 'animal': 'A1 · Alpha', 'payment': 'Paid'}),
          throwsA(isA<FarmRuleException>()));
      expect(
          () => farm
              .add(FarmModule.expenses, {'date': '2026-10-08', 'category': 'Fish/shrimp stocking', 'amount': '400', 'description': 'x', 'scope': 'Batch', 'batch': 'B1 · Layers', 'payment': 'Paid'}),
          throwsA(isA<FarmRuleException>()));
      expect(
          () => farm.add(FarmModule.expenses, {'date': '2026-10-08', 'category': 'Other', 'amount': '10', 'description': 'x', 'scope': 'Animal', 'payment': 'Paid'}), throwsA(isA<FarmRuleException>()),
          reason: 'animal not chosen');
    });
  });

  group('species and configuration', () {
    test('new species can be added and used; pickers follow the tracking method', () async {
      await farm.add(FarmModule.species, {'name': 'Alpaca', 'category': 'Livestock', 'tracking': 'Individual', 'countUnit': 'head', 'status': 'Active'});
      // Older non-livestock species (e.g. from an earlier version) are kept but
      // never offered: this system is livestock only.
      await farm.add(FarmModule.species, {'name': 'Tilapia', 'category': 'Fisheries & aquaculture', 'tracking': 'Batch', 'countUnit': 'fish', 'status': 'Active'});
      final animalForm = RecordFormController(module: FarmModule.animals, farm: farm, auth: auth);
      expect(animalForm.optionsFor('species'), containsAll(['Cattle', 'Alpaca']));
      expect(animalForm.optionsFor('species'), isNot(contains('Tilapia')));
      animalForm.dispose();
      expect(ReportsController(farm: farm, auth: auth).speciesOptions, isNot(contains('Tilapia')));
      expect(() => farm.remove(FarmModule.species, 'SP-1'), throwsA(isA<FarmRuleException>()), reason: 'used by animals');
    });
  });

  test('data persists across an app restart', () async {
    await farm.add(
        FarmModule.feedRecords, {'date': '2026-10-20', 'animal': 'A1 · Alpha', 'feed': 'Feed X', 'source': FarmModule.fromInventory, 'qty': '7', 'unit': 'kg', 'unitPrice': '50', 'shift': 'Morning'});
    final restarted = FarmController(LocalStorageService.instance, clock: () => today);
    await restarted.init();
    expect(restarted.count(FarmModule.feedRecords), 4);
    expect(restarted.feedItem('Feed X')!.number('qty'), 963);
    expect(restarted.profile.name, 'Test Farm');
    expect(FinanceEngine(restarted, october).profitAndLoss.operatingProfit, closeTo(FinanceEngine(farm, october).profitAndLoss.operatingProfit, 0.001));
  });

  test('loading demo data backs up real data first, and it can be restored', () async {
    await farm.reset();
    expect(farm.find(FarmModule.animals, 'A1'), isNull);
    expect(farm.autoBackupDate, isNotNull);
    await farm.restoreAutoBackup();
    expect(farm.find(FarmModule.animals, 'A1'), isNotNull);
    expect(farm.feedItem('Feed X')!.number('qty'), 970);
  });

  test('older saved data is migrated without loss, and no demo activity is mixed in', () async {
    await mockStorage({
      'records_Animals': '[{"id":"AN-1","name":"Old Cow","type":"Cow","breed":"Local","sex":"Female","age":"4 years","status":"Active","location":"Shed"}]',
      'records_Sales':
          '[{"id":"SI-1","date":"2026-10-01","customer":"X","item":"Raw milk","qty":"80 L","amount":"9600","status":"Paid"},{"id":"SI-2","date":"2026-10-02","customer":"Y","item":"Raw milk","qty":"35 L","amount":"4200","status":"Due"}]',
      'records_Feed Records': '[{"id":"FD-1","date":"2026-10-01","group":"Lactating cows","feed":"Dairy concentrate","qty":"42 kg","shift":"Morning"}]',
      'records_Expenses': '[{"id":"EX-1","date":"2026-10-01","category":"Feed","description":"Feed","amount":"18500","payment":"Paid"}]',
      'records_Inventory': '[{"id":"ST-1","name":"Dairy concentrate","category":"Feed","qty":"520","unit":"kg","reorder":"150 kg","status":"In stock"}]',
    });
    final old = FarmController(LocalStorageService.instance, clock: () => today);
    await old.init();
    final cow = old.find(FarmModule.animals, 'AN-1')!;
    expect(cow['species'], 'Cattle');
    expect(cow['age'], '4 years', reason: 'extra columns are kept');
    final s1 = old.find(FarmModule.sales, 'SI-1')!;
    expect(s1['product'], 'Milk');
    expect(s1['unit'], 'L');
    expect(s1.number('unitPrice'), 120);
    expect(s1.status, 'Paid');
    expect(old.find(FarmModule.sales, 'SI-2')!.number('due'), 4200);
    final feed = old.find(FarmModule.feedRecords, 'FD-1')!;
    expect(feed['source'], FarmModule.fromInventory);
    expect(feed['qty'], '42');
    expect(old.find(FarmModule.expenses, 'EX-1')!['scope'], FarmModule.scopeFarm);
    expect(old.list(FarmModule.inventoryTx).single['type'], FarmModule.txOpening);
    // Configuration is added; demo activity is not.
    expect(old.count(FarmModule.species), greaterThanOrEqualTo(10));
    expect(old.count(FarmModule.batches), 0);
    expect(old.count(FarmModule.production), 0);
    expect(old.count(FarmModule.animals), 1);
    final store = await openStorage();
    expect(store.readValue('data_version'), '${FarmController.dataVersion}');
  });
}
