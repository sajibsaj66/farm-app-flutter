import 'package:flutter/material.dart';

import '../core/utils/dates.dart' as dates;
import '../core/utils/field_utils.dart';
import '../core/utils/units.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import '../models/field_spec.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'health_rules.dart';
import 'herd_analytics.dart';
import 'operations_summary.dart';

/// Owns the add/edit form for a module: which fields it shows, how each is
/// entered, validation and saving. Business rules live in [FarmController];
/// a broken rule comes back as [error] instead of a crash.
class RecordFormController extends ChangeNotifier {
  RecordFormController({required this.module, this.existing, Map<String, String> initialValues = const {}, FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : _farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock ?? DateTime.now {
    final rows = _farm.list(module);
    final sample = existing?.data ?? (rows.isNotEmpty ? rows.first.data : <String, dynamic>{});
    fields = FarmModule.fieldsFor(module, sample);
    for (final field in fields) {
      final spec = specFor(field);
      var initial = '${existing?[field] ?? initialValues[field] ?? ''}';
      if (existing == null && initial.isEmpty) initial = _defaultFor(field, spec);
      textControllers[field] = TextEditingController(text: initial);
    }
    if (existing == null) _fillDerived(null);
  }

  final String module;
  final FarmRecord? existing;
  final FarmController _farm;
  final AuthController _auth;
  final DateTime Function() _clock;

  final formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> textControllers = {};
  late final List<String> fields;

  bool saving = false;

  /// A business rule the save broke (shown above the Save button).
  String? error;

  bool get isEditing => existing != null;

  /// Whether the signed-in user may change this module. Without it the form
  /// shows the record read-only and refuses to save.
  bool get canEdit => _auth.access.canEditModule(module);

  String get title => !canEdit ? '$module details' : (isEditing ? 'Edit $module' : 'Add $module');

  String get _noEditMessage => '${_auth.role?.label ?? 'Signed-out user'} can view $module but not change it. Ask the farm owner or manager.';

  FieldSpec specFor(String field) => FarmModule.specFor(module, field);

  String labelFor(String field) => specFor(field).label ?? fieldLabel(field);

  String valueOf(String field) => textControllers[field]?.text.trim() ?? '';

  static String formatDate(DateTime d) => dates.formatDate(d);

  DateTime initialDateFor(String field) => FarmRecord.parseDate(textControllers[field]?.text) ?? _clock();

  static String formatDateTime(DateTime d) => '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String get _now => formatDateTime(_clock());

  /// The last summary filled in automatically (so a manager's own text is
  /// never overwritten).
  String _lastSummary = '';

  String _summaryFor(String period, DateTime date) => _lastSummary = OperationsSummary.build(_farm, _auth.access, date, monthly: period == 'Monthly');

  String _defaultFor(String field, FieldSpec spec) {
    if (spec.type == FieldType.date && spec.required) return formatDate(_clock());
    final me = _farm.actor() ?? '';
    final profile = _farm.profile;
    return switch ((module, field)) {
      (FarmModule.feedRecords, 'source') => FarmModule.fromInventory,
      (FarmModule.expenses, 'scope') => FarmModule.scopeFarm,
      (FarmModule.expenses, 'allocation') => FarmModule.allocNone,
      (FarmModule.expenses, 'payment') => 'Paid',
      (FarmModule.species, 'status') || (FarmModule.locations, 'status') || (FarmModule.batches, 'status') || (FarmModule.customers, 'status') => 'Active',
      (FarmModule.animals, 'status') => 'Active',
      (FarmModule.species, 'tracking') => FarmModule.trackIndividual,
      (FarmModule.milkProduction, 'quality') => 'Accepted',
      (FarmModule.collections, 'method') => 'Cash',
      // Illness report: times default to now; unknown observations stay
      // "Not checked" — never an assumed normal value.
      (FarmModule.illness, 'noticedAt') || (FarmModule.illness, 'reportedAt') => _now,
      (FarmModule.illness, 'reportedBy') => me,
      (FarmModule.illness, 'appetite') || (FarmModule.illness, 'water') || (FarmModule.illness, 'milkChange') => 'Not checked',
      (FarmModule.illness, 'vetName') || (FarmModule.consultations, 'vetName') || (FarmModule.treatments, 'prescribedBy') => profile.defaultVetName,
      (FarmModule.illness, 'vetPhone') || (FarmModule.consultations, 'vetPhone') => profile.defaultVetPhone,
      (FarmModule.consultations, 'diagnosisStatus') => FarmModule.diagNotEvaluated,
      (FarmModule.treatments, 'outcome') => FarmModule.treatmentOngoing,
      (FarmModule.medication, 'status') => FarmModule.medGiven,
      (FarmModule.medication, 'givenAt') => _now,
      (FarmModule.medication, 'administeredBy') => me,
      (FarmModule.followUps, 'status') => 'Scheduled',
      (FarmModule.followUps, 'type') => 'Farm check',
      (FarmModule.tasks, 'status') => 'Pending',
      (FarmModule.staff, 'status') => 'Active',
      (FarmModule.managerReports, 'period') => 'Daily',
      (FarmModule.managerReports, 'summary') => _summaryFor('Daily', _clock()),
      (FarmModule.requests, 'requestedBy') => me,
      (FarmModule.managerReports, 'submittedBy') => me,
      _ => '',
    };
  }

  /// Read-only: worked out on save, or locked after creation.
  bool isReadOnly(String field) {
    final spec = specFor(field);
    // Approval decisions and report reviews belong to the owner.
    if (spec.ownerOnly && !_auth.access.canApprove) return true;
    return !canEdit || spec.computed || (spec.lockedOnEdit && isEditing);
  }

  /// Free-text fields shown over several lines.
  static const _longText = {'summary', 'details', 'issues', 'notes', 'observations', 'ownerComment', 'decisionNote', 'instructions', 'closureNotes'};

  bool isLongText(String field) => _longText.contains(field);

  /// Hides fields that do not apply (e.g. the allocation method for an
  /// expense charged to one animal).
  bool isVisible(String field) {
    // Livestock only: batch (flock/pond/hive) fields are shown only on older
    // records that already hold a value, so nothing saved is lost.
    if (!FarmModule.outOfScope.contains(module) && (specFor(field).type == FieldType.batch || field == 'headCount')) {
      return valueOf(field).isNotEmpty;
    }
    switch ((module, field)) {
      case (FarmModule.expenses, 'animal'):
        return valueOf('scope') == 'Animal';
      case (FarmModule.expenses, 'batch'):
        return valueOf('scope') == 'Batch';
      case (FarmModule.expenses, 'location'):
        return valueOf('scope') == 'Location';
      case (FarmModule.expenses, 'allocation'):
        return valueOf('scope') == FarmModule.scopeFarm;
      case (FarmModule.feedRecords, 'unitPrice') || (FarmModule.feedRecords, 'totalCost'):
        return true;
      case (FarmModule.breeding, 'semen'):
        return valueOf('method') != 'Natural mating';
      case (FarmModule.sales, 'animal'):
        return valueOf('product') == 'Live animal' || valueOf('animal').isNotEmpty;
      case (FarmModule.sales, 'headCount'):
        return valueOf('product') == 'Live birds' || valueOf('batch').isNotEmpty;
      case (FarmModule.production, 'saleable') || (FarmModule.production, 'damaged'):
        return valueOf('product') == 'Eggs' || valueOf(field).isNotEmpty;
      case (FarmModule.production, 'headCount'):
        return const {'Fish', 'Shrimp', 'Meat'}.contains(valueOf('product')) || valueOf(field).isNotEmpty;
      case (FarmModule.batches, 'closeDate'):
        return valueOf('status') != 'Active' || valueOf(field).isNotEmpty;
      case (FarmModule.sampling, 'waterTemp') || (FarmModule.sampling, 'ph') || (FarmModule.sampling, 'oxygen'):
        final batch = _farm.resolve(FarmModule.batches, valueOf('batch'));
        final species = _farm.species(batch?['species']);
        return species == null || '${species['category']}' == 'Fisheries & aquaculture' || valueOf(field).isNotEmpty;
      case (FarmModule.mortality, 'count'):
        return valueOf('batch').isNotEmpty;
      case (FarmModule.illness, 'tempUnit'):
        return valueOf('temperature').isNotEmpty || valueOf(field).isNotEmpty;
      case (FarmModule.illness, 'closure') || (FarmModule.illness, 'closedOn') || (FarmModule.illness, 'closureNotes') || (FarmModule.illness, 'reopenedCount'):
        return isEditing && valueOf(field).isNotEmpty && valueOf(field) != '0';
      case (FarmModule.illness, 'stage') || (FarmModule.illness, 'diagnosisStatus') || (FarmModule.illness, 'diagnosis'):
        return isEditing && valueOf(field).isNotEmpty;
      case (FarmModule.treatments, 'stockPerDose'):
        return valueOf('stockItem').isNotEmpty;
      case (FarmModule.treatments, 'outcomeNotes'):
        return valueOf('outcome') != FarmModule.treatmentOngoing || valueOf(field).isNotEmpty;
      case (FarmModule.medication, 'scheduledAt'):
        return valueOf('status') == FarmModule.medScheduled || valueOf(field).isNotEmpty;
      case (FarmModule.medication, 'givenAt') || (FarmModule.medication, 'administeredBy') || (FarmModule.medication, 'doseGiven'):
        return valueOf('status') == FarmModule.medGiven || valueOf('status') == FarmModule.medDelayed;
      case (FarmModule.medication, 'reason'):
        return const {FarmModule.medMissed, FarmModule.medDelayed, FarmModule.medDiscontinued}.contains(valueOf('status'));
      case (FarmModule.staff, 'wage'):
        return _auth.access.canSeeFinance;
      case (FarmModule.expenses, 'approval') || (FarmModule.purchases, 'approval'):
        return isEditing || _auth.access.canApprove;
      case (FarmModule.expenses, 'decisionNote') || (FarmModule.purchases, 'decisionNote') || (FarmModule.requests, 'decisionNote') || (FarmModule.managerReports, 'ownerComment'):
        return valueOf(field).isNotEmpty || (isEditing && _auth.access.canApprove);
      case (FarmModule.requests, 'status') || (FarmModule.requests, 'decidedBy') || (FarmModule.managerReports, 'status'):
        return isEditing;
      case (FarmModule.followUps, 'doneDate') || (FarmModule.followUps, 'progress') || (FarmModule.followUps, 'vetAssessment') || (FarmModule.followUps, 'nextAction'):
        return valueOf('status') == 'Done' || valueOf(field).isNotEmpty;
      default:
        return true;
    }
  }

  /// Dropdown choices for [field]. The current value is always included so
  /// older or imported records never lose their data when edited.
  List<String> optionsFor(String field) {
    final spec = specFor(field);
    bool active(FarmRecord r) => FarmController.isActive(r);
    final List<String> base = switch (spec.type) {
      FieldType.choice => module == FarmModule.inventoryTx && field == 'type' ? FarmModule.manualTxTypes : spec.options,
      FieldType.animal => _farm.list(FarmModule.animals).where((a) => active(a) && (field != 'dam' || '${a['sex']}'.toLowerCase() == 'female')).map((r) => r.reference).toList(),
      FieldType.customer => _farm.list(FarmModule.customers).where(active).map((r) => '${r['name']}').toList(),
      FieldType.semen => _farm.list(FarmModule.semen).map((r) => '${r['code']}').toList(),
      FieldType.feedItem => _farm.list(FarmModule.inventory).where((r) => '${r['category']}' == 'Feed').map((r) => '${r['name']}').toList(),
      FieldType.inventoryItem => _farm.list(FarmModule.inventory).map((r) => '${r['name']}').toList(),
      FieldType.species => _farm.list(FarmModule.species).where(active).where(_speciesFits).map((r) => '${r['name']}').toList(),
      FieldType.location => _farm.list(FarmModule.locations).where(active).map((r) => '${r['name']}').toList(),
      FieldType.batch => _farm.list(FarmModule.batches).where(active).map((r) => r.reference).toList(),
      FieldType.illness => _farm.list(FarmModule.illness).where((c) => HealthRules.acceptsEntries(c.data)).map((c) => '${c.id} · ${FarmRecord.displayName(c['animal'])}').toList(),
      FieldType.treatment => _farm.list(FarmModule.treatments).where(HealthRules.isActiveTreatment).map((t) => '${t.id} · ${t['medicine']} · ${FarmRecord.displayName(t['animal'])}').toList(),
      FieldType.staff => _farm.list(FarmModule.staff).where(active).map((r) => '${r['name']}').toList(),
      FieldType.multiChoice => spec.options,
      FieldType.sale =>
        _farm.list(FarmModule.sales).where((s) => s.number('due') > 0.005 || (existing != null && s.isReferencedBy(existing!['sale']))).map((s) => '${s.id} · ${s['customer']}').toList(),
      _ => const [],
    };
    final current = valueOf(field);
    return {if (current.isNotEmpty) current, ...base}.toList();
  }

  /// Animals use individually tracked species; batches use batch species.
  bool _speciesFits(FarmRecord s) {
    if (!FarmController.isLivestockSpecies(s)) return false;
    final tracking = '${s['tracking']}';
    if (module == FarmModule.animals) return tracking == FarmModule.trackIndividual;
    if (module == FarmModule.batches) return tracking == FarmModule.trackBatch;
    return true;
  }

  /// What the dropdown shows for [option] — adds stock, head-count and due details.
  String optionLabel(String field, String option) {
    switch (specFor(field).type) {
      case FieldType.semen:
        final s = _farm.semenByCode(option);
        return s == null ? option : '$option · ${FarmRecord.displayName(s['bull'])} · ${s['straws']} straws${s.status == 'Available' ? '' : ' · ${s.status}'}';
      case FieldType.feedItem:
      case FieldType.inventoryItem:
        final i = _farm.feedItem(option);
        return i == null ? option : '$option · ${i['qty']} ${i['unit']} in stock';
      case FieldType.batch:
        final b = _farm.resolve(FarmModule.batches, option);
        return b == null ? option : '$option · ${dates.formatQty(_farm.batchCount(option))} ${b['countUnit'] ?? ''}'.trim();
      case FieldType.illness:
        final c = _farm.resolve(FarmModule.illness, option);
        if (c == null) return option;
        final symptoms = '${c['symptoms']}';
        return '$option · ${c['severity']} · ${symptoms.length > 30 ? '${symptoms.substring(0, 30)}…' : symptoms}';
      case FieldType.sale:
        final s = _farm.resolve(FarmModule.sales, option);
        return s == null ? option : '$option · ${s['product']} · due ${dates.formatQty(s.number('due'))}';
      default:
        return option;
    }
  }

  void setValue(String field, String value) {
    textControllers[field]?.text = value;
    error = null;
    _fillDerived(field);
    notifyListeners();
  }

  /// Called when a text field changes, so calculated fields stay current.
  void touched(String field) {
    error = null;
    _fillDerived(field);
    notifyListeners();
  }

  void _set(String field, String value) {
    if (textControllers.containsKey(field) && textControllers[field]!.text != value) textControllers[field]!.text = value;
  }

  /// Keeps dependent fields in step while the form is filled in.
  void _fillDerived(String? changed) {
    double n(String f) => FarmRecord.leadingNumber(valueOf(f)) ?? 0;
    switch (module) {
      case FarmModule.breeding:
        if (changed == 'semen') {
          final semen = _farm.semenByCode(valueOf('semen'));
          if (semen != null) _set('bull', '${semen['bull']}');
        }
      case FarmModule.feedRecords:
        final item = _farm.feedItem(valueOf('feed'));
        if (changed == 'feed' && item != null) {
          _set('unit', '${item['unit']}');
          _set('unitPrice', dates.formatQty(item.number('unitCost')));
        }
        if (item != null) _set('category', '${'${item['feedType'] ?? ''}'.isNotEmpty ? item['feedType'] : item['category']}');
        final animal = _farm.resolve(FarmModule.animals, valueOf('animal'));
        final batch = _farm.resolve(FarmModule.batches, valueOf('batch'));
        _set('species', '${animal?['species'] ?? batch?['species'] ?? ''}');
        _set('totalCost', (n('qty') * n('unitPrice')).toStringAsFixed(2));
      case FarmModule.sales:
        if (changed == 'product') {
          final unit = FarmModule.defaultProductUnit[valueOf('product')];
          if (unit != null) _set('unit', unit);
        }
        final gross = n('qty') * n('unitPrice');
        final net = gross - n('discount') - n('deductions');
        final paid = n('paidAtSale') + (existing == null ? 0 : _farm.receivedFor(existing!) - existing!.number('paidAtSale'));
        _set('gross', gross.toStringAsFixed(2));
        _set('amount', net.toStringAsFixed(2));
        _set('paid', paid.toStringAsFixed(2));
        _set('due', (net - paid).toStringAsFixed(2));
        _set('status', net - paid <= 0.005 ? 'Paid' : (paid > 0 ? 'Partial' : 'Due'));
      case FarmModule.production:
      case FarmModule.productUsage:
        if (changed == 'product') {
          final unit = FarmModule.defaultProductUnit[valueOf('product')];
          if (unit != null) _set('unit', unit);
        }
      case FarmModule.collections:
        final sale = _farm.resolve(FarmModule.sales, valueOf('sale'));
        if (sale != null) {
          _set('customer', '${sale['customer']}');
          if (changed == 'sale' && valueOf('amount').isEmpty) _set('amount', dates.formatQty(sale.number('due')));
        }
      case FarmModule.batches:
        if (changed == 'species') {
          final s = _farm.species(valueOf('species'));
          if (s != null) _set('countUnit', '${s['countUnit']}');
        }
      case FarmModule.mortality:
        if (valueOf('animal').isNotEmpty) _set('count', '1');
      case FarmModule.managerReports:
        // Refresh the summary when the date or period changes, unless the
        // manager has already rewritten it.
        if ((changed == 'date' || changed == 'period') && (valueOf('summary').isEmpty || valueOf('summary') == _lastSummary)) {
          final date = FarmRecord.parseDate(valueOf('date')) ?? _clock();
          _set('summary', _summaryFor(valueOf('period'), date));
        }
    }
  }

  /// For a new milk entry: the date the chosen animal's withdrawal ends.
  DateTime? get withdrawalWarning {
    if (module != FarmModule.milkProduction) return null;
    final date = FarmRecord.parseDate(valueOf('date'));
    return date == null || valueOf('animal').isEmpty ? null : _farm.withdrawalEnd(valueOf('animal'), date);
  }

  /// For a new AI service: how well the chosen semen suits the chosen cow.
  /// (Not shown when editing, because the service is already in her history.)
  SemenSuitability? get semenCheck {
    if (module != FarmModule.breeding || existing != null || valueOf('method') == 'Natural mating') return null;
    final cow = _farm.resolve(FarmModule.animals, valueOf('animal'));
    final semen = _farm.semenByCode(valueOf('semen'));
    if (cow == null || semen == null) return null;
    return SemenAdvisor(_farm, today: _clock()).check(cow, semen);
  }

  /// Illness form: severity / danger-sign guidance (never a diagnosis).
  String? get illnessAdvice {
    if (module != FarmModule.illness) return null;
    final severity = valueOf('severity');
    final danger = valueOf('dangerSigns').isNotEmpty;
    if (severity.isEmpty && !danger) return null;
    return HealthRules.severityAdvice(severity, dangerSigns: danger);
  }

  bool get isEmergency => module == FarmModule.illness && (valueOf('severity') == 'Emergency' || valueOf('dangerSigns').isNotEmpty);

  /// Vet number to call from the form, if one is entered or set as default.
  String get vetPhone => valueOf('vetPhone').isNotEmpty ? valueOf('vetPhone') : _farm.profile.defaultVetPhone;

  /// Selected values of a multi-choice field.
  List<String> selectedOf(String field) => valueOf(field).split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  void toggleChoice(String field, String option, bool selected) {
    final current = selectedOf(field);
    if (selected && !current.contains(option)) current.add(option);
    if (!selected) current.remove(option);
    setValue(field, current.join('; '));
  }

  /// Helpful context under the form (stock left, head count, unsold stock).
  String? get contextHint {
    switch (module) {
      case FarmModule.feedRecords:
        final item = _farm.feedItem(valueOf('feed'));
        if (item == null || valueOf('source') != FarmModule.fromInventory) return null;
        return '${item['name']}: ${item['qty']} ${item['unit']} in stock.';
      case FarmModule.sales || FarmModule.productUsage:
        final product = valueOf('product');
        if (!FarmController.stockedProducts.contains(product)) return null;
        final stock = _farm.productStock(product, excludeId: existing?.id);
        return 'Unsold $product in stock: ${dates.formatQty(stock < 0 ? 0 : stock)} ${Units.baseOf(FarmModule.defaultProductUnit[product] ?? 'pcs')}.';
      case FarmModule.mortality || FarmModule.batchMovements:
        if (valueOf('batch').isEmpty) return null;
        return 'Head count now: ${dates.formatQty(_farm.batchCount(valueOf('batch'), excludeId: existing?.id))}.';
      case FarmModule.expenses:
        return 'Treatment costs entered on a health record and registered animal purchases are already counted — don’t enter them again here.';
      default:
        return null;
    }
  }

  String? validate(String field, String? value) {
    if (isReadOnly(field) || !isVisible(field)) return null;
    final spec = specFor(field);
    final v = value?.trim() ?? '';
    final label = labelFor(field).toLowerCase();

    final crossField = _crossFieldError(field, v);
    if (crossField != null) return crossField;

    if (v.isEmpty) return spec.required ? (_isPicker(spec) ? 'Please choose $label' : 'Please enter $label') : null;
    switch (spec.type) {
      case FieldType.number:
        final n = FarmRecord.leadingNumber(v);
        final rest = n == null ? '' : v.replaceFirst(RegExp(r'^\s*-?\d+(?:\.\d+)?'), '').trim();
        if (n == null || !RegExp(r'^[A-Za-z%.]*$').hasMatch(rest)) return 'Enter a number, e.g. 12.5';
        if (n < 0) return 'Cannot be negative';
      case FieldType.date:
        if (FarmRecord.parseDate(v) == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return 'Use the date picker (YYYY-MM-DD)';
      case FieldType.dateTime:
        final at = FarmRecord.parseDate(v);
        if (at == null || !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(v)) return 'Use the date and time picker';
        if (module != FarmModule.medication && at.isAfter(_clock().add(const Duration(minutes: 5)))) return 'Cannot be in the future';
      case FieldType.phone:
        if (!RegExp(r'^\+?[0-9 -]{6,16}$').hasMatch(v)) return 'Enter a valid phone number';
      default:
        break;
    }
    return _stockError(field, v);
  }

  String? _crossFieldError(String field, String v) {
    if (module == FarmModule.feedRecords && field == 'group' && v.isEmpty && valueOf('animal').isEmpty && valueOf('batch').isEmpty) {
      return 'Choose an animal or a group';
    }
    if (module == FarmModule.feedRecords && field == 'unit' && v.isNotEmpty && valueOf('source') == FarmModule.fromInventory) {
      final item = _farm.feedItem(valueOf('feed'));
      if (item != null && !Units.compatible(v, '${item['unit']}')) return '${item['name']} is stocked in ${item['unit']}';
    }
    if ((module == FarmModule.mortality || module == FarmModule.health) && field == 'animal' && v.isEmpty && valueOf('batch').isEmpty) {
      return module == FarmModule.mortality ? 'Choose the animal that died' : 'Choose the animal treated';
    }
    if (module == FarmModule.breeding && field == 'semen' && v.isEmpty && valueOf('method') != 'Natural mating') {
      return 'Choose the semen batch used for AI';
    }
    if (module == FarmModule.breeding && field == 'calvingDate' && v.isEmpty && valueOf('result') == FarmModule.resultCalved) {
      return 'Enter the calving date';
    }
    if (module == FarmModule.milkProduction && field == 'litres') {
      final n = FarmRecord.leadingNumber(v);
      if (n != null && n > 60) return 'More than 60 L in one shift — please check';
    }
    if (module == FarmModule.sales && field == 'animal' && v.isEmpty && valueOf('product') == 'Live animal') return 'Choose the animal sold';
    if (module == FarmModule.sales && field == 'paidAtSale') {
      final paid = FarmRecord.leadingNumber(v) ?? 0;
      final net = FarmRecord.leadingNumber(valueOf('amount')) ?? 0;
      if (paid > net + 0.005) return 'Cannot be more than the net sale';
    }
    if (module == FarmModule.production && field == 'damaged') {
      final total = FarmRecord.leadingNumber(valueOf('quantity')) ?? 0;
      final ok = (FarmRecord.leadingNumber(valueOf('saleable')) ?? 0) + (FarmRecord.leadingNumber(v) ?? 0);
      if (ok > total + 1e-9) return 'Saleable + damaged is more than the total';
    }
    return null;
  }

  /// Feed and semen are taken from stock, so they cannot exceed what is there.
  String? _stockError(String field, String v) {
    if (module == FarmModule.feedRecords && field == 'qty' && valueOf('source') == FarmModule.fromInventory) {
      final item = _farm.feedItem(valueOf('feed'));
      if (item == null) return null;
      var available = item.number('qty');
      if (existing != null && '${existing!['source']}' == FarmModule.fromInventory && '${existing!['feed']}'.toLowerCase() == valueOf('feed').toLowerCase()) {
        available += Units.convert(existing!.number('qty'), '${existing!['unit']}', '${item['unit']}') ?? 0;
      }
      final want = Units.convert(FarmRecord.leadingNumber(v) ?? 0, valueOf('unit').isEmpty ? '${item['unit']}' : valueOf('unit'), '${item['unit']}');
      if (want != null && want > available + 1e-9) return 'Only ${dates.formatQty(available)} ${item['unit']} of ${item['name']} in stock';
    }
    if (module == FarmModule.breeding && field == 'semen' && valueOf('method') != 'Natural mating') {
      final semen = _farm.semenByCode(v);
      if (semen == null) return null;
      final sameAsBefore = existing != null && '${existing!['semen']}'.toLowerCase() == v.toLowerCase();
      if (!sameAsBefore && semen.number('straws') <= 0) return 'No straws of $v left in stock';
      final expiry = semen.dateOf('expiry');
      final serviceDate = FarmRecord.parseDate(valueOf('date')) ?? _clock();
      if (!sameAsBefore && expiry != null && dates.dateOnly(expiry).isBefore(dates.dateOnly(serviceDate))) return '$v expired on ${semen['expiry']}';
    }
    return null;
  }

  bool _isPicker(FieldSpec spec) => !const {FieldType.text, FieldType.number, FieldType.phone}.contains(spec.type);

  /// Validates and saves. Returns true when the record was stored.
  Future<bool> save() async {
    error = null;
    if (!canEdit) {
      error = _noEditMessage;
      notifyListeners();
      return false;
    }
    if (!formKey.currentState!.validate()) {
      notifyListeners();
      return false;
    }
    saving = true;
    notifyListeners();
    final values = <String, dynamic>{
      for (final field in fields) field: isVisible(field) ? valueOf(field) : (field == 'count' ? valueOf(field) : ''),
    };
    try {
      if (existing != null) {
        // Keep internal bookkeeping fields (e.g. previous status) on edit.
        final internal = {
          for (final e in existing!.entries)
            if (FarmModule.isInternal(e.key)) e.key: e.value
        };
        await _farm.update(module, FarmRecord({...internal, ...values, 'id': existing!.id}));
      } else {
        await _farm.add(module, values);
      }
      return true;
    } on FarmRuleException catch (e) {
      error = e.message;
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final c in textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
