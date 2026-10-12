import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../controllers/farm_controller.dart';
import '../controllers/health_analytics.dart';
import '../controllers/illness_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'cow_profile_view.dart';
import 'illness_details_view.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';

/// Colour for a health status chip.
Color healthColor(String status) => switch (status) {
      FarmModule.healthHealthy => const Color(0xFFE1F3E8),
      FarmModule.healthRecovered => const Color(0xFFD7F0E3),
      FarmModule.healthTreatment => const Color(0xFFE4F0FF),
      FarmModule.healthFollowUp => const Color(0xFFFFF4D6),
      FarmModule.healthAwaitingVet => const Color(0xFFFFE9D8),
      FarmModule.healthSymptoms => const Color(0xFFFFF0D8),
      FarmModule.healthChronic => const Color(0xFFF0E7FF),
      _ => const Color(0xFFEDEDED),
    };

class HealthChip extends StatelessWidget {
  const HealthChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: healthColor(status), borderRadius: BorderRadius.circular(20)),
        child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class HealthDashboardPage extends StatefulWidget {
  const HealthDashboardPage({super.key, required this.onOpenSection});

  final ValueChanged<String> onOpenSection;

  @override
  State<HealthDashboardPage> createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage> {
  final controller = HealthDashboardController();
  final search = TextEditingController();

  /// The "Today & overdue" heading, scrolled to from its tile.
  final _todayKey = GlobalKey();

  @override
  void dispose() {
    controller.dispose();
    search.dispose();
    super.dispose();
  }

  void _report() => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordFormPage(module: FarmModule.illness)));

  void _openCase(String id) => Navigator.push(context, MaterialPageRoute(builder: (_) => IllnessDetailsPage(illnessId: id)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final h = controller.analytics;
          final rows = h.rows(controller.filter);
          final activities = h.activitiesOn();
          final urgent = h.urgentCases;
          final upcoming = h.upcomingFollowUps(7);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
            Row(children: [
              const Expanded(child: Text('Animal health', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink))),
              if (controller.canOpen(FarmModule.illness)) FilledButton.icon(onPressed: _report, icon: const Icon(Icons.sick_outlined, size: 18), label: const Text('Report illness')),
            ]),
            const Text('Records only — the app does not diagnose or prescribe. Always involve a veterinarian.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 640 ? 5 : 3;
              final w = (c.maxWidth - (cols - 1) * 8) / cols;
              Widget tile(String label, int value, IconData icon, Color tint, {VoidCallback? onTap}) => SizedBox(
                    width: w,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(icon, size: 18, color: AppColors.ink),
                          const SizedBox(height: 4),
                          Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        ]),
                      ),
                    ),
                  );
              void byStatus(String s) => controller.update(HealthFilter(status: s));
              return Wrap(spacing: 8, runSpacing: 8, children: [
                tile('Registered animals', h.activeAnimals.length, Icons.pets, const Color(0xFFE1F2E8), onTap: controller.clear),
                tile('Healthy', h.healthyCount, Icons.favorite_outline, healthColor(FarmModule.healthHealthy), onTap: () => byStatus(FarmModule.healthHealthy)),
                tile('Reported sick', h.sickAnimalCount, Icons.sick_outlined, healthColor(FarmModule.healthSymptoms), onTap: () => byStatus(HealthAnalytics.filterSick)),
                tile('Urgent vet attention', h.urgentAnimalCount, Icons.emergency, const Color(0xFFFDE7E4), onTap: () => byStatus(HealthAnalytics.filterUrgent)),
                tile('Under treatment', h.underTreatmentCount, Icons.medication, healthColor(FarmModule.healthTreatment), onTap: () => byStatus(FarmModule.healthTreatment)),
                tile('Awaiting follow-up', h.followUpCount, Icons.event_repeat, healthColor(FarmModule.healthFollowUp), onTap: () => byStatus(FarmModule.healthFollowUp)),
                tile('Recovered', h.recoveredCount, Icons.task_alt, healthColor(FarmModule.healthRecovered), onTap: () => byStatus(FarmModule.healthRecovered)),
                tile('Overdue follow-ups', h.overdueFollowUps.length, Icons.alarm, const Color(0xFFFFE9D8), onTap: () => widget.onOpenSection(FarmModule.followUps)),
                tile('Today’s activities', activities.length, Icons.today, const Color(0xFFE4F0FF),
                    onTap: () => Scrollable.ensureVisible(_todayKey.currentContext!, duration: const Duration(milliseconds: 300))),
              ]);
            }),
            if (urgent.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionTitle('Urgent — contact a veterinarian'),
              const SizedBox(height: 6),
              for (final c in urgent) _CaseTile(c: c, urgent: true, onTap: () => _openCase(c.id)),
            ],
            const SizedBox(height: 16),
            SectionTitle('Today & overdue', key: _todayKey),
            const SizedBox(height: 6),
            if (activities.isEmpty) const EmptyHint('Nothing scheduled for today and nothing overdue.'),
            for (final a in activities)
              Card(
                color: a.overdue ? const Color(0xFFFFF0D8) : Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(a.overdue ? Icons.alarm : Icons.today, color: a.overdue ? const Color(0xFF9A5B00) : AppColors.brand),
                  title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${a.overdue ? 'OVERDUE since ${formatDate(a.date)} · ' : ''}${a.detail}'),
                  onTap: () {
                    final r = controller.farm.find(a.module, a.recordId);
                    if (r != null) Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: a.module, existing: r)));
                  },
                ),
              ),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionTitle('Follow-ups in the next 7 days'),
              const SizedBox(height: 6),
              for (final f in upcoming)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_repeat, color: AppColors.brand),
                  title: Text('${f['dueDate']} · ${FarmRecord.displayName(f['animal'])} · ${f['type']}'),
                  subtitle: Text('Case ${FarmRecord.refId(f['illness']).toUpperCase()}${'${f['assignedTo'] ?? ''}'.isEmpty ? '' : ' · ${f['assignedTo']}'}'),
                  onTap: () => _openCase(FarmRecord.refId(f['illness']).toUpperCase()),
                ),
            ],
            const SizedBox(height: 16),
            const SectionTitle('Animals'),
            const SizedBox(height: 8),
            TextField(
              controller: search,
              onChanged: (v) => controller.update(_copy(controller.filter, query: v)),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by ID, tag or name…'),
            ),
            const SizedBox(height: 8),
            _Filters(
                controller: controller,
                onClear: () {
                  search.clear();
                  controller.clear();
                }),
            const SizedBox(height: 8),
            Text('${rows.length} animals', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (rows.isEmpty) const EmptyHint('No animals match these filters.'),
            for (final r in rows)
              Card(
                color: Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: r.urgent ? const Color(0xFFB3261E) : const Color(0xFFE7EDE8))),
                child: ListTile(
                  leading:
                      CircleAvatar(backgroundColor: healthColor(r.status), child: Icon(r.urgent ? Icons.emergency : Icons.pets, color: r.urgent ? const Color(0xFFB3261E) : AppColors.ink, size: 20)),
                  title: Text('${r.animal['name']} · ${r.animal.id}${'${r.animal['tag'] ?? ''}'.isEmpty ? '' : ' · ${r.animal['tag']}'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.animal['species']} · ${r.animal['breed']}${'${r.animal['group'] ?? ''}'.isEmpty ? '' : ' · ${r.animal['group']}'} · ${r.animal.status}',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      HealthChip(r.status),
                      if (r.activeTreatments > 0) HealthChip('${r.activeTreatments} active treatment${r.activeTreatments == 1 ? '' : 's'}'),
                      if (r.nextFollowUp != null) HealthChip('Follow-up ${formatDate(r.nextFollowUp!)}'),
                    ]),
                    if (r.latestCase != null) Text('${r.latestCase!.id}: ${r.latestCase!['symptoms']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ]),
                  isThreeLine: true,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalHealthHistoryPage(animalId: r.animal.id))),
                ),
              ),
          ]);
        },
      );

  static HealthFilter _copy(HealthFilter f, {String? query}) =>
      HealthFilter(query: query ?? f.query, species: f.species, breed: f.breed, group: f.group, status: f.status, from: f.from, to: f.to, treatment: f.treatment, vet: f.vet);
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.onClear});

  final HealthDashboardController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final f = controller.filter;
    HealthFilter with_(
            {Object? species = _keep,
            Object? breed = _keep,
            Object? group = _keep,
            Object? status = _keep,
            Object? treatment = _keep,
            Object? vet = _keep,
            Object? from = _keep,
            Object? to = _keep}) =>
        HealthFilter(
          query: f.query,
          species: species == _keep ? f.species : species as String?,
          breed: breed == _keep ? f.breed : breed as String?,
          group: group == _keep ? f.group : group as String?,
          status: status == _keep ? f.status : status as String?,
          treatment: treatment == _keep ? f.treatment : treatment as String?,
          vet: vet == _keep ? f.vet : vet as String?,
          from: from == _keep ? f.from : from as DateTime?,
          to: to == _keep ? f.to : to as DateTime?,
        );
    Widget pick(String label, String? value, List<String> options, HealthFilter Function(String?) make) => SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('$label:$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('All')), for (final o in options) DropdownMenuItem<String?>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => controller.update(make(v)),
          ),
        );
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      pick('Health status', f.status, HealthAnalytics.statusFilters, (v) => with_(status: v)),
      pick('Species', f.species, controller.speciesOptions, (v) => with_(species: v)),
      pick('Breed', f.breed, controller.breedOptions, (v) => with_(breed: v)),
      pick('Group', f.group, controller.groupOptions, (v) => with_(group: v)),
      pick('Treatment', f.treatment, const ['Active treatment', 'No active treatment'], (v) => with_(treatment: v)),
      pick('Veterinarian', f.vet, controller.vetOptions, (v) => with_(vet: v)),
      OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) controller.update(with_(from: picked.start, to: picked.end));
        },
        icon: const Icon(Icons.date_range, size: 18),
        label: Text(f.from == null ? 'Illness date' : '${formatDate(f.from!)} → ${formatDate(f.to!)}'),
      ),
      if (controller.hasFilters) TextButton.icon(onPressed: onClear, icon: const Icon(Icons.clear, size: 18), label: const Text('Clear filters')),
    ]);
  }
}

