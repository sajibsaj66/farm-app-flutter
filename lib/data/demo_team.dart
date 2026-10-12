import '../models/farm_module.dart';

/// Demo staff, their daily tasks, managers' requests and reports to the
/// owner, and owner approvals on large expenses and purchases. Report
/// summaries are worked out from the demo milk and feed records, so they
/// match what the farm shows.
void addTeamDemo(Map<String, List<Map<String, dynamic>>> m, String Function(int daysAgo) d) {
  void add(String module, List<Map<String, dynamic>> rows) => m.putIfAbsent(module, () => []).addAll(rows);
  const owner = 'Farhana Akter';
  const rahim = 'Rahim Uddin';
  const mahmud = 'Mahmudul Hasan';

  // ------------------------------------------------------------------ staff
  add(FarmModule.staff, [
    for (final (i, (name, job, phone, wage, active)) in [
      ('Sabbir Hossain', 'Herdsman', '01710000101', 14000, true),
      ('Jamal Mia', 'Feeder', '01710000102', 12000, true),
      ('Rasel Ahmed', 'Milker', '01710000103', 13000, true),
      ('Shilpi Rani', 'Milker', '01710000104', 13000, true),
      ('Mohon Das', 'Cleaner', '01710000105', 10000, true),
      ('Alamgir Hossain', 'Guard', '01710000106', 11000, true),
      ('Rina Begum', 'Feeder', '01710000107', 12000, true),
      ('Babul Mia', 'Driver', '01710000108', 15000, false),
      ('Sumon Sheikh', 'Cleaner', '01710000109', 10000, true),
      ('Laboni Akter', 'Supervisor', '01710000110', 18000, true),
    ].indexed)
      {
        'id': 'SF-${(i + 1).toString().padLeft(2, '0')}',
        'name': name,
        'job': job,
        'phone': phone,
        'joinDate': d(400 - i * 30),
        'wage': '$wage',
        'status': active ? 'Active' : 'Inactive',
        'notes': active ? '' : 'Left the farm',
      },
  ]);

  // ------------------------------------------------------------------ tasks
  Map<String, dynamic> task(String id, int daysAgo, String text, String area, String who, String shift, String status, {String notes = ''}) => {
        'id': id,
        'date': d(daysAgo),
        'task': text,
        'area': area,
        'assignedTo': who,
        'shift': shift,
        'status': status,
        'checkedBy': status == 'Done' ? rahim : '',
        'notes': notes,
      };
  add(FarmModule.tasks, [
    task('TK-01', 0, 'Milk Shona, Rani and Moti (Moti’s milk kept separate — withdrawal)', 'Milking', 'Rasel Ahmed', 'Morning', 'Done'),
    task('TK-02', 0, 'Feed concentrate and Napier to the lactating cows', 'Feeding', 'Jamal Mia', 'Morning', 'Done'),
    task('TK-03', 0, 'Clean Shed A and wash the milking area', 'Cleaning', 'Mohon Das', 'Morning', 'Pending'),
    task('TK-04', 0, 'Strip Moti’s left rear quarter three times', 'Animal health', 'Shilpi Rani', 'Afternoon', 'Pending'),
    task('TK-05', 0, 'Fattening ration for Toofan', 'Feeding', 'Rina Begum', 'Evening', 'Pending'),
    task('TK-06', 0, 'Check the feed store and count bags', 'Stock & store', 'Laboni Akter', 'Afternoon', 'Not done', notes: 'Store key with the owner today'),
    task('TK-07', 1, 'Evening milking', 'Milking', 'Shilpi Rani', 'Evening', 'Done'),
    task('TK-08', 1, 'Clean the calf pen and change bedding', 'Cleaning', 'Sumon Sheikh', 'Morning', 'Done'),
    task('TK-09', 1, 'Watch Sundori and Kali for heat signs', 'Breeding', 'Sabbir Hossain', 'Morning', 'Done'),
    task('TK-10', 1, 'Night watch of the sheds', 'Other', 'Alamgir Hossain', 'Night', 'Done'),
    task('TK-11', 2, 'Repair the water trough in Shed B', 'Maintenance', 'Sabbir Hossain', 'Afternoon', 'Done'),
    task('TK-12', 2, 'Spread manure on the Napier plot', 'Other', 'Mohon Das', 'Morning', 'Done'),
  ]);

  // --------------------------------------------------------------- requests
  Map<String, dynamic> request(String id, int daysAgo, String type, String title, String details, int amount, String status, {String by = rahim, int? neededIn, String note = ''}) => {
        'id': id,
        'date': d(daysAgo),
        'type': type,
        'title': title,
        'details': details,
        'estimatedAmount': amount == 0 ? '' : '$amount',
        'neededBy': neededIn == null ? '' : d(daysAgo - neededIn),
        'requestedBy': by,
        'status': status,
        'decisionNote': note,
        'decidedBy': status == 'Pending' ? '' : owner,
      };
  add(FarmModule.requests, [
    request('RQ-01', 0, 'Feed or supplies needed', 'Molasses is below the reorder level', '18 kg left; 100 kg lasts about a month', 3500, 'Pending', neededIn: 3),
    request('RQ-02', 1, 'Equipment', 'Second milking machine', 'The current machine needs frequent service; milking takes two hours', 65000, 'Pending', by: mahmud, neededIn: 30),
    request('RQ-03', 2, 'Animal purchase', 'Buy two Sahiwal cross heifers', 'From a known breeder in Sirajganj, vaccinated', 180000, 'Pending', neededIn: 20),
    request('RQ-04', 5, 'Veterinary or treatment cost', 'Mastitis test kit (CMT)', 'To check every milking cow weekly', 1200, 'Approved', note: 'Yes — buy from the vet pharmacy'),
    request('RQ-05', 8, 'Feed or supplies needed', 'Mineral mixture running low', '34 kg left', 6000, 'Approved', note: 'Approved, order 50 kg'),
    request('RQ-06', 12, 'Farm expansion', 'Build a second calf pen', 'Calves crowded during the rainy season', 120000, 'Rejected', by: mahmud, note: 'Not this year — after Qurbani sales'),
    request('RQ-07', 15, 'Large expense', 'Paint all sheds', 'Rust on the roof frames', 38000, 'Rejected', note: 'Only Shed A this month'),
    request('RQ-08', 20, 'Equipment', 'New chaff cutter blade', 'Current blade is blunt', 1500, 'Approved'),
    request('RQ-09', 25, 'Animal purchase', 'Two fattening bulls for Qurbani', 'Gabtoli haat, about 70 000 each', 140000, 'Approved', note: 'Approved within budget'),
    request('RQ-10', 30, 'Other', 'Hire a second night guard', 'Jackal attack near the goat house last month', 11000, 'Rejected', by: mahmud, note: 'Fix the fence first'),
  ]);

  // ---------------------------------------- reports from managers (summaries)
  final milk = m[FarmModule.milkProduction] ?? const [];
  final feed = m[FarmModule.feedRecords] ?? const [];
  double sumOn(List<Map<String, dynamic>> rows, String date, String field) => rows.where((r) => r['date'] == date).fold(0.0, (s, r) => s + (double.tryParse('${r[field]}') ?? 0));
  String daily(int daysAgo) {
    final date = d(daysAgo);
    final litres = sumOn(milk, date, 'litres');
    final kg = sumOn(feed, date, 'qty');
    final entries = feed.where((r) => r['date'] == date).length;
    return ['Milk: ${litres.toStringAsFixed(1)} L', 'Feed: ${kg.toStringAsFixed(0)} kg in $entries entries', 'Health: Moti under treatment for mastitis', 'Stock: Molasses and Mineral Mixture low']
        .join('\n');
  }

  add(FarmModule.managerReports, [
    for (var i = 1; i <= 9; i++)
      {
        'id': 'MR-${i.toString().padLeft(2, '0')}',
        'date': d(i),
        'period': 'Daily',
        'summary': daily(i),
        'issues': i == 2 ? 'Moti: swollen udder, vet called' : (i == 5 ? 'Napier grass spoiled after rain (40 kg)' : ''),
        'notes': i.isEven ? 'All tasks done' : '',
        'submittedBy': i.isOdd ? rahim : mahmud,
        'status': i <= 2 ? 'Submitted' : 'Reviewed',
        'ownerComment': i == 3 ? 'Good — keep Moti’s milk separate' : '',
      },
    {
      'id': 'MR-10',
      'date': d(20),
      'period': 'Monthly',
      'summary': 'Milk and feed in line with last month\nTwo fattening bulls sold at the haat\nOne calf lost (dystocia)',
      'issues': 'Need a second milking machine (see request)',
      'notes': '',
      'submittedBy': rahim,
      'status': 'Reviewed',
      'ownerComment': 'Discuss the machine next week',
    },
  ]);

  // ---------------------------------- owner approvals on expenses/purchases
  for (final module in [FarmModule.expenses, FarmModule.purchases]) {
    for (final r in m[module] ?? const <Map<String, dynamic>>[]) {
      r['approval'] ??= FarmModule.approvalNotRequired;
      r['decisionNote'] ??= '';
    }
  }
  add(FarmModule.expenses, [
    {
      'id': 'EX-6011',
      'date': d(1),
      'category': 'Equipment',
      'amount': '45000',
      'description': 'New chaff cutter machine',
      'scope': FarmModule.scopeFarm,
      'animal': '',
      'batch': '',
      'location': '',
      'allocation': FarmModule.allocNone,
      'payment': 'Due',
      'paymentMethod': '',
      'reference': 'Quote Q-114',
      'vendor': 'Krishi Yantra Ghar',
      'notes': 'Entered by the manager',
      'approval': FarmModule.approvalPending,
      'decisionNote': ''
    },
    {
      'id': 'EX-6012',
      'date': d(6),
      'category': 'Shed and building maintenance',
      'amount': '38000',
      'description': 'Paint all sheds',
      'scope': FarmModule.scopeFarm,
      'animal': '',
      'batch': '',
      'location': '',
      'allocation': FarmModule.allocNone,
      'payment': 'Due',
      'paymentMethod': '',
      'reference': '',
      'vendor': 'Local painter',
      'notes': '',
      'approval': FarmModule.approvalRejected,
      'decisionNote': 'Only Shed A this month'
    },
  ]);
  add(FarmModule.purchases, [
    {
      'id': 'PO-9011',
      'date': d(0),
      'supplier': 'Fresh Feed Traders',
      'item': 'Dairy concentrate',
      'qty': '2000 kg',
      'amount': '92000',
      'status': 'Ordered',
      'approval': FarmModule.approvalPending,
      'decisionNote': ''
    },
  ]);
}
