import 'package:flutter/foundation.dart';

import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'health_rules.dart';

enum RecordSort { newest, oldest, nameAz }

/// Search, filter and sort state for one module's record list.
class RecordsController extends ChangeNotifier {
  RecordsController(this.module, {FarmController? farm, AuthController? auth})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance;

  final String module;
  final FarmController farm;
  final AuthController _auth;

  String _query = '';
  String _filter = 'All';
  RecordSort sort = RecordSort.newest;

  bool get canEdit => _auth.access.canEditModule(module);

  bool get canDelete => canEdit && _auth.access.canDelete;

  bool get canArchive => canDelete && FarmController.archiveStatus.containsKey(module);

  /// Batches and animals open a full profile when tapped.
  bool get hasProfile => module == FarmModule.animals || module == FarmModule.batches || module == FarmModule.illness;

  /// "All" plus every status that actually occurs in this module.
  List<String> get filters {
    final statuses = <String>{
      for (final r in all)
        if (r.status.isNotEmpty) r.status
    }.toList()
      ..sort();
    return ['All', ...statuses];
  }

  /// The active filter; falls back to "All" once no record has that status.
  String get filter => filters.contains(_filter) ? _filter : 'All';

  List<FarmRecord> get all => farm.list(module);

  /// The date a record is sorted by: the first of its date fields that is filled in.
  static const _dateFields = ['date', 'startDate', 'reportedAt', 'dueDate', 'givenAt', 'scheduledAt', 'dob', 'purchaseDate'];

  String _dateOf(FarmRecord r) {
    for (final f in _dateFields) {
      final v = '${r[f] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  List<FarmRecord> get filtered {
    final rows = all.where((r) => r.matches(query: _query, filter: filter)).toList();
    switch (sort) {
      case RecordSort.newest:
        rows.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
      case RecordSort.oldest:
        rows.sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
      case RecordSort.nameAz:
        rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return rows;
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setFilter(String value) {
    _filter = value;
    notifyListeners();
  }

  void setSort(RecordSort value) {
    sort = value;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  /// A calculated line shown on the record's card, or null.
  String? summaryFor(FarmRecord r) {
    switch (module) {
      case FarmModule.batches:
        final unit = '${r['countUnit'] ?? ''}'.trim();
        return 'Now: ${formatQty(farm.batchCount(r.reference))} ${unit.isEmpty ? 'head' : unit} (opened with ${r['initialCount']})';
      case FarmModule.locations:
        final animals = farm.list(FarmModule.animals).where((a) => FarmController.isActive(a) && '${a['location']}' == '${r['name']}').length;
        final batchHead = farm.list(FarmModule.batches).where((b) => FarmController.isActive(b) && '${b['location']}' == '${r['name']}').fold(0.0, (s, b) => s + farm.batchCount(b.reference));
        final occupancy = animals + batchHead;
        final cap = r.number('capacity');
        return 'Occupancy: ${formatQty(occupancy)}${cap > 0 ? ' of ${formatQty(cap)} (${(occupancy / cap * 100).toStringAsFixed(0)}%)' : ''}';
      case FarmModule.customers:
        final due = farm.list(FarmModule.sales).where((s) => '${s['customer']}' == '${r['name']}').fold(0.0, (t, s) => t + s.number('due')) + r.number('balance');
        return due > 0.005 ? 'Outstanding: ${farm.profile.currency}${due.toStringAsFixed(0)}' : 'Nothing outstanding';
      case FarmModule.species:
        final animals = farm.list(FarmModule.animals).where((a) => FarmController.isActive(a) && '${a['species']}' == '${r['name']}').length;
        final batches = farm.list(FarmModule.batches).where((b) => FarmController.isActive(b) && '${b['species']}' == '${r['name']}').length;
        return '$animals animals · $batches active batches';
      case FarmModule.feedRecords:
        return '${r['qty']} ${r['unit']} × ${farm.profile.currency}${r['unitPrice']} = ${farm.profile.currency}${r.number('totalCost').toStringAsFixed(0)}${'${r['source']}' == FarmModule.manualExpense ? ' · not from stock' : ''}';
      case FarmModule.sales:
        return 'Net ${farm.profile.currency}${r.number('amount').toStringAsFixed(0)} · received ${farm.profile.currency}${r.number('paid').toStringAsFixed(0)}${r.number('due') > 0.005 ? ' · due ${farm.profile.currency}${r.number('due').toStringAsFixed(0)}' : ''}';
      case FarmModule.illness:
        final urgent = HealthRules.isUrgent(farm, r);
        return '${r['stage']} · ${r['severity']}${urgent ? ' · URGENT — call a vet' : ''} · ${r['diagnosisStatus']}';
      case FarmModule.followUps:
        final overdue = '${r['status']}' == 'Scheduled' && (r.dateOf('dueDate')?.isBefore(farm.today) ?? false);
        return '${FarmRecord.displayName(r['animal'])} · due ${r['dueDate']}${overdue ? ' · OVERDUE' : ''}';
      case FarmModule.medication:
        return '${FarmRecord.displayName(r['animal'])} · ${r['medicine']} · ${r['status']}';
      case FarmModule.treatments:
        return '${FarmRecord.displayName(r['animal'])} · ${r['dose']} ${r['doseUnit']} · ${r['frequency']}';
      case FarmModule.consultations:
        return '${FarmRecord.displayName(r['animal'])} · ${r['diagnosisStatus']}';
      case FarmModule.tasks:
        return '${r['assignedTo']} · ${r['shift']} · ${r['status']}${'${r['checkedBy'] ?? ''}'.isEmpty ? '' : ' · checked by ${r['checkedBy']}'}';
      case FarmModule.requests:
        final est = r.number('estimatedAmount') > 0 ? ' · about ${farm.profile.currency}${r.number('estimatedAmount').toStringAsFixed(0)}' : '';
        return '${r['type']}$est · by ${r['requestedBy']} · ${r['status']}';
      case FarmModule.managerReports:
        return '${r['period']} report by ${r['submittedBy']} · ${r['status']}';
      case FarmModule.staff:
        final wage = _auth.access.canSeeFinance && r.number('wage') > 0 ? ' · ${farm.profile.currency}${r.number('wage').toStringAsFixed(0)}/month' : '';
        return '${r['job']}$wage';
      case FarmModule.expenses || FarmModule.purchases:
        final approval = '${r['approval'] ?? ''}';
        return approval.isEmpty || approval == FarmModule.approvalNotRequired ? null : 'Owner approval: $approval';
      case FarmModule.animals:
        final hs = '${r['healthStatus'] ?? ''}';
        return hs.isEmpty ? null : 'Health: $hs';
      case FarmModule.production:
        final unit = Units.baseOf('${r['unit']}');
        return '${'${r['product']}'}: ${r['quantity']} ${r['unit']}${'${r['saleable'] ?? ''}'.isNotEmpty ? ' · saleable ${r['saleable']}' : ''}${unit != '${r['unit']}' ? ' ($unit)' : ''}';
      default:
        return null;
    }
  }

  /// Records that depend on [record] (empty when it can be deleted).
  List<(String, FarmRecord)> linksTo(FarmRecord record) => farm.linksTo(module, record);

  Future<void> delete(FarmRecord record) async {
    if (!canDelete) throw StateError('${_auth.role?.label ?? 'Signed-out user'} cannot delete records');
    await farm.remove(module, record.id);
  }

  Future<void> archive(FarmRecord record) async {
    if (!canArchive) throw StateError('${_auth.role?.label ?? 'Signed-out user'} cannot archive records');
    await farm.archive(module, record);
  }
}
