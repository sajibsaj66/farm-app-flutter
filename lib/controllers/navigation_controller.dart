import 'package:flutter/foundation.dart';

import '../models/app_section.dart';
import '../models/farm_module.dart';
import '../models/access_policy.dart';

/// Which section is open, limited to the sections the user's role may see.
class NavigationController extends ChangeNotifier {
  NavigationController(AccessPolicy access) : sections = AppSection.all.where(access.canAccess).toList();

  /// Sections given their own bottom-bar tab (when the role can see them);
  /// everything else is under "More".
  static const preferredTabs = ['Overview', FarmModule.animals, FarmModule.feedRecords, FarmModule.milkProduction];

  static const maxBottomTabs = 4;

  final List<AppSection> sections;

  int _selected = 0;

  int get selectedIndex => _selected;

  AppSection get current => sections[_selected];

  List<AppSection> get bottomTabs {
    final preferred = preferredTabs.map((l) => sections.where((s) => s.label == l)).expand((s) => s).take(maxBottomTabs).toList();
    return preferred;
  }

  int get bottomNavIndex {
    final i = bottomTabs.indexWhere((s) => s.label == current.label);
    return i < 0 ? bottomTabs.length : i;
  }

  bool isMoreTab(int bottomIndex) => bottomIndex == bottomTabs.length;

  /// Selects the [bottomIndex]th bottom tab.
  void selectTab(int bottomIndex) => openSection(bottomTabs[bottomIndex].label);

  void select(int index) {
    if (index == _selected) return;
    _selected = index;
    notifyListeners();
  }

  void openNotifications() => select(sections.indexWhere((s) => s.kind == SectionKind.notifications));

  /// Opens the section called [label]; ignored if the role cannot see it.
  void openSection(String label) {
    final index = sections.indexWhere((s) => s.label == label);
    if (index >= 0) select(index);
  }

  /// Sections grouped under their headings, for the "More" menu.
  List<(String, List<(int, AppSection)>)> get grouped {
    final out = <(String, List<(int, AppSection)>)>[];
    for (final (i, s) in sections.indexed) {
      final g = s.group.isEmpty ? 'Home' : s.group;
      if (out.isEmpty || out.last.$1 != g) out.add((g, []));
      out.last.$2.add((i, s));
    }
    return out;
  }
}
