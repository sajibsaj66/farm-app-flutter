import 'package:flutter/material.dart';

import '../controllers/settings_controller.dart';
import '../core/company.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/ui_feedback.dart';
import 'account_views.dart';
import 'my_profile_view.dart';
import 'widgets/company_card.dart';
import 'users_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dialogs.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SettingsController();
    return ListenableBuilder(
      listenable: Listenable.merge([c.farm, c.auth]),
      builder: (context, _) {
        final user = c.user;
        final profile = c.profile;
        return ListView(padding: const EdgeInsets.all(18), children: [
          const PageHeading(title: 'Settings', subtitle: 'Your account, farm profile and data tools.'),
          const SizedBox(height: 18),
          if (user != null)
            Card(
              color: Colors.white,
              elevation: 0,
              child: ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.brandSoft, child: Text(user.initials, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.bold))),
                title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${user.role.label} · @${user.username} · My profile & data access'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _push(context, const MyProfilePage()),
              ),
            ),
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.brandSoft, child: Icon(Icons.agriculture, color: AppColors.brand)),
              title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([profile.location, profile.phone].where((s) => s.isNotEmpty).join(' · ').ifEmpty('Farm profile')),
              trailing: c.canEditFarmProfile ? const Icon(Icons.edit_outlined) : null,
              onTap: c.canEditFarmProfile ? () => _push(context, const FarmProfilePage()) : null,
            ),
          ),
          const SizedBox(height: 10),
          _group('Account', [
            _tile(Icons.password_outlined, 'Change password', 'Update the password you sign in with', () => _push(context, const ChangePasswordPage())),
          ]),
          if (c.canManageUsers || c.canEditFarmProfile || c.canViewActivityLog)
            _group('Farm management', [
              if (c.canManageUsers) _tile(Icons.group_outlined, 'Users & roles', '${c.userCount} accounts · add staff, change roles, reset passwords', () => _push(context, const UsersPage())),
              if (c.canEditFarmProfile) _tile(Icons.storefront_outlined, 'Farm profile', 'Name, location, contact number and currency', () => _push(context, const FarmProfilePage())),
              if (c.canEditCalculations)
                _tile(Icons.health_and_safety_outlined, 'Health settings', 'Production review levels, reminder timing and default veterinarian', () => _push(context, const HealthSettingsPage())),
              if (c.canEditCalculations)
                _tile(Icons.calculate_outlined, 'Calculation settings', 'Feed cost basis, animal asset cost, depreciation and alert thresholds', () => _push(context, const CalculationSettingsPage())),
              if (c.canViewActivityLog) _tile(Icons.manage_search_outlined, 'Activity log', 'Who added, changed or deleted what, and when', () => _push(context, const ActivityLogPage())),
            ]),
          if (c.canBackup || c.canResetData)
            _group('Data', [
              if (c.canBackup) _tile(Icons.backup_outlined, 'Backup & restore', 'Copy all farm data, or restore it from a backup', () => _push(context, const BackupPage())),
              if (c.canResetData) _tile(Icons.restart_alt, 'Reset demo data', 'Load the demo farm (your data is backed up first)', () => _confirmReset(context, c)),
            ]),
          _group('About', const [
            ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('Storage'),
                subtitle: Text('All data is saved on this device only. Use Backup & restore to keep a copy or move it to another phone.')),
            ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('Online sync'), subtitle: Text('Not available — no cloud backup, multi-device or multi-farm sync.')),
            ListTile(leading: Icon(Icons.notifications_none), title: Text('Reminders'), subtitle: Text('Shown inside the app only; no SMS, email or phone notifications are sent.')),
          ]),
          Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text('Contact'.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.black54))),
          const CompanyCard(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: SettingsController.appName,
              applicationVersion: SettingsController.appVersion,
              children: const [
                Text('Livestock and cattle farm management for Farm Owners and Farm Managers: dairy, rearing, fattening and mixed livestock.'),
                SizedBox(height: 8),
                Text('By ${Company.name} · ${Company.websiteLabel} · ${Company.phone} · ${Company.email}'),
                SizedBox(height: 8),
                Text('Data is stored on this device only. No backend or online service is connected.'),
              ],
            ),
            icon: const Icon(Icons.info_outline),
            label: const Text('About this app'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => confirmSignOut(context), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ]);
      },
    );
  }

  static void _push(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Widget _group(String title, List<Widget> tiles) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.black54))),
          Card(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, t) in tiles.indexed) ...[if (i > 0) const Divider(height: 1), t],
            ]),
          ),
        ]),
      );

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppColors.brand),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  Future<void> _confirmReset(BuildContext context, SettingsController c) async {
    final ok = await confirmDialog(
      context,
      title: 'Reset all demo data?',
      message:
          'All records are replaced with the fictional demo farm. Your current data is saved first as an automatic backup — restore it any time from Backup & restore. User accounts and the farm profile are kept.',
      confirmLabel: 'Reset data',
    );
    if (!ok) return;
    await c.resetDemoData();
    if (context.mounted) showToast(context, 'Demo data reset');
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
