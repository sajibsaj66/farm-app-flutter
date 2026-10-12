import '../models/activity_entry.dart';
import '../models/app_user.dart';
import '../models/farm_module.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';

/// One module as the signed-in user sees it on their profile.
class ModuleAccess {
  const ModuleAccess({required this.module, required this.records, required this.canEdit, required this.canDelete, required this.label});

  final String module;
  final int records;
  final bool canEdit;
  final bool canDelete;

  /// "View only", "View, add & edit"…
  final String label;
}

/// The signed-in user's profile: who they are, which farm data their role
/// lets them see and change, and their own recent changes.
///
/// Everything is read live from [FarmController] and [AuthController], so a
/// change made anywhere in the app shows here straight away.
class MyProfileController {
  MyProfileController({FarmController? farm, AuthController? auth})
      : farm = farm ?? FarmController.instance,
        auth = auth ?? AuthController.instance;

  final FarmController farm;
  final AuthController auth;

  AppUser? get user => auth.currentUser;

  /// Modules this user may open, with how many records each holds.
  List<ModuleAccess> get modules {
    final access = auth.access;
    if (!access.isSignedIn) return const [];
    return [
      for (final m in FarmModule.all)
        if (access.canOpenModule(m.name))
          ModuleAccess(
            module: m.name,
            records: farm.count(m.name),
            canEdit: access.canEditModule(m.name),
            canDelete: access.canEditModule(m.name) && access.canDelete,
            label: access.accessLabel(m.name),
          ),
    ];
  }

  /// Sections of the system this user does not see (e.g. money records for a
  /// manager without those rights).
  List<String> get hiddenModules {
    final access = auth.access;
    if (!access.isSignedIn) return const [];
    return [
      for (final m in FarmModule.all)
        if (!FarmModule.outOfScope.contains(m.name) && !access.canOpenModule(m.name)) m.name
    ];
  }

  int get visibleRecords => modules.fold(0, (s, m) => s + m.records);

  int get editableModules => modules.where((m) => m.canEdit).length;

  /// Changes this user made, newest first (from the activity log).
  List<ActivityEntry> recentChanges({int limit = 8}) {
    final name = user?.name;
    if (name == null) return const [];
    return farm.activity.where((a) => a.by == name).take(limit).toList();
  }
}
