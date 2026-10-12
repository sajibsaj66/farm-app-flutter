import 'package:flutter/material.dart';

import '../controllers/alerts_controller.dart';
import '../controllers/farm_controller.dart';
import '../controllers/navigation_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/app_section.dart';
import '../models/app_user.dart';
import 'approvals_view.dart';
import 'dashboard_view.dart';
import 'health_dashboard_view.dart';
import 'notifications_view.dart';
import 'my_profile_view.dart';
import 'records_view.dart';
import 'reports_view.dart';
import 'settings_view.dart';
import 'widgets/dialogs.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user});

  final AppUser user;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final nav = NavigationController(widget.user.access);
  final farm = FarmController.instance;
  final alerts = AlertsController.instance;

  @override
  void dispose() {
    nav.dispose();
    super.dispose();
  }

  Widget _pageFor(AppSection section) => switch (section.kind) {
        SectionKind.overview => DashboardPage(onOpenSection: nav.openSection),
        SectionKind.health => HealthDashboardPage(onOpenSection: nav.openSection),
        SectionKind.reports => const ReportsPage(),
        SectionKind.notifications => NotificationsPage(onOpenSection: nav.openSection),
        SectionKind.settings => const SettingsPage(),
        SectionKind.approvals => const ApprovalsPage(),
        SectionKind.records => RecordsPage(module: section.label),
      };

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;
    return ListenableBuilder(
      listenable: Listenable.merge([nav, farm, alerts]),
      builder: (context, _) {
        final page = _pageFor(nav.current);
        final unread = alerts.activeCount;
        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.agriculture, color: Colors.white, size: 21)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('DeshIT-BD', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('${farm.profile.name} · ${widget.user.role.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
                onPressed: nav.openNotifications,
                icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none)),
              ),
              Padding(padding: const EdgeInsets.only(right: 10), child: _AccountMenu(user: widget.user)),
            ],
          ),
          body: isWide
              ? Row(children: [
                  // Scrolls when there are more destinations than fit vertically.
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: nav.selectedIndex,
                            onDestinationSelected: nav.select,
                            labelType: NavigationRailLabelType.all,
                            destinations: nav.sections.map((s) => NavigationRailDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label, maxLines: 1))).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ])
              : page,
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: nav.bottomNavIndex,
                  onDestinationSelected: (v) => nav.isMoreTab(v) ? _showMore(context) : nav.selectTab(v),
                  destinations: [
                    ...nav.bottomTabs.map((s) => NavigationDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: s.shortLabel)),
                    const NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
                  ],
                ),
        );
      },
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (group, items) in nav.grouped) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Text(group.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.black54)),
                ),
                for (final (i, s) in items)
                  ListTile(
                    dense: true,
                    leading: Icon(i == nav.selectedIndex ? s.selectedIcon : s.icon, color: i == nav.selectedIndex ? AppColors.brand : null),
                    title: Text(s.label),
                    selected: i == nav.selectedIndex,
                    onTap: () {
                      Navigator.pop(ctx);
                      nav.select(i);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar in the app bar: shows who is signed in and offers sign out.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Account',
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == 'logout') confirmSignOut(context);
          if (value == 'profile') Navigator.push(context, MaterialPageRoute(builder: (_) => const MyProfilePage()));
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(user.role.icon, color: AppColors.brand),
              title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              subtitle: Text(user.role.label),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'profile', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.badge_outlined), title: Text('My profile'))),
          const PopupMenuItem<String>(value: 'logout', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout), title: Text('Sign out'))),
        ],
        child: CircleAvatar(
          backgroundColor: AppColors.brandSoft,
          child: Text(user.initials, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.bold)),
        ),
      );
}
