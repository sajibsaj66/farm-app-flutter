import 'package:flutter/material.dart';

import '../../controllers/herd_analytics.dart';
import '../../core/theme/app_colors.dart';
import '../../models/farm_record.dart';

/// Shows the result of a semen suitability check: verdict, findings, the
/// pedigree facts that could not be checked, and the disclaimer.
class SemenCheckCard extends StatelessWidget {
  const SemenCheckCard({super.key, required this.result, this.compact = false, this.onUse});

  final SemenSuitability result;

  /// Compact cards show the verdict and the first findings only.
  final bool compact;

  /// When set, shows a "Use this semen" button.
  final VoidCallback? onUse;

  static (Color, Color, IconData) styleFor(SuitabilityLevel level) => switch (level) {
        SuitabilityLevel.notRecommended => (const Color(0xFFFDE7E4), const Color(0xFFB3261E), Icons.block),
        SuitabilityLevel.verify => (const Color(0xFFFFF0D8), const Color(0xFF9A5B00), Icons.help_outline),
        SuitabilityLevel.noConflict => (const Color(0xFFE1F3E8), AppColors.brand, Icons.check_circle_outline),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = styleFor(result.level);
    final s = result.semen;
    final findings = compact ? result.findings.where((f) => f.level != SuitabilityLevel.noConflict).take(2).toList() : result.findings;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(result.headline, style: TextStyle(fontWeight: FontWeight.w800, color: fg))),
        ]),
        const SizedBox(height: 4),
        Text(
          '${s['code']} · ${FarmRecord.displayName(s['bull'])} (${s['breed']}) · ${s['straws']} straws · expires ${s['expiry']}',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
        if (findings.isNotEmpty) const SizedBox(height: 8),
        for (final f in findings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(styleFor(f.level).$3, size: 15, color: styleFor(f.level).$2),
              const SizedBox(width: 6),
              Expanded(child: Text(f.text, style: const TextStyle(fontSize: 12))),
            ]),
          ),
        if (result.missing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            compact ? 'Not recorded, so not checked: ${result.missing.length} item${result.missing.length == 1 ? '' : 's'}' : 'Not recorded, so these could not be checked:',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (!compact)
            for (final m in result.missing) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text('• $m', style: const TextStyle(fontSize: 12))),
        ],
        if (!compact) ...[
          const SizedBox(height: 8),
          const Text(SemenSuitability.disclaimer, style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
        ],
        if (onUse != null && result.level != SuitabilityLevel.notRecommended)
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: onUse, icon: const Icon(Icons.biotech_outlined, size: 18), label: const Text('Record AI with this semen'))),
      ]),
    );
  }
}
