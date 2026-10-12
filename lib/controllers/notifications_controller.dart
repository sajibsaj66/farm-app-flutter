import '../models/activity_entry.dart';
import '../models/alert_item.dart';
import 'alerts_controller.dart';
import 'farm_controller.dart';

class NotificationsController {
  NotificationsController({FarmController? farm, AlertsController? alerts})
      : farm = farm ?? FarmController.instance,
        alerts = alerts ?? AlertsController.instance;

  final FarmController farm;
  final AlertsController alerts;

  List<AlertItem> get reminders => alerts.active;

  int get readCount => alerts.dismissedCount;

  Iterable<ActivityEntry> get recentActivity => farm.activity.take(10);

  Future<void> markRead(AlertItem alert) => alerts.dismiss(alert.id);

  Future<void> markAllRead() async {
    for (final a in reminders) {
      await alerts.dismiss(a.id);
    }
  }

  Future<void> showReadAgain() => alerts.restoreDismissed();
}
