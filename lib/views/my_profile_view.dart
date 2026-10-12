import 'package:flutter/material.dart';

import '../controllers/my_profile_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/access_policy.dart';
import '../models/user_role.dart';
import 'widgets/common_widgets.dart';

/// The signed-in user's profile: their account and role, how much of the
/// farm's data the role can see and change, and their own recent changes.
class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final controller = MyProfileController();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My profile')),
        body: ListenableBuilder(
          listenable: Listenable.merge([controller.farm, controller.auth]),
          builder: (context, _) {
            final user = controller.user;
            if (user == null) return const Center(child: Text('Not signed in'));
            final modules = controller.modules;
            final changes = controller.recentChanges();
            return ListView(padding: const EdgeInsets.all(18), children: [
              Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.brandSoft,
                      child: Text(user.initials, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        Text('@${user.username}${user.phone.isEmpty ? '' : ' · ${user.phone}'}', style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 6),
                        Chip(avatar: Icon(user.role.icon, size: 16, color: AppColors.brand), label: Text(user.role.label), visualDensity: VisualDensity.compact),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(user.role.description, style: const TextStyle(color: Colors.black54)),
              ),
              if (user.role == UserRole.manager)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    user.grants.isEmpty
                        ? 'The owner has not given you sales, purchase, expense or financial rights.'
                        : 'The owner also allows you to: ${ManagerGrant.values.where(user.grants.contains).map((g) => g.label.toLowerCase()).join(', ')}.',
                    style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _Stat(label: 'Data you can see', value: '${modules.length} sections'),
                _Stat(label: 'Records you can see', value: '${controller.visibleRecords}'),
                _Stat(label: 'Sections you can change', value: '${controller.editableModules}'),
              ]),
              const SizedBox(height: 18),
              const SectionTitle('Your recent changes'),
              const SizedBox(height: 6),
              if (changes.isEmpty) const EmptyHint('You have not changed anything yet.'),
              for (final a in changes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, color: AppColors.brand, size: 20),
                  title: Text(a.title),
                  subtitle: Text(a.displayTime),
                ),
            ]);
          },
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 100),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        ]),
      );
}
