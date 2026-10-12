import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/field_utils.dart';
import '../../models/farm_module.dart';
import '../../models/farm_record.dart';

enum RecordAction { profile, view, edit, archive, delete }

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.icon,
    required this.onAction,
    this.canEdit = true,
    this.canDelete = true,
    this.canArchive = false,
    this.hasProfile = false,
    this.summary,
  });

  final FarmRecord record;
  final IconData icon;
  final ValueChanged<RecordAction> onAction;
  final bool canEdit;
  final bool canDelete;
  final bool canArchive;

  /// Animals and batches open their full profile when tapped.
  final bool hasProfile;

  /// A calculated line (e.g. current head count, occupancy, amount due).
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final primary = record.title;
    final secondary = record.entries
        .where((e) => e.key != 'id' && !FarmModule.isInternal(e.key) && '${e.value}'.trim().isNotEmpty && e.value.toString() != primary)
        .take(3)
        .map((e) => '${fieldLabel(e.key)}: ${e.value}')
        .join('  ·  ');
    final status = record.status;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFE7EDE8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onAction(hasProfile ? RecordAction.profile : RecordAction.view),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.brand)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(primary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 4),
                Text('${record.id}  $secondary', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 11, height: 1.5)),
                if (summary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: record.needsAttention ? const Color(0xFFFFE9D8) : const Color(0xFFE1F3E8), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
            PopupMenuButton<RecordAction>(
              tooltip: 'Record actions',
              onSelected: onAction,
              itemBuilder: (_) => [
                if (hasProfile) const PopupMenuItem(value: RecordAction.profile, child: Text('Open full profile')),
                const PopupMenuItem(value: RecordAction.view, child: Text('View details')),
                if (canEdit) const PopupMenuItem(value: RecordAction.edit, child: Text('Edit')),
                if (canArchive) const PopupMenuItem(value: RecordAction.archive, child: Text('Archive (keep history)')),
                if (canDelete) const PopupMenuItem(value: RecordAction.delete, child: Text('Delete')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
