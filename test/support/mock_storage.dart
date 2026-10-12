import 'package:shared_preferences/shared_preferences.dart';
import 'package:technovate_farm_management/services/local_storage_service.dart';

/// Starts a test with an empty in-memory Hive box. [legacy] is what an older
/// install had saved in SharedPreferences; it is copied into Hive on the next
/// `init()`, exactly like a real upgrade.
Future<void> mockStorage(Map<String, Object> legacy) async {
  SharedPreferences.setMockInitialValues(legacy);
  await LocalStorageService.instance.debugResetForTests();
}

/// The storage the app uses, opened (for reading back what was saved).
Future<LocalStorageService> openStorage() async {
  await LocalStorageService.instance.init();
  return LocalStorageService.instance;
}
