import 'package:flutter/material.dart';

import 'farm_module.dart';

enum SectionKind { overview, health, approvals, records, reports, notifications, settings }

/// One destination in the app's navigation.
class AppSection {
  const AppSection(this.label, this.icon, this.selectedIcon, this.kind, {String? shortLabel, this.group = ''}) : shortLabel = shortLabel ?? label;

  final String label;

  /// Label for the compact bottom navigation bar.
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;
  final SectionKind kind;

  /// Heading the section is listed under in the "More" menu.
  final String group;

  /// The Animal Health dashboard section.
  static const healthDashboard = 'Animal Health';

  /// The owner's decision queue (and a manager's view of it).
  static const approvals = 'Approvals';

  static const _shortLabels = {
    FarmModule.illness: 'Illness',
    FarmModule.followUps: 'Follow-ups',
    FarmModule.milkProduction: 'Milk',
    FarmModule.health: 'Health',
    FarmModule.feedRecords: 'Feed',
    FarmModule.semen: 'Semen',
    FarmModule.weights: 'Weight',
    FarmModule.production: 'Production',
    FarmModule.species: 'Species',
    FarmModule.locations: 'Locations',
    FarmModule.tasks: 'Tasks',
    FarmModule.managerReports: 'Reports to owner',
    FarmModule.requests: 'Requests',
  };

  /// Navigation order. Livestock only: the poultry/fish/bee batch modules
  /// ([FarmModule.outOfScope]) are not listed.
  static const groups = <(String, List<String>)>[
    ('Livestock', [FarmModule.animals, FarmModule.breeding, FarmModule.semen, FarmModule.weights, FarmModule.mortality]),
    ('Feed & stock', [FarmModule.feedRecords, FarmModule.inventory, FarmModule.inventoryTx]),
    ('Milk & production', [FarmModule.milkProduction, FarmModule.production, FarmModule.productUsage]),
    ('Health', [FarmModule.illness, FarmModule.consultations, FarmModule.treatments, FarmModule.medication, FarmModule.followUps, FarmModule.health]),
    ('Sales & money', [FarmModule.sales, FarmModule.collections, FarmModule.customers, FarmModule.purchases, FarmModule.expenses]),
    ('Team & approvals', [FarmModule.tasks, FarmModule.managerReports, FarmModule.requests, FarmModule.staff]),
    ('Farm setup', [FarmModule.species, FarmModule.locations]),
  ];

  static final all = <AppSection>[
    const AppSection('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard, SectionKind.overview, shortLabel: 'Home'),
    for (final (group, modules) in groups) ...[
      if (group == 'Health') const AppSection(healthDashboard, Icons.health_and_safety_outlined, Icons.health_and_safety, SectionKind.health, shortLabel: 'Health', group: 'Health'),
      if (group == 'Team & approvals') const AppSection(approvals, Icons.fact_check_outlined, Icons.fact_check, SectionKind.approvals, group: 'Team & approvals'),
      for (final name in modules) AppSection(name, FarmModule.byName(name)!.navIcon, FarmModule.byName(name)!.recordIcon, SectionKind.records, shortLabel: _shortLabels[name], group: group),
    ],
    const AppSection('Reports', Icons.query_stats_outlined, Icons.query_stats, SectionKind.reports, group: 'Reports & settings'),
    const AppSection('Notifications', Icons.notifications_none, Icons.notifications, SectionKind.notifications, group: 'Reports & settings'),
    const AppSection('Settings', Icons.settings_outlined, Icons.settings, SectionKind.settings, group: 'Reports & settings'),
  ];
}
