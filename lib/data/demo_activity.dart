import '../models/farm_module.dart';

/// Demo activity log: who recorded what, one entry per demo record below, so
/// the Activity log and each user's "recent changes" are not empty on a demo
/// farm. Every entry points at a record that exists in the demo data.
///
/// Each entry: (module, demo user name, hour of day).
List<Map<String, dynamic>> buildDemoActivity(Map<String, List<Map<String, dynamic>>> records, DateTime now) {
  const plan = [
    (FarmModule.milkProduction, 'Mahmudul Hasan', 6),
    (FarmModule.feedRecords, 'Rahim Uddin', 7),
    (FarmModule.production, 'Sharmin Akter', 8),
    (FarmModule.illness, 'Rahim Uddin', 9),
    (FarmModule.medication, 'Habibur Rahman', 10),
    (FarmModule.followUps, 'Rahim Uddin', 11),
    (FarmModule.weights, 'Rokeya Begum', 12),
    (FarmModule.mortality, 'Rahim Uddin', 13),
    (FarmModule.sales, 'Rahim Uddin', 14),
    (FarmModule.collections, 'Mahmudul Hasan', 15),
    (FarmModule.expenses, 'Farhana Akter', 16),
    (FarmModule.purchases, 'Farhana Akter', 17),
    (FarmModule.inventoryTx, 'Rahim Uddin', 18),
    (FarmModule.breeding, 'Sharmin Akter', 19),
  ];
  const dateFields = ['date', 'reportedAt', 'givenAt', 'dueDate', 'startDate'];
  final out = <Map<String, dynamic>>[];
  for (final (module, by, hour) in plan) {
    final rows = records[module] ?? const [];
    // The newest record of the module that has a date.
    Map<String, dynamic>? newest;
    DateTime? newestDate;
    for (final r in rows) {
      for (final f in dateFields) {
        final d = DateTime.tryParse('${r[f] ?? ''}'.trim());
        if (d == null) continue;
        if (newestDate == null || d.isAfter(newestDate)) {
          newest = r;
          newestDate = d;
        }
        break;
      }
    }
    if (newest == null || newestDate == null) continue;
    var at = DateTime(newestDate.year, newestDate.month, newestDate.day, hour, (hour * 7) % 60);
    // Never in the future.
    if (at.isAfter(now)) at = now.subtract(Duration(minutes: 20 - hour));
    out.add({'title': 'New $module record added · ${newest['id']}', 'time': at.toIso8601String(), 'by': by});
  }
  out.sort((a, b) => '${b['time']}'.compareTo('${a['time']}'));
  return out;
}
