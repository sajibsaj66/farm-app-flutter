import 'app_section.dart';
import 'app_user.dart';
import 'farm_module.dart';
import 'user_role.dart';

/// Extra rights the Farm Owner can give an individual Farm Manager.
/// Without them a manager runs daily operations but sees no money records.
enum ManagerGrant {
  sales('Record sales & payments', 'Sales, payments received and customers'),
  purchases('Record purchases', 'Purchases of feed, medicine and supplies'),
  expenses('Record expenses', 'Daily farm expenses'),
  finance('See financial summaries', 'Profit & loss, cash flow, costs and income in dashboards, profiles and reports');

  const ManagerGrant(this.label, this.description);

  final String label;
  final String description;

  static Set<ManagerGrant> parse(dynamic saved) => {
        if (saved is List)
          for (final name in saved)
            for (final g in values)
              if (g.name == '$name') g,
      };
}

/// What one signed-in user may see and do. Every permission check in the app
/// goes through this class — the views use it to hide what is not allowed,
/// and [FarmController] uses it to refuse writes that are not allowed.
class AccessPolicy {
  const AccessPolicy(this.role, [this.grants = const {}]);

  factory AccessPolicy.of(AppUser? user) => user == null || !user.active ? none : AccessPolicy(user.role, user.grants);

  /// Signed out: nothing.
  static const none = AccessPolicy(null);

  final UserRole? role;
  final Set<ManagerGrant> grants;

  bool get isOwner => role == UserRole.owner;
  bool get isSignedIn => role != null;

  bool has(ManagerGrant g) => isOwner || (role == UserRole.manager && grants.contains(g));

  /// Modules a manager may open only with a grant.
  static const _grantFor = {
    FarmModule.sales: ManagerGrant.sales,
    FarmModule.collections: ManagerGrant.sales,
    FarmModule.customers: ManagerGrant.sales,
    FarmModule.purchases: ManagerGrant.purchases,
    FarmModule.expenses: ManagerGrant.expenses,
  };

  /// Farm setup and the staff list: a manager may look them up (e.g. to
  /// assign tasks) but only the owner hires staff or changes setup.
  static const _managerViewOnly = {FarmModule.species, FarmModule.locations, FarmModule.staff};

  bool canOpenModule(String module) {
    if (!isSignedIn || FarmModule.outOfScope.contains(module)) return false;
    final grant = _grantFor[module];
    return grant == null || has(grant);
  }

  bool canEditModule(String module) => canOpenModule(module) && (isOwner || !_managerViewOnly.contains(module));

  /// Permanently remove (or archive) records: owner only. Managers correct
  /// mistakes by editing; the owner reviews and removes.
  bool get canDelete => isOwner;

  /// Money: profit, costs and income figures and financial reports.
  bool get canSeeFinance => has(ManagerGrant.finance);

  /// Farm profile, calculation and health settings, users, backup/restore
  /// and loading demo data.
  bool get canManageSettings => isOwner;

  bool get canManageUsers => isOwner;

  bool get canResetData => isOwner;

  bool get canBackup => isOwner;

  /// The whole farm's activity log (each user always sees their own).
  bool get canViewActivityLog => isOwner;

  /// Approve or reject requests, large expenses and purchases, and review
  /// managers' reports. Fields marked owner-only can be set only by the owner.
  bool get canApprove => isOwner;

  /// Record that an illness case is over (recovered, chronic, died…).
  bool get canCloseIllness => isSignedIn;

  static const _openToAll = {SectionKind.overview, SectionKind.notifications, SectionKind.settings, SectionKind.reports, SectionKind.approvals};

  bool canAccess(AppSection section) {
    if (!isSignedIn) return false;
    if (_openToAll.contains(section.kind)) return true;
    if (section.kind == SectionKind.health) return true;
    return canOpenModule(section.label);
  }

  /// What this user can do with [module], in words.
  String accessLabel(String module) {
    if (!canOpenModule(module)) return 'No access';
    if (!canEditModule(module)) return 'View only';
    return canDelete ? 'View, add, edit & delete' : 'View, add & edit';
  }
}