const _keep = Object();

class _CaseTile extends StatelessWidget {
  const _CaseTile({required this.c, required this.onTap, this.urgent = false});

  final FarmRecord c;
  final VoidCallback onTap;
  final bool urgent;

  @override
  Widget build(BuildContext context) => Card(
        color: urgent ? const Color(0xFFFDE7E4) : Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          leading: Icon(urgent ? Icons.emergency : Icons.sick_outlined, color: urgent ? const Color(0xFFB3261E) : AppColors.brand),
          title: Text('${FarmRecord.displayName(c['animal'])} · ${c['severity']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${c.id} · ${c['stage']} · ${c['symptoms']}${'${c['dangerSigns'] ?? ''}'.isEmpty ? '' : '\nSigns: ${c['dangerSigns']}'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

/// Every illness case of one animal, plus its production review.
class AnimalHealthHistoryPage extends StatelessWidget {
  const AnimalHealthHistoryPage({super.key, required this.animalId});

  final String animalId;

  @override
  Widget build(BuildContext context) {
    final farm = FarmController.instance;
    return ListenableBuilder(
      listenable: farm,
      builder: (context, _) {
        final animal = farm.find(FarmModule.animals, animalId);
        if (animal == null) return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('This animal is no longer in the register.')));
        final h = HealthAnalytics(farm);
        final cases = h.casesFor(animal);
        final review = h.productionReview(animal);
        return Scaffold(
          appBar: AppBar(
            title: Text('${animal['name']} — health history'),
            actions: [
              IconButton(
                  tooltip: 'Animal profile', icon: const Icon(Icons.pets_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CowProfilePage(animalId: animal.id))))
            ],
          ),
          floatingActionButton: FarmController.isActive(animal) && (AuthController.instance.access.canOpenModule(FarmModule.illness))
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: FarmModule.illness, initialValues: {'animal': animal.reference}))),
                  icon: const Icon(Icons.sick_outlined),
                  label: const Text('Report illness'),
                )
              : null,
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Text('${animal.id} · ${animal['species']} · ${animal['breed']} · ${animal.status}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: HealthChip(h.statusOf(animal))),
            const SizedBox(height: 12),
            const SectionTitle('Production review'),
            const SizedBox(height: 6),
            if (review.isEmpty) const EmptyHint('Not enough milk or feed records to compare.'),
            for (final r in review)
              Card(
                color: r.triggered ? const Color(0xFFFFF0D8) : Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('${r.triggered ? 'Review: ' : ''}${r.explanation}${r.triggered ? ' A drop is a reason to check the animal — not proof of disease.' : ''}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            const SizedBox(height: 12),
            SectionTitle('Illness history (${cases.length})'),
            const SizedBox(height: 6),
            if (cases.isEmpty) const EmptyHint('No illness has been reported for this animal.'),
            for (final c in cases) _CaseTile(c: c, urgent: false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IllnessDetailsPage(illnessId: c.id)))),
          ]),
        );
      },
    );
  }
}
