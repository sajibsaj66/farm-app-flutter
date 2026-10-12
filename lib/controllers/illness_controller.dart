import 'package:flutter/material.dart';

import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_profile.dart';
import '../models/farm_record.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'health_analytics.dart';
import 'health_rules.dart';

/// One illness case: its full history and the actions that move it through
/// the lifecycle. Recovery is never automatic — it is recorded here, by an
/// owner or manager, with notes and an explicit confirmation.
class IllnessController extends ChangeNotifier {
  IllnessController(this.illnessId, {FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock;

  final String illnessId;
  final FarmController farm;
  final AuthController _auth;
  final DateTime Function()? _clock;

  DateTime get today => dateOnly(_clock?.call() ?? farm.today);

  FarmRecord? get illness => farm.find(FarmModule.illness, illnessId);

  FarmRecord? get animal => farm.resolve(FarmModule.animals, illness?['animal']);

  /// How other records refer to this case.
  String get reference => '$illnessId · ${FarmRecord.displayName(illness?['animal'])}';

  List<FarmRecord> _rel(String module, {String field = 'date'}) =>
      HealthRules.related(farm, module, illnessId)..sort((a, b) => '${b[field]}${b['_createdAt'] ?? ''}'.compareTo('${a[field]}${a['_createdAt'] ?? ''}'));

  List<FarmRecord> get consultations => _rel(FarmModule.consultations);
  List<FarmRecord> get treatments => _rel(FarmModule.treatments, field: 'startDate');
  List<FarmRecord> get followUps => _rel(FarmModule.followUps, field: 'dueDate');

  List<FarmRecord> doses(FarmRecord treatment) => farm.list(FarmModule.medication).where((m) => treatment.isReferencedBy(m['treatment'])).toList()
    ..sort((a, b) => '${b['givenAt']}${b['scheduledAt']}'.compareTo('${a['givenAt']}${a['scheduledAt']}'));

  bool get isOpen => illness != null && HealthRules.isOpen(illness!.data);

  bool get isUrgent => illness != null && HealthRules.isUrgent(farm, illness!);

  bool get canClose => _auth.access.canCloseIllness;

  bool canOpen(String module) => _auth.access.canOpenModule(module);

  String get advice => HealthRules.severityAdvice('${illness?['severity']}', dangerSigns: '${illness?['dangerSigns'] ?? ''}'.isNotEmpty);

  /// The best phone number to call: on the case, the latest consultation, or
  /// the farm's default vet.
  String get vetPhone {
    final fromCase = '${illness?['vetPhone'] ?? ''}'.trim();
    if (fromCase.isNotEmpty) return fromCase;
    for (final c in consultations) {
      final p = '${c['vetPhone'] ?? ''}'.trim();
      if (p.isNotEmpty) return p;
    }
    return farm.profile.defaultVetPhone;
  }

  List<ProductionReview> get productionChanges => illness == null ? const [] : HealthAnalytics(farm, today: today).reviewAround(illness!);

  /// Lifecycle steps and whether each has been reached.
  List<(String, bool)> get lifecycle {
    final i = illness;
    if (i == null) return const [];
    final closed = '${i['closure'] ?? ''}'.isNotEmpty;
    return [
      ('Symptoms reported', true),
      ('Veterinary assessment', consultations.isNotEmpty),
      ('Treatment plan', treatments.isNotEmpty),
      ('Treatment monitoring', farm.list(FarmModule.medication).any((m) => FarmRecord.refId(m['illness']) == illnessId.toLowerCase())),
      ('Follow-up', followUps.any((f) => '${f['status']}' == 'Done')),
      (closed ? '${i['closure']}' : 'Recovery or continued care', closed),
    ];
  }

  /// Why the case cannot be closed as [outcome] yet (empty when it can).
  List<String> blockers(String outcome) {
    if (outcome == FarmModule.closeChronic || outcome == FarmModule.closeDied) return const [];
    return [
      for (final t in treatments.where(HealthRules.isActiveTreatment))
        'Treatment ${t.id} (${t['medicine']}) is still ongoing — record its status (completed, or stopped on the vet’s instruction) first.',
      for (final f in followUps.where((f) => '${f['status']}' == 'Scheduled')) 'Follow-up ${f.id} on ${f['dueDate']} is still scheduled — record it as done, missed or cancelled first.',
    ];
  }

  /// Ends the case. Returns an error message, or null when saved.
  Future<String?> close({required String outcome, required DateTime date, required String notes, required bool confirmed}) async {
    final i = illness;
    if (i == null) return 'This illness case no longer exists.';
    if (!canClose) return 'Only the Farm Owner or Farm Manager can record the outcome of an illness.';
    if (!FarmModule.closures.contains(outcome)) return 'Choose an outcome.';
    if (!isOpen && '${i['closure']}' != FarmModule.closeChronic) return 'This case is already closed.';
    if (!confirmed) return 'Confirm that this is based on the animal’s condition and veterinary guidance.';
    if (notes.trim().length < 3) return 'Add notes describing the animal’s condition.';
    final noticed = i.dateOf('noticedAt');
    if (dateOnly(date).isAfter(today)) return 'The date cannot be in the future.';
    if (noticed != null && dateOnly(date).isBefore(dateOnly(noticed))) return 'The date is before the symptoms were noticed.';
    final b = blockers(outcome);
    if (b.isNotEmpty) return b.first;
    try {
      await farm.update(
        FarmModule.illness,
        FarmRecord({...i.toJson(), 'closure': outcome, 'closedOn': formatDate(date), 'closureNotes': notes.trim()}),
        activity: 'Illness ${i.id} (${FarmRecord.displayName(i['animal'])}) closed: $outcome',
      );
      return null;
    } on FarmRuleException catch (e) {
      return e.message;
    }
  }

  /// Reopens a closed case when symptoms come back. The previous outcome is
  /// kept in the case notes, so no history is lost.
  Future<String?> reopen(String reason) async {
    final i = illness;
    if (i == null) return 'This illness case no longer exists.';
    if ('${i['closure'] ?? ''}'.isEmpty) return 'This case is already open.';
    if (reason.trim().length < 3) return 'Describe why the case is being reopened (e.g. symptoms returned).';
    final history = 'Reopened ${formatDate(today)}: ${reason.trim()}. Previous outcome: ${i['closure']} on ${i['closedOn']}${'${i['closureNotes'] ?? ''}'.isEmpty ? '' : ' — ${i['closureNotes']}'}.';
    final notes = '${i['notes'] ?? ''}'.trim();
    final count = (FarmRecord.leadingNumber(i['reopenedCount']) ?? 0) + 1;
    try {
      await farm.update(
        FarmModule.illness,
        FarmRecord({...i.toJson(), 'closure': '', 'closedOn': '', 'closureNotes': '', 'reopenedCount': formatQty(count), 'notes': notes.isEmpty ? history : '$notes\n$history'}),
        activity: 'Illness ${i.id} reopened',
      );
      return null;
    } on FarmRuleException catch (e) {
      return e.message;
    }
  }

  void refresh() => notifyListeners();
}

/// Health dashboard filters.
class HealthDashboardController extends ChangeNotifier {
  HealthDashboardController({FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock;

  final FarmController farm;
  final AuthController _auth;
  final DateTime Function()? _clock;

  HealthFilter filter = const HealthFilter();

  HealthAnalytics get analytics => HealthAnalytics(farm, today: _clock?.call() ?? farm.today);

  bool canOpen(String module) => _auth.access.canOpenModule(module);

  List<String> _distinct(String field) => {for (final a in farm.list(FarmModule.animals)) '${a[field] ?? ''}'.trim()}.where((s) => s.isNotEmpty).toList()..sort();

  List<String> get speciesOptions => _distinct('species');
  List<String> get breedOptions => _distinct('breed');
  List<String> get groupOptions => _distinct('group');
  List<String> get vetOptions => analytics.allVets.toList()..sort();

  void update(HealthFilter f) {
    filter = f;
    notifyListeners();
  }

  void clear() => update(const HealthFilter());

  bool get hasFilters =>
      filter.query.isNotEmpty ||
      filter.species != null ||
      filter.breed != null ||
      filter.group != null ||
      filter.status != null ||
      filter.from != null ||
      filter.to != null ||
      filter.treatment != null ||
      filter.vet != null;
}

/// Health settings (owner): thresholds, reminder timing and default vet.
class HealthSettingsController extends ChangeNotifier {
  HealthSettingsController({FarmController? farm}) : _farm = farm ?? FarmController.instance {
    final p = _farm.profile;
    milk.text = formatQty(p.lowMilkPercent);
    feed.text = formatQty(p.lowFeedPercent);
    recent.text = '${p.healthRecentDays}';
    baseline.text = '${p.healthBaselineDays}';
    lead.text = '${p.reminderLeadDays}';
    recovered.text = '${p.recoveredShowDays}';
    vetName.text = p.defaultVetName;
    vetPhone.text = p.defaultVetPhone;
  }

  final FarmController _farm;
  final formKey = GlobalKey<FormState>();
  final milk = TextEditingController();
  final feed = TextEditingController();
  final recent = TextEditingController();
  final baseline = TextEditingController();
  final lead = TextEditingController();
  final recovered = TextEditingController();
  final vetName = TextEditingController();
  final vetPhone = TextEditingController();
  bool busy = false;

  static String? _range(String? v, double min, double max, String what) {
    final n = double.tryParse(v?.trim() ?? '');
    return n == null || n < min || n > max ? 'Enter $what between ${formatQty(min)} and ${formatQty(max)}' : null;
  }

  String? validatePercent(String? v) => _range(v, 1, 100, 'a percentage');
  String? validateDays(String? v) => _range(v, 1, 90, 'days') ?? (int.tryParse(v!.trim()) == null ? 'Enter whole days' : null);
  String? validateLead(String? v) => _range(v, 0, 30, 'days') ?? (int.tryParse(v!.trim()) == null ? 'Enter whole days' : null);
  String? validatePhone(String? v) => (v == null || v.trim().isEmpty || RegExp(r'^\+?[0-9 -]{6,16}$').hasMatch(v.trim())) ? null : 'Enter a valid phone number';

  Future<bool> save() async {
    if (busy || !formKey.currentState!.validate()) return false;
    busy = true;
    notifyListeners();
    final FarmProfile p = _farm.profile;
    await _farm.updateProfile(p.copyWith(
      lowMilkPercent: double.parse(milk.text.trim()),
      lowFeedPercent: double.parse(feed.text.trim()),
      healthRecentDays: int.parse(recent.text.trim()),
      healthBaselineDays: int.parse(baseline.text.trim()),
      reminderLeadDays: int.parse(lead.text.trim()),
      recoveredShowDays: int.parse(recovered.text.trim()),
      defaultVetName: vetName.text.trim(),
      defaultVetPhone: vetPhone.text.trim(),
    ));
    busy = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    for (final c in [milk, feed, recent, baseline, lead, recovered, vetName, vetPhone]) {
      c.dispose();
    }
    super.dispose();
  }
}
