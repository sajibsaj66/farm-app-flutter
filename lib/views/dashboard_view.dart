import 'package:flutter/material.dart';

import '../controllers/dashboard_controller.dart';
import 'manager_dashboard_view.dart';
import 'owner_dashboard_view.dart';

/// The home screen: the Owner dashboard (business performance) for a Farm
/// Owner, the Manager dashboard (today's operations) for a Farm Manager.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onOpenSection});

  /// Switches the shell to another section (e.g. when a card is tapped).
  final ValueChanged<String> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final c = DashboardController();
    return ListenableBuilder(
      listenable: Listenable.merge([c.farm, c.alerts]),
      builder: (context, _) {
        // A fresh controller per build so every figure reflects the latest save.
        final live = DashboardController(farm: c.farm, alerts: c.alerts);
        return live.isOwner ? OwnerDashboard(c: live, onOpenSection: onOpenSection) : ManagerDashboard(c: live, onOpenSection: onOpenSection);
      },
    );
  }
}
