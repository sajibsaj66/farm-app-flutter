import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/access_policy.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'farm_controller.dart';
import 'health_rules.dart';

/// The day's (or month's) operations in a few lines, worked out from the
/// saved records — the starting text of a manager's report to the owner.
/// Money lines appear only for sections the user may open.
class OperationsSummary {
  OperationsSummary._();

  static String build(FarmController farm, AccessPolicy access, DateTime date, {bool monthly = false}) {
    final day = dateOnly(date);
    final from = monthly ? DateTime(day.year, day.month) : day;
    final to = monthly ? DateTime(day.year, day.month + 1, 0) : day;
    final cur = farm.profile.currency;
    Iterable<FarmRecord> rows(String m) => farm.inRange(m, from, to);
    String q(double v) => formatQty(double.parse(v.toStringAsFixed(1)));

    final milk = rows(FarmModule.milkProduction);
    final litres = milk.fold(0.0, (s, m) => s + m.number('litres'));
    final withheld = milk.where((m) => !FarmController.isSellableMilk(m)).fold(0.0, (s, m) => s + m.number('litres'));
    final feed = rows(FarmModule.feedRecords);
    final feedKg = feed.fold(0.0, (s, r) => s + (Units.kg(r.number('qty'), '${r['unit'] ?? 'kg'}') ?? 0));
    final newCases = farm.list(FarmModule.illness).where((c) {
      final d = c.dateOf('reportedAt');
      return d != null && !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);
    }).length;
    final open = farm.list(FarmModule.illness).where((c) => HealthRules.isOpen(c.data)).toList();
    final urgent = open.where((c) => HealthRules.isUrgent(farm, c)).length;
    final doses = farm.list(FarmModule.medication).where((m) {
      final d = m.dateOf('givenAt');
      return d != null && !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);
    }).length;
    final deaths = rows(FarmModule.mortality).fold(0.0, (s, r) => s + (r.number('count') > 0 ? r.number('count') : 1));
    final low = farm.list(FarmModule.inventory).where((i) => i.isLowStock).map((i) => '${i['name']} (${i['qty']} ${i['unit']})').toList();
    final tasks = rows(FarmModule.tasks);
    final done = tasks.where((t) => '${t['status']}' == 'Done').length;

    return [
      'Milk: ${q(litres)} L${withheld > 0 ? ' (${q(withheld)} L withheld, not for sale)' : ''}',
      'Feed: ${q(feedKg)} kg in ${feed.length} entries',
      'Health: $newCases new case(s), ${open.length} open${urgent > 0 ? ', $urgent urgent' : ''}; $doses dose(s) given',
      if (deaths > 0) 'Deaths: ${formatQty(deaths)}',
      'Stock: ${low.isEmpty ? 'nothing below reorder level' : 'low — ${low.join(', ')}'}',
      if (tasks.isNotEmpty) 'Staff tasks: $done of ${tasks.length} done',
      if (access.canOpenModule(FarmModule.sales)) 'Sales: $cur${rows(FarmModule.sales).fold(0.0, (s, r) => s + r.number('amount')).toStringAsFixed(0)} (${rows(FarmModule.sales).length})',
      if (access.canOpenModule(FarmModule.expenses))
        'Expenses: $cur${rows(FarmModule.expenses).where((e) => !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, r) => s + r.number('amount')).toStringAsFixed(0)}',
    ].join('\n');
  }
}
