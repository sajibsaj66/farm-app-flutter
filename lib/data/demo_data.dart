import '../models/farm_module.dart';
import 'demo_extras.dart';
import 'demo_team.dart';

/// Configuration records every farm starts with (species and locations).
/// These are safe to add to an existing install; everything else in
/// [buildDemoRecords] is fictional demo activity.
const configurationModules = {FarmModule.species, FarmModule.locations};

/// Fictional seed records used on a fresh install and by "Reset demo data".
///
/// Dates are relative to [today] so the demo always shows recent activity.
/// A mixed livestock farm in Bangladesh: dairy cattle (a cow that recently
/// calved, a confirmed pregnancy, a cow under a milk withdrawal period, a calf
/// with known parents), fattening bulls sold at the haat, a buffalo, goats and
/// a sheep — so every screen and report has something to show. No poultry,
/// fisheries or bee-keeping.
Map<String, List<Map<String, dynamic>>> buildDemoRecords(DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  String d(int daysAgo) => _fmt(t.subtract(Duration(days: daysAgo)));
  String ago({int years = 0, int months = 0}) => _fmt(DateTime(t.year - years, t.month - months, 15));
  String money(double v) => v.toStringAsFixed(0);

  const shona = 'AN-1001 · Shona';
  const rani = 'AN-1002 · Rani';
  const moti = 'AN-1004 · Moti';
  const toofan = 'AN-1009 · Toofan';

  // Feed items: name → (unit cost, feed category). Napier Grass stays second
  // (ST-4002) — its opening balance includes recorded wastage below.
  const feedItems = {
    'Dairy Concentrate Feed': (46.0, 'Dairy concentrate'),
    'Napier Grass': (6.0, 'Green fodder'),
    'Calf Starter': (72.0, 'Calf starter'),
    'Mineral Mixture': (120.0, 'Minerals and vitamins'),
    'Rice Straw': (8.0, 'Hay and straw'),
    'Wheat Bran': (44.0, 'Grains and supplements'),
    'Maize Silage': (12.0, 'Silage'),
    'Fattening Concentrate': (52.0, 'Fattening concentrate'),
    'Molasses': (35.0, 'Grains and supplements'),
  };

  // ------------------------------------------------------------------ milk
  final milk = <Map<String, dynamic>>[];
  final sellableMilkByDay = <int, double>{};
  var milkId = 3000;
  const herd = [
    (shona, 12.5, 10.0, '3.6', '8.4'),
    (rani, 8.5, 7.0, '4.4', '8.8'),
    (moti, 6.5, 5.5, '4.8', '9.0'),
  ];
  for (var i = 0; i < 14; i++) {
    for (final (cow, morning, evening, fat, snf) in herd) {
      for (final (shift, base) in [('Morning', morning), ('Evening', evening)]) {
        final wobble = (((i * 7 + base.round()) % 5) - 2) * 0.3;
        final litres = double.parse((base + wobble).toStringAsFixed(1));
        final withheld = cow == moti && i <= 1;
        final quality = withheld ? 'Withheld' : (cow == moti && i == 3 ? 'Review' : 'Accepted');
        if (!withheld) sellableMilkByDay[i] = (sellableMilkByDay[i] ?? 0) + litres;
        milk.add({'id': 'ML-${milkId++}', 'date': d(i), 'animal': cow, 'shift': shift, 'litres': litres.toStringAsFixed(1), 'quality': quality, 'fat': fat, 'snf': snf});
      }
    }
  }

  // ------------------------------------------------------------------ feed
  final feed = <Map<String, dynamic>>[];
  final issued = <String, double>{};
  final issueTx = <Map<String, dynamic>>[];
  var feedId = 8000;
  void addFeed(int daysAgo, String item, double qty, {String animal = '', String batch = '', String group = '', String species = '', String shift = 'Morning'}) {
    final (cost, category) = feedItems[item]!;
    final id = 'FD-${feedId++}';
    feed.add({
      'id': id,
      'date': d(daysAgo),
      'animal': animal,
      'batch': batch,
      'group': group,
      'species': species,
      'feed': item,
      'category': category,
      'source': FarmModule.fromInventory,
      'qty': _num(qty),
      'unit': 'kg',
      'unitPrice': money(cost),
      'totalCost': (qty * cost).toStringAsFixed(2),
      'shift': shift,
      'staff': 'Sabbir Hossain',
      'notes': '',
    });
    issued[item] = (issued[item] ?? 0) + qty;
    issueTx.add({'id': 'TX-$id', 'date': d(daysAgo), 'item': item, 'type': FarmModule.txIssue, 'quantity': _num(qty), 'unitCost': money(cost), 'reference': id, 'notes': ''});
  }

  for (var i = 0; i < 14; i++) {
    for (final (cow, concentrate, grass) in [(shona, 6.0, 25.0), (rani, 5.0, 22.0), (moti, 4.0, 20.0)]) {
      addFeed(i, 'Dairy Concentrate Feed', concentrate, animal: cow, species: 'Cattle');
      addFeed(i, 'Napier Grass', grass, animal: cow, species: 'Cattle', shift: 'Evening');
    }
    addFeed(i, 'Napier Grass', 30, group: 'Bulls', species: 'Cattle');
    addFeed(i, 'Calf Starter', 1.5, group: 'Calves', species: 'Cattle');
    addFeed(i, 'Napier Grass', 4, group: 'Goats', species: 'Goat');
    // Fattening bull on a finishing ration.
    addFeed(i, 'Fattening Concentrate', 4, animal: toofan, species: 'Cattle');
    addFeed(i, 'Maize Silage', 12, animal: toofan, species: 'Cattle', shift: 'Evening');
  }
  // Weekly extras for the milking herd.
  for (var w = 0; w < 14; w += 7) {
    addFeed(w, 'Wheat Bran', 15, group: 'Lactating cows', species: 'Cattle');
    addFeed(w, 'Molasses', 5, group: 'Lactating cows', species: 'Cattle');
    addFeed(w, 'Rice Straw', 40, group: 'Bulls', species: 'Cattle');
  }

  // ------------------------------------------------------------ inventory
  const stockNow = {
    'Dairy Concentrate Feed': 520.0,
    'Napier Grass': 1800.0,
    'Calf Starter': 45.0,
    'Mineral Mixture': 34.0,
    'Rice Straw': 600.0,
    'Wheat Bran': 420.0,
    'Maize Silage': 1500.0,
    'Fattening Concentrate': 380.0,
    'Molasses': 18.0,
  };
  const reorder = {
    'Dairy Concentrate Feed': '150 kg',
    'Napier Grass': '400 kg',
    'Calf Starter': '20 kg',
    'Mineral Mixture': '40 kg',
    'Rice Straw': '100 kg',
    'Wheat Bran': '100 kg',
    'Maize Silage': '300 kg',
    'Fattening Concentrate': '100 kg',
    'Molasses': '20 kg',
  };
  // Recent purchases, then an opening balance that makes the history add up.
  final purchases = {'Dairy Concentrate Feed': (1, 500.0), 'Fattening Concentrate': (10, 400.0), 'Wheat Bran': (6, 500.0)};
  var itemNo = 4000;
  final inventory = <Map<String, dynamic>>[];
  final stockTx = <Map<String, dynamic>>[];
  for (final MapEntry(key: item, value: (cost, category)) in feedItems.entries) {
    final id = 'ST-${++itemNo}';
    final now = stockNow[item]!;
    final bought = purchases[item]?.$2 ?? 0;
    final opening = now + (issued[item] ?? 0) - bought;
    final status = now <= double.parse(reorder[item]!.split(' ').first) ? 'Low stock' : 'In stock';
    inventory.add({'id': id, 'name': item, 'category': 'Feed', 'feedType': category, 'qty': _num(now), 'unit': 'kg', 'reorder': reorder[item], 'unitCost': money(cost), 'status': status});
    stockTx.add({'id': 'TX-OPEN-$id', 'date': d(125), 'item': item, 'type': FarmModule.txOpening, 'quantity': _num(opening), 'unitCost': money(cost), 'reference': 'Opening balance', 'notes': ''});
    final p = purchases[item];
    if (p != null) {
      stockTx
          .add({'id': 'TX-PUR-$id', 'date': d(p.$1), 'item': item, 'type': FarmModule.txPurchase, 'quantity': _num(p.$2), 'unitCost': money(cost), 'reference': 'INV-${2600 + itemNo}', 'notes': ''});
    }
  }
  inventory.addAll([
    {'id': 'ST-4101', 'name': 'FMD Vaccine', 'category': 'Vaccine', 'feedType': '', 'qty': '18', 'unit': 'vials', 'reorder': '10 vials', 'unitCost': '85', 'status': 'In stock'},
    {'id': 'ST-4102', 'name': 'Oxytetracycline Inj.', 'category': 'Medicine', 'feedType': '', 'qty': '6', 'unit': 'vials', 'reorder': '5 vials', 'unitCost': '220', 'status': 'In stock'},
    {'id': 'ST-4103', 'name': 'Milk Cans (40 L)', 'category': 'Equipment', 'feedType': '', 'qty': '12', 'unit': 'pcs', 'reorder': '4', 'unitCost': '2800', 'status': 'In stock'},
  ]);
  stockTx.addAll([
    {'id': 'TX-OPEN-ST-4101', 'date': d(125), 'item': 'FMD Vaccine', 'type': FarmModule.txOpening, 'quantity': '18', 'unitCost': '85', 'reference': 'Opening balance', 'notes': ''},
    {'id': 'TX-OPEN-ST-4102', 'date': d(125), 'item': 'Oxytetracycline Inj.', 'type': FarmModule.txOpening, 'quantity': '8', 'unitCost': '220', 'reference': 'Opening balance', 'notes': ''},
    {
      'id': 'TX-MA-02',
      'date': d(1),
      'item': 'Oxytetracycline Inj.',
      'type': FarmModule.txTreatment,
      'quantity': '1',
      'unitCost': '220',
      'reference': 'MA-02',
      'notes': 'Oxytetracycline Inj. · AN-1004 · Moti'
    },
    {
      'id': 'TX-MA-03',
      'date': d(0),
      'item': 'Oxytetracycline Inj.',
      'type': FarmModule.txTreatment,
      'quantity': '1',
      'unitCost': '220',
      'reference': 'MA-03',
      'notes': 'Oxytetracycline Inj. · AN-1004 · Moti'
    },
    {'id': 'TX-OPEN-ST-4103', 'date': d(125), 'item': 'Milk Cans (40 L)', 'type': FarmModule.txOpening, 'quantity': '12', 'unitCost': '2800', 'reference': 'Opening balance', 'notes': ''},
  ]);
  // Wastage that was already taken out of stock: recorded as history only.
  stockTx.add({'id': 'TX-WASTE-1', 'date': d(3), 'item': 'Napier Grass', 'type': FarmModule.txWastage, 'quantity': '40', 'unitCost': '6', 'reference': '', 'notes': 'Spoiled after rain'});
  for (final tx in stockTx) {
    if (tx['id'] == 'TX-OPEN-ST-4002') tx['quantity'] = _num(double.parse('${tx['quantity']}') + 40);
  }
  stockTx.addAll(issueTx);

  // ------------------------------------------------------------- production
  // Manure collected weekly (sold to a compost buyer or used on the fodder
  // plot), Lali's birth, and Doli's wool.
  final production = <Map<String, dynamic>>[];
  var prodId = 6000;
  for (var w = 70; w >= 7; w -= 7) {
    production.add({
      'id': 'PR-${prodId++}',
      'date': d(w),
      'product': 'Manure',
      'batch': '',
      'animal': '',
      'quantity': '${2800 + (w % 3) * 100}',
      'unit': 'kg',
      'saleable': '',
      'damaged': '',
      'headCount': '',
      'notes': 'Cow dung collected from Shed A and Shed B'
    });
  }
  production.addAll([
    {
      'id': 'PR-${prodId++}',
      'date': d(75),
      'product': 'Offspring',
      'batch': '',
      'animal': shona,
      'quantity': '1',
      'unit': 'head',
      'saleable': '',
      'damaged': '',
      'headCount': '',
      'notes': 'Female calf Lali (AN-1005)'
    },
    {
      'id': 'PR-${prodId++}',
      'date': d(40),
      'product': 'Wool',
      'batch': '',
      'animal': 'AN-1010 · Doli',
      'quantity': '1.5',
      'unit': 'kg',
      'saleable': '',
      'damaged': '',
      'headCount': '',
      'notes': 'Spring shearing'
    },
  ]);

  // ------------------------------------------------------------------ sales
  final sales = <Map<String, dynamic>>[];
  final usage = <Map<String, dynamic>>[];
  var saleId = 5000;
  var useId = 9500;
  Map<String, dynamic> sale(int daysAgo, String product, String customer, double qty, String unit, double price,
      {String batch = '', String animal = '', String item = '', double head = 0, double discount = 0, double deductions = 0, double? paid}) {
    final gross = qty * price;
    final net = gross - discount - deductions;
    final p = paid ?? net;
    final due = net - p;
    return {
      'id': 'SI-${saleId++}',
      'date': d(daysAgo),
      'product': product,
      'customer': customer,
      'animal': animal,
      'batch': batch,
      'item': item,
      'qty': _num(qty),
      'unit': unit,
      'unitPrice': _num(price),
      'headCount': head == 0 ? '' : _num(head),
      'gross': money(gross),
      'discount': discount == 0 ? '' : money(discount),
      'deductions': deductions == 0 ? '' : money(deductions),
      'amount': money(net),
      'paidAtSale': money(p),
      'paid': money(p),
      'due': money(due),
      'status': due <= 0 ? 'Paid' : (p > 0 ? 'Partial' : 'Due'),
    };
  }

  for (var i = 0; i < 14; i++) {
    final sellable = sellableMilkByDay[i]!;
    const internal = 3.0;
    final sold = (sellable - internal).floorToDouble();
    final rest = sellable - internal - sold;
    if (i == 1) {
      sales.add(sale(i, 'Milk', 'Rahman Grocery', sold, 'L', 120, item: 'Raw milk', paid: 0));
    } else {
      sales.add(sale(i, 'Milk', 'Green Valley Dairy', sold, 'L', 120, item: 'Raw milk'));
    }
    usage.add({'id': 'PU-${useId++}', 'date': d(i), 'product': 'Milk', 'usage': 'Internal use', 'quantity': _num(internal + rest), 'unit': 'L', 'batch': '', 'notes': 'Calf feeding and farm use'});
  }
  // Withheld milk (withdrawal period) never enters saleable stock, so it needs
  // no usage record of its own.
  // Fattening bulls and a goat sold at the haat (the animals are marked Sold),
  // and manure sold to a compost buyer.
  sales.addAll([
    sale(20, 'Live animal', 'Gabtoli Cattle Haat Agent', 1, 'head', 145000, animal: 'AN-1021 · Kalu', item: 'Fattened Deshi bull', deductions: 1500, paid: 100000),
    sale(15, 'Live animal', 'Rahman Cattle Traders', 1, 'head', 120000, animal: 'AN-1022 · Lalu', item: 'Fattened Sahiwal cross bull', paid: 0),
    sale(30, 'Live animal', 'Haji Beef House', 1, 'head', 18000, animal: 'AN-1023 · Sada', item: 'Black Bengal castrated buck'),
    sale(8, 'Live animal', 'Rahman Cattle Traders', 1, 'head', 35000, animal: 'AN-1024 · Bachchu', item: 'Bull calf', paid: 5000),
    sale(5, 'Manure', 'Krishi Seba Compost', 1500, 'kg', 4, item: 'Cow dung', paid: 0),
    sale(12, 'Manure', 'Moyna Store', 500, 'kg', 4, item: 'Cow dung (bagged)'),
  ]);
  usage.addAll([
    {'id': 'PU-${useId++}', 'date': d(21), 'product': 'Manure', 'usage': 'Internal use', 'quantity': '4000', 'unit': 'kg', 'batch': '', 'notes': 'Spread on the Napier fodder plot'},
    {'id': 'PU-${useId++}', 'date': d(35), 'product': 'Wool', 'usage': 'Given away', 'quantity': '1.5', 'unit': 'kg', 'batch': '', 'notes': 'To a local weaver'},
  ]);
  String ref(String customer, String product, [String? animal]) {
    final s = sales.firstWhere((s) => s['customer'] == customer && s['product'] == product && (animal == null || s['animal'] == animal));
    return '${s['id']} · $customer';
  }

  final duesMilk = sales.firstWhere((s) => s['customer'] == 'Rahman Grocery' && s['product'] == 'Milk');

  final records = <String, List<Map<String, dynamic>>>{
    FarmModule.species: [
      for (final (i, (name, category, tracking, products, unit)) in [
        ('Cattle', 'Cattle', 'Individual', 'Milk, Meat, Offspring, Manure, Hides & skins', 'head'),
        ('Buffalo', 'Buffalo', 'Individual', 'Milk, Meat, Offspring, Manure', 'head'),
        ('Goat', 'Goat & sheep', 'Individual', 'Milk, Meat, Offspring, Manure, Hides & skins', 'head'),
        ('Sheep', 'Goat & sheep', 'Individual', 'Meat, Wool, Milk, Offspring', 'head'),
        ('Mithun (Gayal)', 'Cattle', 'Individual', 'Meat, Offspring', 'head'),
        ('Red Chittagong Cattle', 'Cattle', 'Individual', 'Milk, Meat, Offspring, Manure', 'head'),
        ('Pig', 'Other livestock', 'Individual', 'Meat, Offspring', 'head'),
        ('Horse', 'Other livestock', 'Individual', 'Offspring', 'head'),
        ('Donkey', 'Other livestock', 'Individual', 'Offspring', 'head'),
        ('Yak', 'Other livestock', 'Individual', 'Milk, Meat, Wool, Offspring', 'head'),
      ].indexed)
        {'id': 'SP-${(i + 1).toString().padLeft(2, '0')}', 'name': name, 'category': category, 'tracking': tracking, 'products': products, 'countUnit': unit, 'notes': '', 'status': 'Active'},
    ],
    FarmModule.locations: [
      {'id': 'LC-01', 'name': 'Shed A', 'kind': 'Shed', 'capacity': '12', 'area': '2400 sq ft', 'notes': 'Milking cows', 'status': 'Active'},
      {'id': 'LC-02', 'name': 'Shed B', 'kind': 'Shed', 'capacity': '8', 'area': '1600 sq ft', 'notes': 'Bulls and heifers', 'status': 'Active'},
      {'id': 'LC-03', 'name': 'Isolation', 'kind': 'Isolation', 'capacity': '2', 'area': '', 'notes': 'Sick animals', 'status': 'Active'},
      {'id': 'LC-04', 'name': 'Calf pen', 'kind': 'Pen', 'capacity': '6', 'area': '', 'notes': '', 'status': 'Active'},
      {'id': 'LC-05', 'name': 'Goat house', 'kind': 'Pen', 'capacity': '15', 'area': '', 'notes': '', 'status': 'Active'},
      {'id': 'LC-06', 'name': 'Fattening Shed', 'kind': 'Shed', 'capacity': '10', 'area': '1800 sq ft', 'notes': 'Bulls for Qurbani sale', 'status': 'Active'},
      {'id': 'LC-07', 'name': 'Heifer Shed', 'kind': 'Shed', 'capacity': '8', 'area': '1200 sq ft', 'notes': '', 'status': 'Active'},
      {'id': 'LC-08', 'name': 'Bull Pen', 'kind': 'Pen', 'capacity': '3', 'area': '', 'notes': '', 'status': 'Active'},
      {'id': 'LC-09', 'name': 'Char Pasture', 'kind': 'Pasture', 'capacity': '30', 'area': '2 acres', 'notes': 'Grazing in the dry season', 'status': 'Active'},
    ],
    FarmModule.animals: [
      {
        'id': 'AN-1001',
        'name': 'Shona',
        'tag': 'BD-1001',
        'species': 'Cattle',
        'type': 'Cow',
        'breed': 'Holstein Friesian',
        'sex': 'Female',
        'dob': ago(years: 4, months: 2),
        'group': 'Lactating cows',
        'initialWeight': '380',
        'weight': '420',
        'status': 'Active',
        'location': 'Shed A',
        'sire': 'BULL-012 · Hero',
        'dam': '',
        'source': 'Purchased',
        'purchaseDate': ago(years: 1, months: 6),
        'purchasePrice': '185000',
        'notes': ''
      },
      {
        'id': 'AN-1002',
        'name': 'Rani',
        'tag': 'BD-1002',
        'species': 'Cattle',
        'type': 'Cow',
        'breed': 'Sahiwal Cross',
        'sex': 'Female',
        'dob': ago(years: 3, months: 5),
        'group': 'Lactating cows',
        'initialWeight': '330',
        'weight': '365',
        'status': 'Pregnant',
        'location': 'Shed A',
        'sire': 'BULL-009 · Tiger',
        'dam': '',
        'source': 'Purchased',
        'purchaseDate': ago(years: 1),
        'purchasePrice': '150000',
        'notes': ''
      },
      {
        'id': 'AN-1003',
        'name': 'Badsha',
        'tag': 'BD-1003',
        'species': 'Cattle',
        'type': 'Bull',
        'breed': 'Brahman Cross',
        'sex': 'Male',
        'dob': ago(years: 2, months: 3),
        'group': 'Bulls',
        'initialWeight': '410',
        'weight': '510',
        'status': 'Active',
        'location': 'Shed B',
        'sire': '',
        'dam': '',
        'source': 'Purchased',
        'purchaseDate': ago(months: 8),
        'purchasePrice': '210000',
        'notes': 'Fattening for sale'
      },
      {
        'id': 'AN-1004',
        'name': 'Moti',
        'tag': 'BD-1004',
        'species': 'Cattle',
        'type': 'Cow',
        'breed': 'Jersey Cross',
        'sex': 'Female',
        'dob': ago(years: 5, months: 1),
        'group': 'Lactating cows',
        'initialWeight': '',
        'weight': '390',
        'status': 'Treatment',
        'location': 'Isolation',
        'sire': 'BULL-018 · Sultan',
        'dam': '',
        'source': 'Born on farm',
        'purchaseDate': '',
        'purchasePrice': '',
        'notes': ''
      },
      {
        'id': 'AN-1005',
        'name': 'Lali',
        'tag': 'BD-1005',
        'species': 'Cattle',
        'type': 'Calf',
        'breed': 'Holstein Friesian Cross',
        'sex': 'Female',
        'dob': d(75),
        'group': 'Calves',
        'initialWeight': '36',
        'weight': '78',
        'status': 'Active',
        'location': 'Calf pen',
        'sire': 'BULL-018 · Sultan',
        'dam': shona,
        'source': 'Born on farm',
        'purchaseDate': '',
        'purchasePrice': '',
        'notes': ''
      },
      {
        'id': 'AN-1006',
        'name': 'Kali',
        'tag': 'BD-1006',
        'species': 'Goat',
        'type': 'Doe',
        'breed': 'Black Bengal',
        'sex': 'Female',
        'dob': ago(years: 2),
        'group': 'Goats',
        'initialWeight': '14',
        'weight': '19',
        'status': 'Active',
        'location': 'Goat house',
        'sire': '',
        'dam': '',
        'source': 'Purchased',
        'purchaseDate': ago(months: 10),
        'purchasePrice': '9500',
        'notes': ''
      },
    ],
    FarmModule.breeding: [
      {
        'id': 'BR-2005',
        'animal': shona,
        'date': d(40),
        'method': 'AI',
        'semen': 'SEM-7781',
        'bull': 'BULL-018 · Sultan',
        'technician': 'Rahim Uddin',
        'result': 'Pregnancy check due',
        'calvingDate': '',
        'cost': '500'
      },
      {
        'id': 'BR-2004',
        'animal': moti,
        'date': d(60),
        'method': 'AI',
        'semen': 'SEM-7720',
        'bull': 'BULL-012 · Hero',
        'technician': 'Karim Ali',
        'result': 'Not pregnant',
        'calvingDate': '',
        'cost': '500'
      },
      {
        'id': 'BR-2003',
        'animal': rani,
        'date': d(108),
        'method': 'AI',
        'semen': 'SEM-7781',
        'bull': 'BULL-018 · Sultan',
        'technician': 'Rahim Uddin',
        'result': 'Confirmed pregnant',
        'calvingDate': '',
        'cost': '500'
      },
      {
        'id': 'BR-2001',
        'animal': rani,
        'date': d(130),
        'method': 'AI',
        'semen': 'SEM-7720',
        'bull': 'BULL-012 · Hero',
        'technician': 'Karim Ali',
        'result': 'Not pregnant',
        'calvingDate': '',
        'cost': '500'
      },
      {
        'id': 'BR-2000',
        'animal': shona,
        'date': d(358),
        'method': 'AI',
        'semen': 'SEM-7781',
        'bull': 'BULL-018 · Sultan',
        'technician': 'Rahim Uddin',
        'result': 'Calved',
        'calvingDate': d(75),
        'cost': '500'
      },
    ],
    FarmModule.semen: [
      {
        'id': 'SM-5001',
        'code': 'SEM-7781',
        'bull': 'BULL-018 · Sultan',
        'breed': 'Sahiwal',
        'bullSire': 'BULL-003 · Raja Sr',
        'bullDam': 'COW-221 · Laxmi',
        'supplier': 'BRAC AI Centre',
        'straws': '9',
        'expiry': d(-400),
        'tank': 'Tank 1 · Canister A',
        'costPerStraw': '800',
        'status': 'Available'
      },
      {
        'id': 'SM-5002',
        'code': 'SEM-7720',
        'bull': 'BULL-012 · Hero',
        'breed': 'Holstein Friesian',
        'bullSire': '',
        'bullDam': '',
        'supplier': 'DLS AI Centre, Savar',
        'straws': '2',
        'expiry': d(-20),
        'tank': 'Tank 1 · Canister B',
        'costPerStraw': '1000',
        'status': 'Available'
      },
      {
        'id': 'SM-5003',
        'code': 'SEM-7802',
        'bull': 'BULL-025 · Raja',
        'breed': 'Holstein Friesian',
        'bullSire': 'BULL-012 · Hero',
        'bullDam': 'COW-310 · Bela',
        'supplier': 'American Dairy Ltd',
        'straws': '15',
        'expiry': d(-600),
        'tank': 'Tank 2 · Canister A',
        'costPerStraw': '1500',
        'status': 'Available'
      },
    ],
    FarmModule.weights: [
      for (final (cow, weights) in [
        (shona, [(90, 405), (60, 410), (30, 416), (2, 420)]),
        (rani, [(90, 345), (60, 352), (30, 359), (2, 365)]),
        (moti, [(60, 392), (30, 394), (2, 390)]),
        ('AN-1003 · Badsha', [(90, 470), (60, 485), (30, 498), (2, 510)]),
        ('AN-1005 · Lali', [(75, 36), (60, 45), (45, 53), (30, 61), (15, 70), (1, 78)]),
        ('AN-1006 · Kali', [(60, 17), (30, 18), (3, 19)]),
      ])
        for (final (daysAgo, kg) in weights) {'id': 'WT-${cow.substring(3, 7)}-$daysAgo', 'date': d(daysAgo), 'animal': cow, 'weight': '$kg', 'bcs': '3'},
    ]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    // Poultry, fish and bee batches are not part of this livestock system.
    FarmModule.batches: [],
    FarmModule.batchMovements: [],
    FarmModule.sampling: [],
    // Ten animals lost over the past year (each marked Dead in the register).
    FarmModule.mortality: [
      for (final (i, (animal, daysAgo, cause, disposal, notes)) in [
        ('AN-1011 · Chotu', 300, 'Calving / birth', 'Buried', 'Stillborn-weak calf, died on day 2'),
        ('AN-1012 · Bindu', 260, 'Disease', 'Buried', 'Calf pneumonia'),
        ('AN-1013 · Kalo', 220, 'Disease', 'Buried', 'PPR outbreak in the goat house'),
        ('AN-1014 · Dhola', 200, 'Accident', 'Buried', 'Fell into the drainage ditch'),
        ('AN-1015 · Mukta', 170, 'Heat stress', 'Buried', ''),
        ('AN-1016 · Pinki', 140, 'Disease', 'Burned', 'Suspected anthrax — vet informed, carcass burned'),
        ('AN-1017 · Bhola', 110, 'Predator', 'Buried', 'Jackal attack at night'),
        ('AN-1018 · Tara', 80, 'Disease', 'Buried', 'Lumpy skin disease'),
        ('AN-1019 · Chandu', 50, 'Unknown', 'Rendered', ''),
        ('AN-1020 · Lucky', 25, 'Calving / birth', 'Buried', 'Dystocia'),
      ].indexed)
        {'id': 'MO-${(i + 1).toString().padLeft(2, '0')}', 'date': d(daysAgo), 'animal': animal, 'batch': '', 'count': '1', 'cause': cause, 'disposal': disposal, 'notes': notes},
    ],
    FarmModule.feedRecords: feed..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    FarmModule.inventory: inventory,
    FarmModule.inventoryTx: stockTx..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    FarmModule.milkProduction: milk,
    FarmModule.production: production,
    FarmModule.productUsage: usage..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    FarmModule.health: [
      {
        'id': 'VH-7002',
        'animal': 'AN-1003 · Badsha',
        'batch': '',
        'date': d(5),
        'type': 'Vaccination',
        'details': 'FMD vaccine',
        'medicine': 'FMD Vaccine',
        'vet': 'Dr. Karim Ali',
        'withdrawalDays': '',
        'cost': '85',
        'next': d(-180),
        'status': 'Completed'
      },
      {
        'id': 'VH-7003',
        'animal': shona,
        'batch': '',
        'date': d(30),
        'type': 'Deworming',
        'details': 'Routine deworming',
        'medicine': 'Albendazole',
        'vet': '',
        'withdrawalDays': '',
        'cost': '150',
        'next': d(-60),
        'status': 'Completed'
      },
      {
        'id': 'VH-7004',
        'animal': toofan,
        'batch': '',
        'date': d(20),
        'type': 'Vaccination',
        'details': 'Anthrax vaccine',
        'medicine': 'Anthrax spore vaccine',
        'vet': 'Upazila Livestock Office',
        'withdrawalDays': '',
        'cost': '50',
        'next': d(-345),
        'status': 'Completed'
      },
      {
        'id': 'VH-7005',
        'animal': rani,
        'batch': '',
        'date': d(16),
        'type': 'Vaccination',
        'details': 'Haemorrhagic septicaemia (HS)',
        'medicine': 'HS vaccine',
        'vet': 'Upazila Livestock Office',
        'withdrawalDays': '',
        'cost': '60',
        'next': d(-165),
        'status': 'Completed'
      },
      {
        'id': 'VH-7006',
        'animal': rani,
        'batch': '',
        'date': d(-5),
        'type': 'Vaccination',
        'details': 'FMD booster (scheduled)',
        'medicine': 'FMD Vaccine',
        'vet': '',
        'withdrawalDays': '',
        'cost': '',
        'next': d(-5),
        'status': 'Scheduled'
      },
    ],
    // Illness care: Moti's mastitis (vet confirmed, under treatment, follow-up
    // booked), Lali's calf scour (recovered), Badsha's new limp (reported).
    FarmModule.illness: [
      {
        'id': 'IL-01',
        'animal': moti,
        'species': 'Cattle',
        'noticedAt': '${d(2)} 06:30',
        'reportedAt': '${d(2)} 07:15',
        'reportedBy': 'Rahim Uddin',
        'symptoms': 'Swollen, hot left rear udder quarter; clots in milk',
        'dangerSigns': '',
        'observations': 'Kicks when that quarter is milked',
        'appetite': 'Reduced',
        'water': 'Normal',
        'milkChange': 'Decreased',
        'behaviour': 'Restless at milking',
        'temperature': '39.8',
        'tempUnit': '°C',
        'injury': '',
        'severity': 'Moderate',
        'suspectedCause': 'Mastitis',
        'vetName': 'Dr. Karim Ali',
        'vetPhone': '01711000000',
        'notes': '',
        'stage': '',
        'diagnosisStatus': '',
        'diagnosis': '',
        'closure': '',
        'closedOn': '',
        'closureNotes': '',
        'reopenedCount': '0',
      },
      {
        'id': 'IL-02',
        'animal': 'AN-1005 · Lali',
        'species': 'Cattle',
        'noticedAt': '${d(40)} 17:00',
        'reportedAt': '${d(40)} 18:00',
        'reportedBy': 'Rahim Uddin',
        'symptoms': 'Watery diarrhoea, weak suckling',
        'dangerSigns': '',
        'observations': '',
        'appetite': 'Reduced',
        'water': 'Increased',
        'milkChange': 'Not milking / not applicable',
        'behaviour': 'Dull, lying down more',
        'temperature': '',
        'tempUnit': '',
        'injury': '',
        'severity': 'Moderate',
        'suspectedCause': 'Calf scour',
        'vetName': 'Dr. Karim Ali',
        'vetPhone': '01711000000',
        'notes': '',
        'stage': '',
        'diagnosisStatus': '',
        'diagnosis': '',
        'closure': 'Recovered',
        'closedOn': d(28),
        'closureNotes': 'Dung firm, suckling well; vet agreed to stop',
        'reopenedCount': '0',
      },
      {
        'id': 'IL-03',
        'animal': 'AN-1003 · Badsha',
        'species': 'Cattle',
        'noticedAt': '${d(0)} 07:00',
        'reportedAt': '${d(0)} 07:30',
        'reportedBy': 'Rahim Uddin',
        'symptoms': 'Limping on right hind leg',
        'dangerSigns': '',
        'observations': 'Still walking to the trough',
        'appetite': 'Normal',
        'water': 'Not checked',
        'milkChange': 'Not milking / not applicable',
        'behaviour': '',
        'temperature': '',
        'tempUnit': '',
        'injury': 'Small cut above the hoof',
        'severity': 'Low',
        'suspectedCause': '',
        'vetName': '',
        'vetPhone': '',
        'notes': '',
        'stage': '',
        'diagnosisStatus': '',
        'diagnosis': '',
        'closure': '',
        'closedOn': '',
        'closureNotes': '',
        'reopenedCount': '0',
      },
    ],
    FarmModule.consultations: [
      {
        'id': 'VC-01',
        'illness': 'IL-01 · Moti',
        'animal': moti,
        'date': d(1),
        'vetName': 'Dr. Karim Ali',
        'vetPhone': '01711000000',
        'observations': 'Left rear quarter firm and warm; CMT strongly positive',
        'diagnosis': 'Clinical mastitis (left rear quarter)',
        'diagnosisStatus': 'Veterinarian confirmed',
        'recommendedTreatment': 'Antibiotic injection as prescribed; strip the quarter 3× a day',
        'prescriptionRef': 'RX-2026-114',
        'fee': '500',
        'nextDate': d(-2),
        'instructions': 'Discard milk during treatment and the withdrawal period',
      },
      {
        'id': 'VC-02',
        'illness': 'IL-02 · Lali',
        'animal': 'AN-1005 · Lali',
        'date': d(39),
        'vetName': 'Dr. Karim Ali',
        'vetPhone': '01711000000',
        'observations': 'Mildly dehydrated; no fever recorded',
        'diagnosis': 'Calf scours — cause not determined',
        'diagnosisStatus': 'Suspected',
        'recommendedTreatment': 'Oral electrolytes; keep suckling',
        'prescriptionRef': '',
        'fee': '300',
        'nextDate': '',
        'instructions': 'Call if she stops drinking',
      },
    ],
    FarmModule.treatments: [
      {
        'id': 'TR-01',
        'illness': 'IL-01 · Moti',
        'animal': moti,
        'startDate': d(1),
        'endDate': d(-1),
        'medicine': 'Oxytetracycline Inj.',
        'activeIngredient': 'Oxytetracycline',
        'medicineType': 'Antibiotic',
        'dose': '10',
        'doseUnit': 'ml',
        'route': 'Intramuscular (IM)',
        'frequency': 'Once daily for 3 days',
        'prescribedBy': 'Dr. Karim Ali',
        'prescriptionRef': 'RX-2026-114',
        'stockItem': 'Oxytetracycline Inj.',
        'stockPerDose': '1',
        'withdrawalDays': '4',
        'cost': '1200',
        'outcome': 'Ongoing',
        'outcomeNotes': '',
        'notes': '',
      },
      {
        'id': 'TR-02',
        'illness': 'IL-02 · Lali',
        'animal': 'AN-1005 · Lali',
        'startDate': d(39),
        'endDate': d(36),
        'medicine': 'Oral electrolyte solution',
        'activeIngredient': '',
        'medicineType': 'Fluid / electrolyte',
        'dose': '2',
        'doseUnit': 'litres',
        'route': 'Oral',
        'frequency': 'Twice daily for 3 days',
        'prescribedBy': 'Dr. Karim Ali',
        'prescriptionRef': '',
        'stockItem': '',
        'stockPerDose': '',
        'withdrawalDays': '',
        'cost': '450',
        'outcome': 'Completed',
        'outcomeNotes': 'Course finished as prescribed',
        'notes': '',
      },
    ],
    FarmModule.medication: [
      {
        'id': 'MA-04',
        'treatment': 'TR-01 · Oxytetracycline Inj. · Moti',
        'animal': moti,
        'illness': 'IL-01 · Moti',
        'medicine': 'Oxytetracycline Inj.',
        'status': 'Scheduled',
        'scheduledAt': '${d(-1)} 08:00',
        'givenAt': '',
        'doseGiven': '',
        'administeredBy': '',
        'reason': '',
        'sideEffects': '',
        'notes': ''
      },
      {
        'id': 'MA-03',
        'treatment': 'TR-01 · Oxytetracycline Inj. · Moti',
        'animal': moti,
        'illness': 'IL-01 · Moti',
        'medicine': 'Oxytetracycline Inj.',
        'status': 'Given',
        'scheduledAt': '',
        'givenAt': '${d(0)} 08:10',
        'doseGiven': '10 ml',
        'administeredBy': 'Sabbir Hossain',
        'reason': '',
        'sideEffects': '',
        'notes': '',
        '_stockItem': 'Oxytetracycline Inj.',
        '_stockIssued': '1'
      },
      {
        'id': 'MA-02',
        'treatment': 'TR-01 · Oxytetracycline Inj. · Moti',
        'animal': moti,
        'illness': 'IL-01 · Moti',
        'medicine': 'Oxytetracycline Inj.',
        'status': 'Given',
        'scheduledAt': '',
        'givenAt': '${d(1)} 08:00',
        'doseGiven': '10 ml',
        'administeredBy': 'Sabbir Hossain',
        'reason': '',
        'sideEffects': '',
        'notes': '',
        '_stockItem': 'Oxytetracycline Inj.',
        '_stockIssued': '1'
      },
      {
        'id': 'MA-01',
        'treatment': 'TR-02 · Oral electrolyte solution · Lali',
        'animal': 'AN-1005 · Lali',
        'illness': 'IL-02 · Lali',
        'medicine': 'Oral electrolyte solution',
        'status': 'Given',
        'scheduledAt': '',
        'givenAt': '${d(39)} 09:00',
        'doseGiven': '2 litres',
        'administeredBy': 'Sabbir Hossain',
        'reason': '',
        'sideEffects': '',
        'notes': ''
      },
    ],
    FarmModule.followUps: [
      {
        'id': 'FU-01',
        'illness': 'IL-01 · Moti',
        'animal': moti,
        'dueDate': d(-2),
        'type': 'Vet visit',
        'assignedTo': 'Dr. Karim Ali',
        'status': 'Scheduled',
        'doneDate': '',
        'progress': '',
        'observations': '',
        'vetAssessment': '',
        'nextAction': '',
        'notes': ''
      },
      {
        'id': 'FU-02',
        'illness': 'IL-02 · Lali',
        'animal': 'AN-1005 · Lali',
        'dueDate': d(30),
        'type': 'Farm check',
        'assignedTo': 'Sabbir Hossain',
        'status': 'Done',
        'doneDate': d(30),
        'progress': 'Improved',
        'observations': 'Dung firming up, drinking well',
        'vetAssessment': '',
        'nextAction': 'Treatment finished — decide on recovery',
        'notes': ''
      },
    ],
    FarmModule.purchases: [
      {'id': 'PO-9001', 'date': d(1), 'supplier': 'Fresh Feed Traders', 'item': 'Dairy concentrate', 'qty': '500 kg', 'amount': '23000', 'status': 'Received'},
    ],
    FarmModule.sales: sales..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    // Later payments — never more than what is still owed on each sale.
    FarmModule.collections: [
      {'id': 'PY-01', 'date': d(0), 'sale': '${duesMilk['id']} · Rahman Grocery', 'customer': 'Rahman Grocery', 'amount': '2000', 'method': 'Cash', 'reference': '', 'notes': ''},
      {
        'id': 'PY-02',
        'date': d(10),
        'sale': ref('Gabtoli Cattle Haat Agent', 'Live animal'),
        'customer': 'Gabtoli Cattle Haat Agent',
        'amount': '30000',
        'method': 'Mobile banking',
        'reference': 'bKash 8F3K2',
        'notes': ''
      },
      {
        'id': 'PY-03',
        'date': d(2),
        'sale': ref('Gabtoli Cattle Haat Agent', 'Live animal'),
        'customer': 'Gabtoli Cattle Haat Agent',
        'amount': '13500',
        'method': 'Bank',
        'reference': 'DBBL 5521',
        'notes': 'Fully paid'
      },
      {
        'id': 'PY-04',
        'date': d(12),
        'sale': ref('Rahman Cattle Traders', 'Live animal', 'AN-1022 · Lalu'),
        'customer': 'Rahman Cattle Traders',
        'amount': '50000',
        'method': 'Cash',
        'reference': '',
        'notes': ''
      },
      {
        'id': 'PY-05',
        'date': d(6),
        'sale': ref('Rahman Cattle Traders', 'Live animal', 'AN-1022 · Lalu'),
        'customer': 'Rahman Cattle Traders',
        'amount': '40000',
        'method': 'Bank',
        'reference': 'DBBL 5588',
        'notes': ''
      },
      {
        'id': 'PY-06',
        'date': d(1),
        'sale': ref('Rahman Cattle Traders', 'Live animal', 'AN-1022 · Lalu'),
        'customer': 'Rahman Cattle Traders',
        'amount': '10000',
        'method': 'Mobile banking',
        'reference': 'Nagad 77Q1',
        'notes': ''
      },
      {'id': 'PY-07', 'date': d(0), 'sale': '${duesMilk['id']} · Rahman Grocery', 'customer': 'Rahman Grocery', 'amount': '1000', 'method': 'Cash', 'reference': '', 'notes': ''},
      {
        'id': 'PY-08',
        'date': d(4),
        'sale': ref('Rahman Cattle Traders', 'Live animal', 'AN-1024 · Bachchu'),
        'customer': 'Rahman Cattle Traders',
        'amount': '10000',
        'method': 'Cash',
        'reference': '',
        'notes': ''
      },
      {
        'id': 'PY-09',
        'date': d(1),
        'sale': ref('Rahman Cattle Traders', 'Live animal', 'AN-1024 · Bachchu'),
        'customer': 'Rahman Cattle Traders',
        'amount': '10000',
        'method': 'Cash',
        'reference': '',
        'notes': ''
      },
      {'id': 'PY-10', 'date': d(0), 'sale': ref('Krishi Seba Compost', 'Manure'), 'customer': 'Krishi Seba Compost', 'amount': '3000', 'method': 'Cash', 'reference': '', 'notes': ''},
    ],
    FarmModule.customers: [
      {'id': 'CU-10001', 'name': 'Green Valley Dairy', 'phone': '01700000001', 'type': 'Collection centre', 'balance': '0', 'status': 'Active'},
      {'id': 'CU-10002', 'name': 'Rahman Grocery', 'phone': '01800000002', 'type': 'Retail', 'balance': '0', 'status': 'Active'},
      {'id': 'CU-10003', 'name': 'Rahman Cattle Traders', 'phone': '01900000003', 'type': 'Trader', 'balance': '0', 'status': 'Active'},
      {'id': 'CU-10004', 'name': 'Gabtoli Cattle Haat Agent', 'phone': '01600000004', 'type': 'Trader', 'balance': '0', 'status': 'Active'},
      {'id': 'CU-10005', 'name': 'Haji Beef House', 'phone': '01500000005', 'type': 'Wholesale', 'balance': '0', 'status': 'Active'},
    ],
    FarmModule.expenses: [
      {
        'id': 'EX-6001',
        'date': d(1),
        'category': 'Feed',
        'amount': '23000',
        'description': 'Dairy concentrate 500 kg',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocNone,
        'payment': 'Paid',
        'paymentMethod': 'Cash',
        'reference': 'INV-2601',
        'vendor': 'Fresh Feed Traders',
        'notes': 'Stock purchase — feed cost is counted when fed'
      },
      {
        'id': 'EX-6002',
        'date': d(2),
        'category': 'Veterinary treatment',
        'amount': '2500',
        'description': 'Monthly vet retainer',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocEqual,
        'payment': 'Paid',
        'paymentMethod': 'Cash',
        'reference': '',
        'vendor': 'Dr. Karim Ali',
        'notes': ''
      },
      {
        'id': 'EX-6003',
        'date': d(10),
        'category': 'Labour and salaries',
        'amount': '45000',
        'description': 'Staff salaries',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocFeed,
        'payment': 'Paid',
        'paymentMethod': 'Bank',
        'reference': '',
        'vendor': '',
        'notes': ''
      },
      {
        'id': 'EX-6004',
        'date': d(5),
        'category': 'Electricity',
        'amount': '6500',
        'description': 'Electricity bill',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocEqual,
        'payment': 'Paid',
        'paymentMethod': 'Mobile banking',
        'reference': 'DESCO-7781',
        'vendor': 'DESCO',
        'notes': ''
      },
      {
        'id': 'EX-6005',
        'date': d(25),
        'category': 'Shed and building maintenance',
        'amount': '4000',
        'description': 'Shed A floor and drain repair',
        'scope': 'Location',
        'animal': '',
        'batch': '',
        'location': 'Shed A',
        'allocation': '',
        'payment': 'Paid',
        'paymentMethod': 'Cash',
        'reference': '',
        'vendor': 'Local mason',
        'notes': ''
      },
      {
        'id': 'EX-6006',
        'date': d(21),
        'category': 'Transportation',
        'amount': '2100',
        'description': 'Truck to Gabtoli haat',
        'scope': 'Animal',
        'animal': 'AN-1021 · Kalu',
        'batch': '',
        'location': '',
        'allocation': '',
        'payment': 'Paid',
        'paymentMethod': 'Cash',
        'reference': '',
        'vendor': 'Local pickup',
        'notes': ''
      },
      {
        'id': 'EX-6007',
        'date': d(2),
        'category': 'Equipment',
        'amount': '1500',
        'description': 'Chaff cutter blade',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocNone,
        'payment': 'Due',
        'paymentMethod': '',
        'reference': '',
        'vendor': 'Krishi Yantra Ghar',
        'notes': ''
      },
      {
        'id': 'EX-6008',
        'date': d(30),
        'category': 'Insurance',
        'amount': '3000',
        'description': 'Livestock insurance premium',
        'scope': FarmModule.scopeFarm,
        'animal': '',
        'batch': '',
        'location': '',
        'allocation': FarmModule.allocNone,
        'payment': 'Paid',
        'paymentMethod': 'Bank',
        'reference': '',
        'vendor': 'Green Delta',
        'notes': ''
      },
    ],
  };
  addDemoExtras(records, d, ago);
  addTeamDemo(records, d);
  return records;
}

String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
