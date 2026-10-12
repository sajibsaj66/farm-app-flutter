import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/reports_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import '../models/finance.dart';
import 'batch_profile_view.dart';
import 'cow_profile_view.dart';
import 'illness_details_view.dart';
import 'widgets/common_widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final controller = ReportsController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final table = controller.build();
          return ListView(padding: const EdgeInsets.all(18), children: [
            const Text('Reports & insights', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Calculated from records saved on this device. Every figure on screen is exactly what Copy CSV exports.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            DropdownButtonFormField<ReportKind>(
              // Keyed so the box always shows the report actually built.
              key: ValueKey(controller.kind),
              initialValue: controller.kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Report', prefixIcon: Icon(Icons.query_stats)),
              items: [for (final k in controller.kinds) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (k) => controller.setKind(k!),
            ),
            const SizedBox(height: 12),
            _FilterBar(controller: controller),
            if (controller.kind == ReportKind.feed) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final g in FeedGrouping.values) ChoiceChip(label: Text('By ${g.name}'), selected: controller.feedGrouping == g, onSelected: (_) => controller.setFeedGrouping(g)),
              ]),
            ],
            if (controller.kind == ReportKind.records) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('export:${controller.exportModule}'),
                initialValue: controller.exportModule,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Records to export', prefixIcon: Icon(Icons.table_rows_outlined)),
                items: [for (final m in controller.exportModules) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (m) => controller.setExportModule(m!),
              ),
            ],
            const SizedBox(height: 16),
            TextField(onChanged: controller.setQuery, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search this report…', isDense: true)),
            const SizedBox(height: 12),
            _TableView(table: table, period: controller.periodLabel, onOpen: _open, shown: controller.shown, onShowMore: controller.showMore),
          ]);
        },
      );

  void _open(String id) {
    final farm = controller.farm;
    final Widget? page = farm.find(FarmModule.batches, id) != null
        ? BatchProfilePage(batchId: id)
        : farm.find(FarmModule.animals, id) != null
            ? CowProfilePage(animalId: id)
            : farm.find(FarmModule.illness, id) != null
                ? IllnessDetailsPage(illnessId: id)
                : null;
    if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final ReportsController controller;

  @override
  Widget build(BuildContext context) {
    final f = controller.filter;
    Future<void> pickRange() async {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(start: f.from, end: f.to),
      );
      if (picked == null) return;
      final error = controller.setDates(picked.start, picked.end);
      if (error != null && context.mounted) showToast(context, error);
    }

    Widget pick(String label, String? value, List<String> options, String Function(String) labelOf, void Function(String?) onChanged) => SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('$label:$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All')),
              for (final o in options) DropdownMenuItem<String?>(value: o, child: Text(labelOf(o), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged,
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE7EDE8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: pickRange,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text('${formatDate(f.from)} → ${formatDate(f.to)}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in ReportsController.presets) ActionChip(label: Text(p), onPressed: () => controller.applyPreset(p)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          pick('Species', f.species, controller.speciesOptions, (s) => s, (v) => controller.setFilter(f.copyWith(species: v, clearSpecies: v == null))),
          pick('Location', f.location, controller.locationOptions, (s) => s, (v) => controller.setFilter(f.copyWith(location: v, clearLocation: v == null))),
          pick('Animal', f.animal, controller.animalOptions, controller.animalLabel, (v) => controller.setFilter(f.copyWith(animal: v, clearAnimal: v == null))),
          // Livestock only: a batch filter is shown only for older saved batch data.
          if (controller.batchOptions.isNotEmpty) pick('Batch', f.batch, controller.batchOptions, controller.batchLabel, (v) => controller.setFilter(f.copyWith(batch: v, clearBatch: v == null))),
          pick('Product', f.product, FarmModule.saleProducts, (s) => s, (v) => controller.setFilter(f.copyWith(product: v, clearProduct: v == null))),
        ]),
      ]),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({required this.table, required this.period, required this.onOpen, required this.shown, required this.onShowMore});

  final ReportTable table;
  final String period;
  final ValueChanged<String> onOpen;
  final int shown;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(table.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink))),
          FilledButton.tonalIcon(
            onPressed: table.rows.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: table.toCsv()));
                    if (context.mounted) showToast(context, '${table.title}: ${table.rows.length} rows copied as CSV');
                  },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy CSV'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(period, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (table.summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (label, value) in table.summary)
              Container(
                constraints: const BoxConstraints(minWidth: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 3),
                  Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ]),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        if (table.rows.isEmpty) const EmptyHint('Nothing to show for these dates and filters.'),
        for (final (i, row) in table.rows.take(shown).indexed) _RowCard(columns: table.columns, row: row, linkId: i < table.linkIds.length ? table.linkIds[i] : null, onOpen: onOpen),
        if (table.rows.length > shown)
          Center(
              child: TextButton.icon(
                  onPressed: onShowMore, icon: const Icon(Icons.expand_more), label: Text('Show more (${table.rows.length - shown} more rows — Copy CSV exports all ${table.rows.length})'))),
        if (table.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('How these figures are calculated', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          for (final n in table.notes) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $n', style: const TextStyle(fontSize: 12, color: Colors.black54))),
        ],
      ]);
}

/// One report row as a card: the first column is the title, the rest are
/// label/value pairs (readable on a phone, unlike a wide table).
class _RowCard extends StatelessWidget {
  const _RowCard({required this.columns, required this.row, required this.linkId, required this.onOpen});

  final List<String> columns;
  final List<String> row;
  final String? linkId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (var i = 1; i < row.length && i < columns.length; i++)
        if (row[i].isNotEmpty) (columns[i], row[i])
    ];
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE7EDE8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: linkId == null ? null : () => onOpen(linkId!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(row.isEmpty ? '' : row.first, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (linkId != null) const Icon(Icons.chevron_right, size: 18),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 2, children: [
              for (final (label, value) in values)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$label: ', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ])),
            ]),
          ]),
        ),
      ),
    );
  }
}
