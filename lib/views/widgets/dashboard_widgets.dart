import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/activity_entry.dart';
import '../../models/alert_item.dart';

/// Navy header card at the top of a dashboard.
class DashboardHero extends StatelessWidget {
  const DashboardHero({super.key, required this.caption, required this.headline, required this.detail, required this.stats});

  final String caption;
  final String headline;
  final String detail;

  /// (label, value) pairs shown along the bottom.
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          Text(headline, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 10, children: [
            for (final (label, value) in stats)
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              ]),
          ]),
        ]),
      );
}

/// Tone of a figure: neutral, good (green), warning (amber) or bad (red).
enum StatTone { neutral, good, warning, bad }

/// One figure on a dashboard, tappable when it links to a section.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.sub, this.tone = StatTone.neutral, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final String? sub;
  final StatTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatTone.good => (AppColors.positiveSoft, AppColors.positive),
      StatTone.warning => (AppColors.warningSoft, AppColors.warning),
      StatTone.bad => (AppColors.dangerSoft, AppColors.danger),
      StatTone.neutral => (AppColors.brandSoft, AppColors.navy),
    };
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.inputBorder)),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: fg, size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tone == StatTone.neutral ? AppColors.ink : fg)),
                if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lays [children] out in 2 columns on phones and 3–4 on wider screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
        const gap = 10.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final w in children) SizedBox(width: width, child: w)]);
      });
}

/// Section heading with an optional action on the right.
class DashSection extends StatelessWidget {
  const DashSection(this.title, {super.key, this.subtitle, this.action, this.onAction});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          if (action != null && onAction != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

/// A row in a dashboard list (task, alert, low stock item…).
class DashRow extends StatelessWidget {
  const DashRow({super.key, required this.icon, required this.title, this.subtitle, this.tone = StatTone.neutral, this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final StatTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      StatTone.good => AppColors.positiveSoft,
      StatTone.warning => AppColors.warningSoft,
      StatTone.bad => AppColors.dangerSoft,
      StatTone.neutral => Colors.white,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: tone == StatTone.bad ? AppColors.danger : (tone == StatTone.warning ? AppColors.warning : AppColors.navy)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

DashRow alertRow(AlertItem alert, {VoidCallback? onTap}) =>
    DashRow(icon: alert.icon, title: alert.title, subtitle: alert.message, tone: alert.tone == AlertTone.warning ? StatTone.warning : StatTone.neutral, onTap: onTap);

DashRow activityRow(ActivityEntry a) => DashRow(icon: Icons.history, title: a.title, subtitle: a.subtitle);

/// A quick-action button (orange icon).
class DashAction extends StatelessWidget {
  const DashAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 18, color: AppColors.orange),
        label: Text(label),
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.inputBorder),
        onPressed: onTap,
      );
}
