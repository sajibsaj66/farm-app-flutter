import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'farm_controller.dart';

/// The illness lifecycle, as pure rules:
///
/// Reported symptoms → veterinary assessment → treatment plan → treatment
/// monitoring → follow-up → recovery or continued care.
///
/// The stage is worked out from what has been recorded. Ending a case
/// (recovered, chronic care, referred, died) is never automatic — only an
/// explicit closure sets it. A passed treatment end date does not make an
/// animal recovered.
class HealthRules {
  HealthRules._();

  static List<FarmRecord> related(FarmController farm, String module, String illnessId) => farm.list(module).where((r) => FarmRecord.refId(r['illness']) == illnessId.toLowerCase()).toList();

  static String _s(Map<String, dynamic> m, String k) => '${m[k] ?? ''}'.trim();

  /// A case is open until it is closed. Chronic cases stay open for care.
  static bool isOpen(Map<String, dynamic> illness) {
    final c = _s(illness, 'closure');
    return c.isEmpty || c == FarmModule.closeChronic;
  }

  /// Whether new consultations, treatments, doses and follow-ups may be added.
  static bool acceptsEntries(Map<String, dynamic> illness) => isOpen(illness);

  static bool isActiveTreatment(FarmRecord t) {
    final o = '${t['outcome'] ?? ''}'.trim();
    return o.isEmpty || o == FarmModule.treatmentOngoing;
  }

  /// The case's current stage (also used as the animal's health status).
  static String stage(FarmController farm, Map<String, dynamic> illness) {
    final closure = _s(illness, 'closure');
    if (closure == FarmModule.closeRecovered) return FarmModule.healthRecovered;
    if (closure == FarmModule.closeChronic) return FarmModule.healthChronic;
    if (closure.isNotEmpty) return closure;
    final id = _s(illness, 'id');
    final treatments = related(farm, FarmModule.treatments, id);
    if (treatments.any(isActiveTreatment)) return FarmModule.healthTreatment;
    if (related(farm, FarmModule.followUps, id).any((f) => '${f['status']}' == 'Scheduled')) return FarmModule.healthFollowUp;
    // Assessed, treated or checked but not closed: someone must decide on
    // recovery.
    if (treatments.isNotEmpty || related(farm, FarmModule.consultations, id).isNotEmpty || related(farm, FarmModule.followUps, id).isNotEmpty) {
      return FarmModule.healthFollowUp;
    }
    return _s(illness, 'severity') == 'Low' ? FarmModule.healthSymptoms : FarmModule.healthAwaitingVet;
  }

  /// (status, diagnosis) from the most recent consultation that evaluated the
  /// animal. Never taken from the farmer's suspected cause.
  static (String, String) diagnosis(FarmController farm, String illnessId) {
    final evaluated = related(farm, FarmModule.consultations, illnessId).where((c) => '${c['diagnosisStatus']}' != FarmModule.diagNotEvaluated).toList()
      ..sort((a, b) => '${a['date']}${a['_createdAt'] ?? ''}'.compareTo('${b['date']}${b['_createdAt'] ?? ''}'));
    if (evaluated.isEmpty) return (FarmModule.diagNotEvaluated, '');
    final last = evaluated.last;
    return ('${last['diagnosisStatus']}', '${last['diagnosis'] ?? ''}');
  }

  /// Life-threatening signs, an Emergency severity, or a High severity case
  /// not yet seen by a vet.
  static bool isUrgent(FarmController farm, FarmRecord illness) {
    if (!isOpen(illness.data) || _s(illness.data, 'closure') == FarmModule.closeChronic) return false;
    if (_s(illness.data, 'severity') == 'Emergency' || _s(illness.data, 'dangerSigns').isNotEmpty) return true;
    return _s(illness.data, 'severity') == 'High' && related(farm, FarmModule.consultations, illness.id).isEmpty;
  }

  static const _priority = [FarmModule.healthAwaitingVet, FarmModule.healthTreatment, FarmModule.healthFollowUp, FarmModule.healthSymptoms, FarmModule.healthChronic];

  /// An animal's health status from its illness cases.
  static String animalStatus(FarmController farm, FarmRecord animal, {DateTime? today, int recoveredDays = 30}) {
    final cases = farm.list(FarmModule.illness).where((i) => animal.isReferencedBy(i['animal'])).toList();
    if (cases.isEmpty) return FarmModule.healthHealthy;
    final open = cases.where((c) => isOpen(c.data)).map((c) => stage(farm, c.data)).toSet();
    for (final p in _priority) {
      if (open.contains(p)) return p;
    }
    if (open.isNotEmpty) return FarmModule.healthOther;
    final latest = [...cases]..sort((a, b) => '${a['closedOn']}'.compareTo('${b['closedOn']}'));
    final last = latest.last;
    final closedOn = FarmRecord.parseDate(last['closedOn']);
    final day = dateOnly(today ?? farm.today);
    if ('${last['closure']}' == FarmModule.closeRecovered && closedOn != null && daysBetween(closedOn, day) <= recoveredDays) return FarmModule.healthRecovered;
    if ('${last['closure']}' == FarmModule.closeDied) return FarmModule.healthOther;
    return FarmModule.healthHealthy;
  }

  /// Danger-sign and severity guidance shown to the user. It never names a
  /// disease and never says the animal is fine.
  static String severityAdvice(String severity, {bool dangerSigns = false}) {
    if (dangerSigns || severity == 'Emergency') {
      return 'EMERGENCY: contact a veterinarian immediately. Keep the animal calm and separated. Do not wait to see if it improves.';
    }
    return switch (severity) {
      'High' => 'Prompt veterinary assessment is required. Contact a veterinarian today.',
      'Moderate' => 'The animal needs a timely veterinary assessment and a written follow-up plan.',
      'Low' => 'No urgent warning recorded. Keep watching the animal and ask a veterinarian if it does not improve or gets worse.',
      _ => 'Record what you see. The app does not diagnose illness.',
    };
  }
}
