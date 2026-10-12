import 'package:flutter/foundation.dart';

import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'herd_analytics.dart';

/// State for one animal's profile screen: the selected period and the
/// actions that can be started from it.
class CowProfileController extends ChangeNotifier {
  CowProfileController(this.animalId, {FarmController? farm, AuthController? auth, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _clock = clock;

  /// Period choices in days; null means all time.
  static const periods = <int?>[7, 30, 90, null];

  final String animalId;
  final FarmController farm;
  final AuthController _auth;
  final DateTime Function()? _clock;

  int? periodDays = 30;

  DateTime get today => dateOnly(_clock?.call() ?? farm.today);

  FarmRecord? get animal => farm.find(FarmModule.animals, animalId);

  CowAnalytics? get analytics {
    final a = animal;
    return a == null ? null : CowAnalytics(farm, a, today: today);
  }

  SemenAdvisor get advisor => SemenAdvisor(farm, today: today);

  bool canOpen(String module) => _auth.access.canOpenModule(module);

  bool get canSeeFinance => _auth.access.canSeeFinance;

  bool get canRecordCalving => canOpen(FarmModule.breeding) && canOpen(FarmModule.animals);

  String periodLabel(int? days) => days == null ? 'All time' : '$days days';

  void setPeriod(int? days) {
    periodDays = days;
    notifyListeners();
  }

  /// The service a calving belongs to: the confirmed pregnancy, otherwise the
  /// latest service since the last calving.
  FarmRecord? get calvingService {
    final a = analytics;
    if (a == null) return null;
    return a.currentPregnancy ?? (a.currentCycleServices.isEmpty ? null : a.currentCycleServices.last);
  }

  /// Registers a calving: adds the calf (linked to this cow as dam and to the
  /// service bull as sire), records its birth weight, marks the service as
  /// calved and moves the cow into the milking group. Returns an error
  /// message, or null on success.
  Future<String?> recordCalving({required DateTime date, required String calfName, required String sex, String tag = '', double? birthWeight}) async {
    final cow = animal;
    if (cow == null) return 'This animal no longer exists.';
    if (!canRecordCalving) return 'Your role cannot record calvings.';
    if (calfName.trim().isEmpty) return 'Please enter the calf’s name.';
    if (date.isAfter(today)) return 'The calving date cannot be in the future.';
    if (birthWeight != null && (birthWeight <= 0 || birthWeight > 120)) return 'Birth weight should be between 1 and 120 kg.';

    final service = calvingService;
    final semen = farm.semenByCode(service?['semen']);
    final cowBreed = '${cow['breed'] ?? ''}'.trim();
    final bullBreed = '${semen?['breed'] ?? ''}'.trim();
    final breed = bullBreed.isEmpty || bullBreed == cowBreed ? cowBreed : '$cowBreed × $bullBreed';
    final day = formatDate(date);

    final calf = await farm.add(
      FarmModule.animals,
      {
        'name': calfName.trim(),
        'tag': tag.trim(),
        'type': 'Calf',
        'breed': breed,
        'sex': sex,
        'dob': day,
        'group': 'Calves',
        'weight': birthWeight == null ? '' : formatQty(birthWeight),
        'status': 'Active',
        'location': 'Calf pen',
        'sire': '${service?['bull'] ?? ''}',
        'dam': cow.reference,
        'source': 'Born on farm',
        'purchasePrice': '',
      },
      activity: 'Calf ${calfName.trim()} born to ${cow['name']}',
    );
    if (birthWeight != null) {
      await farm.add(FarmModule.weights, {'date': day, 'animal': calf.reference, 'weight': formatQty(birthWeight), 'bcs': ''}, activity: 'Birth weight recorded for ${calfName.trim()}');
    }
    if (service != null) {
      await farm.update(FarmModule.breeding, FarmRecord({...service.toJson(), 'result': FarmModule.resultCalved, 'calvingDate': day}), activity: '${cow['name']} calved · ${service.id}');
    }
    final latest = farm.find(FarmModule.animals, cow.id) ?? cow;
    await farm.update(
      FarmModule.animals,
      FarmRecord({...latest.toJson(), 'status': 'Active', 'group': 'Lactating cows'}),
      activity: '${cow['name']} moved to Lactating cows after calving',
    );
    return null;
  }
}
