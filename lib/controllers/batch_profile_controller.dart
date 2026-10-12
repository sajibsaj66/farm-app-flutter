import 'package:flutter/foundation.dart';

import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'auth_controller.dart';
import 'batch_analytics.dart';
import 'farm_controller.dart';

/// State and actions for one batch's profile screen.
class BatchProfileController extends ChangeNotifier {
  BatchProfileController(this.batchId, {FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock;

  final String batchId;
  final FarmController farm;
  final AuthController _auth;
  final DateTime Function()? _clock;

  DateTime get today => dateOnly(_clock?.call() ?? farm.today);

  FarmRecord? get batch => farm.find(FarmModule.batches, batchId);

  BatchAnalytics? get analytics {
    final b = batch;
    return b == null ? null : BatchAnalytics(farm, b, today: today);
  }

  bool canOpen(String module) => _auth.access.canOpenModule(module);

  bool get canSeeFinance => _auth.access.canSeeFinance;

  bool get isOpen => batch != null && '${batch!['status']}' == 'Active';

  /// Closes the batch on [date] (the final settlement then covers its whole
  /// life). Returns an error message or null.
  Future<String?> closeBatch(DateTime date) async {
    final b = batch;
    if (b == null) return 'This batch no longer exists.';
    if (!canOpen(FarmModule.batches)) return 'Your role cannot close batches.';
    final start = b.dateOf('startDate');
    if (start != null && date.isBefore(start)) return 'The closing date is before the batch started.';
    if (date.isAfter(today)) return 'The closing date cannot be in the future.';
    try {
      await farm.update(FarmModule.batches, FarmRecord({...b.toJson(), 'status': 'Closed', 'closeDate': formatDate(date)}), activity: 'Batch ${b['name']} closed');
      return null;
    } on FarmRuleException catch (e) {
      return e.message;
    }
  }
}
