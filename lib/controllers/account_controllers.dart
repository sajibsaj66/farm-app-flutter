import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/utils/dates.dart';
import '../models/activity_entry.dart';
import '../models/farm_profile.dart';
import '../models/user_role.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';

/// Change the signed-in user's own password.
class ChangePasswordController extends ChangeNotifier {
  ChangePasswordController({AuthController? auth}) : _auth = auth ?? AuthController.instance;

  final AuthController _auth;

  final formKey = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();

  bool busy = false;
  String? error;

  String? validateConfirm(String? v) => v != next.text ? 'Passwords do not match' : null;

  Future<bool> submit() async {
    if (busy || !formKey.currentState!.validate()) return false;
    busy = true;
    error = null;
    notifyListeners();
    error = await _auth.changeOwnPassword(current: current.text, next: next.text);
    busy = false;
    notifyListeners();
    return error == null;
  }

  @override
  void dispose() {
    for (final c in [current, next, confirm]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Owner-only: edit the farm's name, location, contact and currency.
class FarmProfileController extends ChangeNotifier {
  FarmProfileController({FarmController? farm}) : _farm = farm ?? FarmController.instance {
    final p = _farm.profile;
    name.text = p.name;
    location.text = p.location;
    phone.text = p.phone;
    currency.text = p.currency;
    milkPrice.text = formatQty(p.milkPrice);
  }

  final FarmController _farm;

  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final location = TextEditingController();
  final phone = TextEditingController();
  final currency = TextEditingController();
  final milkPrice = TextEditingController();

  bool busy = false;

  String? validateName(String? v) => (v == null || v.trim().length < 2) ? 'Please enter the farm name' : null;

  String? validatePhone(String? v) => (v == null || v.trim().isEmpty || RegExp(r'^\+?[0-9 -]{6,16}$').hasMatch(v.trim())) ? null : 'Enter a valid phone number';

  String? validateCurrency(String? v) => (v == null || v.trim().isEmpty || v.trim().length > 4) ? 'Use a short symbol, e.g. ৳' : null;

  String? validateMilkPrice(String? v) {
    final n = double.tryParse(v?.trim() ?? '');
    return n == null || n <= 0 ? 'Enter the price per litre, e.g. 120' : null;
  }

  Future<bool> save() async {
    if (busy || !formKey.currentState!.validate()) return false;
    busy = true;
    notifyListeners();
    // copyWith keeps the calculation settings, which have their own screen.
    await _farm.updateProfile(
        _farm.profile.copyWith(name: name.text.trim(), location: location.text.trim(), phone: phone.text.trim(), currency: currency.text.trim(), milkPrice: double.parse(milkPrice.text.trim())));
    busy = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    for (final c in [name, location, phone, currency, milkPrice]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Owner-only: copy all farm data out as JSON, or restore it from a copy.
class BackupController extends ChangeNotifier {
  BackupController({FarmController? farm, AuthController? auth})
      : _farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance;

  final FarmController _farm;
  final AuthController _auth;

  final restoreInput = TextEditingController();
  bool busy = false;
  String? error;

  bool get allowed => _auth.role == UserRole.owner;

  /// When the automatic backup (taken before demo data was loaded) was made.
  DateTime? get autoBackupDate => _farm.autoBackupDate;

  Future<bool> restoreAutoBackup() async {
    if (!allowed) {
      error = 'Only the Farm Owner can restore data.';
      notifyListeners();
      return false;
    }
    try {
      await _farm.restoreAutoBackup();
      return true;
    } on FarmRuleException catch (e) {
      error = e.message;
      return false;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } finally {
      notifyListeners();
    }
  }

  String buildBackup() => const JsonEncoder.withIndent('  ').convert(_farm.exportData());

  /// Checks the pasted text; returns an error message or null when it is a
  /// valid backup.
  Map<String, dynamic>? _parse() {
    final text = restoreInput.text.trim();
    if (text.isEmpty) {
      error = 'Paste a backup first.';
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('The backup must be a JSON object.');
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      error = 'This text is not a valid backup.';
      return null;
    }
  }

  Future<bool> restore() async {
    if (!allowed) {
      error = 'Only the Farm Owner can restore data.';
      notifyListeners();
      return false;
    }
    error = null;
    final data = _parse();
    if (data == null) {
      notifyListeners();
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      await _farm.restore(data);
      restoreInput.clear();
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    restoreInput.dispose();
    super.dispose();
  }
}

/// Owner only: how profit, feed cost, asset cost and alerts are calculated.
class CalculationSettingsController extends ChangeNotifier {
  CalculationSettingsController({FarmController? farm}) : _farm = farm ?? FarmController.instance {
    final p = _farm.profile;
    feedCostBasis = p.feedCostBasis;
    assetMethod = p.assetMethod;
    years.text = formatQty(p.depreciationYears);
    residual.text = formatQty(p.residualPercent);
    mortality.text = formatQty(p.mortalityAlertPercent);
    lowMilk.text = formatQty(p.lowMilkPercent);
    approvalLimit.text = formatQty(p.approvalLimit);
    budget.text = formatQty(p.monthlyBudget);
  }

  final FarmController _farm;
  final formKey = GlobalKey<FormState>();
  final years = TextEditingController();
  final residual = TextEditingController();
  final mortality = TextEditingController();
  final lowMilk = TextEditingController();
  final approvalLimit = TextEditingController();
  final budget = TextEditingController();
  late FeedCostBasis feedCostBasis;
  late AssetMethod assetMethod;
  bool busy = false;

  void setFeedCostBasis(FeedCostBasis v) {
    feedCostBasis = v;
    notifyListeners();
  }

  void setAssetMethod(AssetMethod v) {
    assetMethod = v;
    notifyListeners();
  }

  static String? _range(String? v, double min, double max, String what) {
    final n = double.tryParse(v?.trim() ?? '');
    return n == null || n < min || n > max ? 'Enter $what between ${formatQty(min)} and ${formatQty(max)}' : null;
  }

  String? validateYears(String? v) => _range(v, 1, 30, 'years');
  String? validateResidual(String? v) => _range(v, 0, 100, 'a percentage');
  String? validatePercent(String? v) => _range(v, 0, 100, 'a percentage');
  String? validateMoney(String? v) => _range(v, 0, 100000000, 'an amount');

  Future<bool> save() async {
    if (busy || !formKey.currentState!.validate()) return false;
    busy = true;
    notifyListeners();
    await _farm.updateProfile(_farm.profile.copyWith(
      feedCostBasis: feedCostBasis,
      assetMethod: assetMethod,
      depreciationYears: double.parse(years.text.trim()),
      residualPercent: double.parse(residual.text.trim()),
      mortalityAlertPercent: double.parse(mortality.text.trim()),
      lowMilkPercent: double.parse(lowMilk.text.trim()),
      approvalLimit: double.parse(approvalLimit.text.trim()),
      monthlyBudget: double.parse(budget.text.trim()),
    ));
    busy = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    for (final c in [years, residual, mortality, lowMilk, approvalLimit, budget]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Owner/manager: searchable audit trail of who changed what.
class ActivityLogController extends ChangeNotifier {
  ActivityLogController({FarmController? farm}) : farm = farm ?? FarmController.instance;

  final FarmController farm;
  String _query = '';

  List<ActivityEntry> get entries {
    final q = _query.toLowerCase();
    return farm.activity.where((a) => q.isEmpty || '${a.title} ${a.by ?? ''} ${a.time}'.toLowerCase().contains(q)).toList();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }
}
