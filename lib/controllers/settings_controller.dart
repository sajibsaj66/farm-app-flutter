import '../models/app_user.dart';
import '../models/farm_profile.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';

class SettingsController {
  SettingsController({FarmController? farm, AuthController? auth})
      : farm = farm ?? FarmController.instance,
        auth = auth ?? AuthController.instance;

  final FarmController farm;
  final AuthController auth;

  static const appName = 'DeshIT-BD Farm Management';
  static const appVersion = '1.0.0';

  AppUser? get user => auth.currentUser;

  FarmProfile get profile => farm.profile;

  bool get canEditFarmProfile => auth.access.canManageSettings;
  bool get canManageUsers => auth.access.canManageUsers;
  bool get canBackup => auth.access.canBackup;
  bool get canViewActivityLog => auth.access.canViewActivityLog;
  bool get canResetData => auth.access.canResetData;
  bool get canEditCalculations => auth.access.canManageSettings;

  int get userCount => auth.users.length;

  Future<void> resetDemoData() {
    if (!canResetData) throw StateError('Only the farm owner can reset data');
    return farm.reset();
  }

  Future<void> logout() => auth.logout();
}
