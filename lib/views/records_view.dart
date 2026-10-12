import 'package:flutter/material.dart';

import '../controllers/farm_controller.dart';
import '../controllers/records_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/field_utils.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'batch_profile_view.dart';
import 'cow_profile_view.dart';
import 'illness_details_view.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dialogs.dart';
import 'widgets/record_card.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.module});

  final String module;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  late RecordsController controller = RecordsController(widget.module);
  final searchField = TextEditingController();

  @override
  void didUpdateWidget(RecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      controller.dispose();
      controller = RecordsController(widget.module);
      searchField.clear();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    searchField.dispose();
    super.dispose();
  }

  static const _sortLabels = {RecordSort.newest: 'Newest first', RecordSort.oldest: 'Oldest first', RecordSort.nameAz: 'Name A–Z'};

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    return ListenableBuilder(
      listenable: Listenable.merge([controller.farm, controller]),
      builder: (context, _) {
        final all = controller.all;
        final filtered = controller.filtered;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Row(children: [
            Expanded(child: Text(module, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink))),
            PopupMenuButton<RecordSort>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              initialValue: controller.sort,
              onSelected: controller.setSort,
              itemBuilder: (_) => [for (final e in _sortLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            ),
            IconButton(tooltip: 'Refresh list', onPressed: controller.refresh, icon: const Icon(Icons.refresh)),
          ]),
          Text('${all.length} records · ${_sortLabels[controller.sort]} · saved on this device', style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(controller: searchField, onChanged: controller.setQuery, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search records…')),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: controller.filters
                  .map((f) => Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(f), selected: controller.filter == f, onSelected: (_) => controller.setFilter(f))))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text('${filtered.length} results', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54))),
            if (controller.canEdit)
              FilledButton.icon(onPressed: () => _openForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add new'))
            else
              const Chip(avatar: Icon(Icons.visibility_outlined, size: 16), label: Text('View only')),
          ]),
          const SizedBox(height: 12),
          if (all.isEmpty)
            EmptyHint(controller.canEdit ? 'No $module yet. Tap "Add new" to record the first one.' : 'No $module yet.')
          else if (filtered.isEmpty)
            const EmptyHint('No records match this search. Clear the search/filter or add a new record.')
          else
            ...filtered.map((record) => RecordCard(
                  record: record,
                  icon: FarmModule.recordIconFor(module),
                  canEdit: controller.canEdit,
                  canDelete: controller.canDelete,
                  canArchive: controller.canArchive && FarmController.isActive(record),
                  hasProfile: controller.hasProfile,
                  summary: controller.summaryFor(record),
                  onAction: (action) => switch (action) {
                    RecordAction.profile => _openProfile(context, record),
                    RecordAction.view => _viewRecord(context, record),
                    RecordAction.edit => _openForm(context, existing: record),
                    RecordAction.archive => _archive(context, record),
                    RecordAction.delete => _confirmDelete(context, record),
                  },
                )),
        ]);
      },
    );
  }

  void _openProfile(BuildContext context, FarmRecord record) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => switch (widget.module) {
            FarmModule.batches => BatchProfilePage(batchId: record.id),
            FarmModule.illness => IllnessDetailsPage(illnessId: record.id),
            _ => CowProfilePage(animalId: record.id),
          },
        ),
      );

  void _viewRecord(BuildContext context, FarmRecord record) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
            Text('${widget.module} details', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...record.entries.where((e) => !FarmModule.isInternal(e.key)).map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: Text(FarmModule.specFor(widget.module, e.key).label ?? fieldLabel(e.key), style: const TextStyle(color: Colors.black54))),
                    Expanded(child: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                )),
            const SizedBox(height: 12),
            if (controller.canEdit)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openForm(context, existing: record);
                  },
                  child: const Text('Edit record'),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _archive(BuildContext context, FarmRecord record) async {
    final ok =
        await confirmDialog(context, title: 'Archive ${record.shortLabel}?', message: 'It will be hidden from pickers but kept, with all its history, in lists and reports.', confirmLabel: 'Archive');
    if (!ok) return;
    try {
      await controller.archive(record);
      if (context.mounted) showToast(context, 'Archived');
    } on FarmRuleException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  Future<void> _confirmDelete(BuildContext context, FarmRecord record) async {
    final links = controller.linksTo(record);
    if (links.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text(
              '"${record.shortLabel}" is used by ${links.length} other record${links.length == 1 ? '' : 's'} (for example ${links.first.$1} ${links.first.$2.id}). Deleting it would break their history.${controller.canArchive ? '\n\nArchive it instead to keep the history.' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            if (controller.canArchive && FarmController.isActive(record))
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _archive(context, record);
                },
                child: const Text('Archive instead'),
              ),
          ],
        ),
      );
      return;
    }
    final ok = await confirmDialog(context, title: 'Delete record?', message: 'Delete "${record.shortLabel}" from this device? Linked stock and statuses are put back.', confirmLabel: 'Delete');
    if (!ok) return;
    try {
      await controller.delete(record);
      if (context.mounted) showToast(context, 'Record deleted');
    } on FarmRuleException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  Future<void> _openForm(BuildContext context, {FarmRecord? existing}) => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: widget.module, existing: existing)));
}
