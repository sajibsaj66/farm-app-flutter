import 'package:flutter/foundation.dart';

import '../models/access_policy.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';

/// One item on the Approvals screen.
class ApprovalItem {
  const ApprovalItem({required this.module, required this.record, required this.title, required this.detail, required this.status, this.amount});

  final String module;
  final FarmRecord record;
  final String title;
  final String detail;

  /// Pending owner approval, Approved, Rejected, Submitted, Reviewed…
  final String status;
  final double? amount;

  bool get isReport => module == FarmModule.managerReports;
}

/// The owner's decision queue — large expenses and purchases, managers'
/// requests and reports — and, for a manager, what happened to theirs.
class ApprovalsController extends ChangeNotifier {
  ApprovalsController({FarmController? farm, AuthController? auth})
      : farm = farm ?? FarmController.instance,
        auth = auth ?? AuthController.instance;

  final FarmController farm;
  final AuthController auth;

  AccessPolicy get access => auth.access;

  bool get canDecide => access.canApprove;

  String money(double v) => '${farm.profile.currency}${v.toStringAsFixed(0)}';

  ApprovalItem _item(String module, FarmRecord r) => switch (module) {
        FarmModule.expenses => ApprovalItem(
            module: module,
            record: r,
            title: 'Expense: ${r['description']}',
            detail: '${r['category']} · ${r['date']}${'${r['vendor'] ?? ''}'.isEmpty ? '' : ' · ${r['vendor']}'}',
            status: '${r['approval']}',
            amount: r.number('amount')),
        FarmModule.purchases =>
          ApprovalItem(module: module, record: r, title: 'Purchase: ${r['item']} (${r['qty']})', detail: '${r['supplier']} · ${r['date']}', status: '${r['approval']}', amount: r.number('amount')),
        FarmModule.requests => ApprovalItem(
            module: module,
            record: r,
            title: 'Request: ${r['title']}',
            detail: '${r['type']} · by ${r['requestedBy']} · ${r['date']}${'${r['neededBy'] ?? ''}'.isEmpty ? '' : ' · needed by ${r['neededBy']}'}',
            status: '${r['status']}',
            amount: r.number('estimatedAmount') > 0 ? r.number('estimatedAmount') : null),
        _ => ApprovalItem(module: module, record: r, title: '${r['period']} report · ${r['date']}', detail: 'From ${r['submittedBy']}', status: '${r['status']}'),
      };

  /// Waiting for the owner (only the parts this user may see).
  List<ApprovalItem> get pending => [
        for (final (m, r) in farm.pendingDecisions)
          if (access.canOpenModule(m) && (canDecide || _isMine(m, r))) _item(m, r),
      ];

  /// Decided items, newest first (managers see their own).
  List<ApprovalItem> decided({int limit = 15}) {
    final out = <ApprovalItem>[];
    for (final m in [FarmModule.expenses, FarmModule.purchases]) {
      if (!access.canOpenModule(m)) continue;
      for (final r in farm.list(m).where((r) => '${r['approval']}' == FarmModule.approvalApproved || '${r['approval']}' == FarmModule.approvalRejected)) {
        out.add(_item(m, r));
      }
    }
    for (final r in farm.list(FarmModule.requests).where((r) => '${r['status']}' != 'Pending')) {
      if (canDecide || _isMine(FarmModule.requests, r)) out.add(_item(FarmModule.requests, r));
    }
    for (final r in farm.list(FarmModule.managerReports).where((r) => '${r['status']}' == 'Reviewed')) {
      if (canDecide || _isMine(FarmModule.managerReports, r)) out.add(_item(FarmModule.managerReports, r));
    }
    out.sort((a, b) => '${b.record['date']}'.compareTo('${a.record['date']}'));
    return out.take(limit).toList();
  }

  bool _isMine(String module, FarmRecord r) {
    final me = auth.currentUser?.name;
    return switch (module) {
      FarmModule.requests => '${r['requestedBy']}' == me,
      FarmModule.managerReports => '${r['submittedBy']}' == me,
      _ => true, // expenses and purchases: anyone who may open them
    };
  }

  /// Returns an error message, or null when saved.
  Future<String?> decide(ApprovalItem item, {required bool approve, String note = ''}) async {
    try {
      await farm.decide(item.module, item.record.id, approve: approve, note: note);
      notifyListeners();
      return null;
    } on FarmRuleException catch (e) {
      return e.message;
    }
  }
}
