import 'package:flutter/material.dart';

/// The two kinds of farm user. What each may see and do is decided by
/// [AccessPolicy] (the Farm Owner can give individual managers extra rights).
enum UserRole {
  owner(
    'Farm Owner',
    'Oversees the business: all records, money, financial reports, users, settings and backup.',
    Icons.workspace_premium_outlined,
  ),
  manager(
    'Farm Manager',
    'Runs daily operations: animals, feed, milk, health, breeding and stock. Sales, purchases, expenses and financial summaries only if the owner allows them.',
    Icons.manage_accounts_outlined,
  );

  const UserRole(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  /// Roles from earlier versions that no longer exist.
  static const retired = {'worker', 'veterinarian', 'accountant'};

  /// Reads a stored role name. Retired roles (Farm Worker, veterinarian,
  /// accountant) become [manager] — with no money rights, the least
  /// privileged access — so the owner can review them deliberately.
  static UserRole parse(String name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return manager;
  }
}
