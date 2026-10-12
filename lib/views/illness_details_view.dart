import 'package:flutter/material.dart';

import '../controllers/health_analytics.dart';
import '../controllers/illness_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import 'cow_profile_view.dart';
import 'record_form_view.dart';
import 'widgets/call_vet_button.dart';
import 'widgets/common_widgets.dart';

/// One illness case from report to recovery.
class IllnessDetailsPage extends StatefulWidget {
  const IllnessDetailsPage({super.key, required this.illnessId});

  final String illnessId;

  @override
  State<IllnessDetailsPage> createState() => _IllnessDetailsPageState();
}

class _IllnessDetailsPageState extends State<IllnessDetailsPage> {
  late final controller = IllnessController(widget.illnessId);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _form(String module, {FarmRecord? existing, Map<String, String> values = const {}}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: module, existing: existing, initialValues: values)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final i = controller.illness;
          if (i == null) return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('This illness case no longer exists.')));
          final ref = controller.reference;
          final open = controller.isOpen;
          final animal = controller.animal;
          return Scaffold(
            appBar: AppBar(
              title: Text('Illness ${i.id}'),
              actions: [
                if (animal != null)
                  IconButton(
                      tooltip: 'Animal profile',
                      icon: const Icon(Icons.pets_outlined),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CowProfilePage(animalId: animal.id)))),
                IconButton(tooltip: 'Edit report', icon: const Icon(Icons.edit_outlined), onPressed: () => _form(FarmModule.illness, existing: i)),
              ],
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              _Header(i: i, urgent: controller.isUrgent),
              const SizedBox(height: 12),
              if (open) ...[
                _Advice(text: controller.advice, urgent: controller.isUrgent),
                if (controller.isUrgent || '${i['severity']}' == 'High')
                  Padding(padding: const EdgeInsets.only(top: 8), child: CallVetButton(phone: controller.vetPhone, emergency: controller.isUrgent)),
                const SizedBox(height: 12),
              ],
              _Lifecycle(steps: controller.lifecycle),
              const SizedBox(height: 12),
              _Section(title: 'Reported symptoms', subtitle: 'As reported on ${i['reportedAt']} by ${i['reportedBy']} — not a diagnosis', children: [
                _Row('Noticed', '${i['noticedAt']}'),
                _Row('Main symptoms', '${i['symptoms']}'),
                if ('${i['dangerSigns'] ?? ''}'.isNotEmpty) _Row('Life-threatening signs', '${i['dangerSigns']}', color: const Color(0xFFB3261E)),
                if ('${i['observations'] ?? ''}'.isNotEmpty) _Row('Observations', '${i['observations']}'),
                _Row('Appetite', '${i['appetite']}'),
                _Row('Water intake', '${i['water']}'),
                _Row('Milk change', '${i['milkChange']}'),
                if ('${i['behaviour'] ?? ''}'.isNotEmpty) _Row('Behaviour', '${i['behaviour']}'),
                _Row('Temperature', '${i['temperature'] ?? ''}'.isEmpty ? 'Not measured' : '${i['temperature']} ${i['tempUnit']}'),
                if ('${i['injury'] ?? ''}'.isNotEmpty) _Row('Injury / abnormality', '${i['injury']}'),
                _Row('Severity', '${i['severity']}'),
                if ('${i['suspectedCause'] ?? ''}'.isNotEmpty) _Row('Suspected cause', '${i['suspectedCause']} (unconfirmed)'),
                if ('${i['notes'] ?? ''}'.isNotEmpty) _Row('Notes', '${i['notes']}'),
              ]),
              _Section(
                title: 'Veterinary assessment & diagnosis',
                trailing: open && controller.canOpen(FarmModule.consultations)
                    ? TextButton.icon(onPressed: () => _form(FarmModule.consultations, values: {'illness': ref}), icon: const Icon(Icons.add, size: 18), label: const Text('Consultation'))
                    : null,
                children: [
                  _DiagnosisChip(status: '${i['diagnosisStatus']}', diagnosis: '${i['diagnosis'] ?? ''}'),
                  const SizedBox(height: 6),
                  if (controller.consultations.isEmpty) const Text('No veterinary consultation recorded yet.', style: TextStyle(color: Colors.black54)),
                  for (final c in controller.consultations)
                    _Tile(
                      Icons.local_hospital_outlined,
                      '${c['date']} · ${c['vetName']} · ${c['diagnosisStatus']}',
                      [
                        if ('${c['diagnosis'] ?? ''}'.isNotEmpty) 'Diagnosis: ${c['diagnosis']}',
                        'Findings: ${c['observations']}',
                        if ('${c['recommendedTreatment'] ?? ''}'.isNotEmpty) 'Advised: ${c['recommendedTreatment']}',
                        if ('${c['nextDate'] ?? ''}'.isNotEmpty) 'Next visit ${c['nextDate']}'
                      ].join('\n'),
                      () => _form(FarmModule.consultations, existing: c),
                    ),
                ],
              ),
              _Section(
                title: 'Treatment plan & medication',
                trailing: open && controller.canOpen(FarmModule.treatments)
                    ? TextButton.icon(onPressed: () => _form(FarmModule.treatments, values: {'illness': ref}), icon: const Icon(Icons.add, size: 18), label: const Text('Treatment'))
                    : null,
                children: [
                  if (controller.treatments.isEmpty) const Text('No treatment recorded. Treatments are entered only as prescribed by a veterinarian.', style: TextStyle(color: Colors.black54)),
                  for (final t in controller.treatments) _treatment(t),
                ],
              ),
              _Section(
                title: 'Follow-ups',
                trailing: open && controller.canOpen(FarmModule.followUps)
                    ? TextButton.icon(onPressed: () => _form(FarmModule.followUps, values: {'illness': ref}), icon: const Icon(Icons.add, size: 18), label: const Text('Follow-up'))
                    : null,
                children: [
                  if (controller.followUps.isEmpty) const Text('No follow-up scheduled.', style: TextStyle(color: Colors.black54)),
                  for (final f in controller.followUps)
                    _Tile(
                      Icons.event_repeat_outlined,
                      '${f['dueDate']} · ${f['type']} · ${f['status']}${'${f['status']}' == 'Scheduled' && (f.dateOf('dueDate')?.isBefore(controller.today) ?? false) ? ' · OVERDUE' : ''}',
                      [
                        if ('${f['progress'] ?? ''}'.isNotEmpty) 'Symptoms: ${f['progress']}',
                        if ('${f['observations'] ?? ''}'.isNotEmpty) '${f['observations']}',
                        if ('${f['vetAssessment'] ?? ''}'.isNotEmpty) 'Vet: ${f['vetAssessment']}',
                        if ('${f['nextAction'] ?? ''}'.isNotEmpty) 'Next: ${f['nextAction']}'
                      ].join('\n'),
                      () => _form(FarmModule.followUps, existing: f),
                      warn: '${f['progress']}' == 'Worsened',
                    ),
                ],
              ),
              _production(controller.productionChanges),
              _closure(i),
            ]),
          );
        },
      );

  Widget _treatment(FarmRecord t) {
    final doses = controller.doses(t);
    final ref = '${t.id} · ${t['medicine']} · ${FarmRecord.displayName(t['animal'])}';
    // A Material rather than a decorated box, so tapping a dose shows ink.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: _treatmentBody(t, doses, ref),
        ),
      ),
    );
  }

  Widget _treatmentBody(FarmRecord t, List<FarmRecord> doses, String ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.medication, color: AppColors.brand, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text('${t['medicine']} · ${t['outcome']}', style: const TextStyle(fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Edit treatment', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _form(FarmModule.treatments, existing: t)),
      ]),
      Text('Prescribed by ${t['prescribedBy']}: ${t['dose']} ${t['doseUnit']}${'${t['route'] ?? ''}'.isEmpty ? '' : ' · ${t['route']}'} · ${t['frequency']}', style: const TextStyle(fontSize: 12)),
      Text('From ${t['startDate']}${'${t['endDate'] ?? ''}'.isEmpty ? '' : ' to ${t['endDate']} (planned)'}${'${t['withdrawalDays'] ?? ''}'.isEmpty ? '' : ' · ${t['withdrawalDays']}-day withdrawal'}',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      if ('${t['outcomeNotes'] ?? ''}'.isNotEmpty) Text('Reason: ${t['outcomeNotes']}', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 6),
      Text('Doses (${doses.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      for (final d in doses.take(8))
        _Tile(
          Icons.vaccines_outlined,
          '${d['status']} · ${'${d['givenAt'] ?? ''}'.isNotEmpty ? d['givenAt'] : d['scheduledAt']}',
          [
            if ('${d['doseGiven'] ?? ''}'.isNotEmpty) '${d['doseGiven']}',
            if ('${d['administeredBy'] ?? ''}'.isNotEmpty) 'by ${d['administeredBy']}',
            if ('${d['reason'] ?? ''}'.isNotEmpty) 'Reason: ${d['reason']}',
            if ('${d['sideEffects'] ?? ''}'.isNotEmpty) 'Reaction: ${d['sideEffects']} — contact the vet'
          ].join(' · '),
          () => _form(FarmModule.medication, existing: d),
          warn: '${d['sideEffects'] ?? ''}'.isNotEmpty || '${d['status']}' == FarmModule.medMissed,
        ),
      if (doses.length > 8) Text('+ ${doses.length - 8} more in the Medication Log', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      if (controller.isOpen && controller.canOpen(FarmModule.medication) && '${t['outcome']}' == FarmModule.treatmentOngoing)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _form(FarmModule.medication, values: {'treatment': ref}), icon: const Icon(Icons.add, size: 18), label: const Text('Record dose')),
        ),
    ]);
  }

  Widget _production(List<ProductionReview> reviews) {
    if (reviews.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'Production around this illness', subtitle: 'Recorded values only — a drop is a reason to review, not proof of disease', children: [
      for (final r in reviews)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(r.triggered ? Icons.trending_down : Icons.check_circle_outline, size: 18, color: r.triggered ? const Color(0xFF9A5B00) : AppColors.brand),
            const SizedBox(width: 6),
            Expanded(child: Text(r.explanation, style: const TextStyle(fontSize: 12))),
          ]),
        ),
    ]);
  }

  Widget _closure(FarmRecord i) {
    final closure = '${i['closure'] ?? ''}';
    return _Section(title: 'Recovery & case outcome', children: [
      if (closure.isEmpty) ...[
        const Text('The case stays open until an owner or manager records the outcome. A treatment end date passing does not mark the animal recovered.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        if (controller.canClose)
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CloseIllnessPage(controller: controller))),
            icon: const Icon(Icons.task_alt),
            label: const Text('Record recovery or outcome'),
          )
        else
          const Text('Ask the Farm Owner or Manager to record recovery.', style: TextStyle(fontWeight: FontWeight.w600)),
      ] else ...[
        _Row('Outcome', closure, color: closure == FarmModule.closeRecovered ? AppColors.brand : null),
        _Row('Date', '${i['closedOn']}'),
        _Row('Notes', '${i['closureNotes']}'),
        if (closure == FarmModule.closeChronic && controller.canClose)
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CloseIllnessPage(controller: controller))), child: const Text('Record final outcome')),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: () => _reopen(context), icon: const Icon(Icons.replay), label: const Text('Symptoms came back — reopen case')),
      ],
      if (FarmRecord.leadingNumber(i['reopenedCount']) != null && FarmRecord.leadingNumber(i['reopenedCount'])! > 0)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reopened ${i['reopenedCount']} time(s). Earlier outcomes are kept in the notes.', style: const TextStyle(fontSize: 12, color: Colors.black54))),
    ]);
  }

  Future<void> _reopen(BuildContext context) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen this case?'),
        content: TextField(controller: reason, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'What has come back?', hintText: 'e.g. swelling returned, not eating again')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reopen')),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true) return;
    final error = await controller.reopen(text);
    if (context.mounted) showToast(context, error ?? 'Case reopened — the earlier outcome is kept in its notes');
  }
}

/// Records the end of a case. Requires notes and an explicit confirmation.
class CloseIllnessPage extends StatefulWidget {
  const CloseIllnessPage({super.key, required this.controller});

  final IllnessController controller;

  @override
  State<CloseIllnessPage> createState() => _CloseIllnessPageState();
}

class _CloseIllnessPageState extends State<CloseIllnessPage> {
  String outcome = FarmModule.closeRecovered;
  late DateTime date = widget.controller.today;
  final notes = TextEditingController();
  bool confirmed = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    final result = await widget.controller.close(outcome: outcome, date: date, notes: notes.text, confirmed: confirmed);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        busy = false;
        error = result;
      });
      return;
    }
    if (outcome == FarmModule.closeDied) showToast(context, 'Outcome saved. Also record the death in Mortality & Losses so the animal is marked Dead.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final blockers = widget.controller.blockers(outcome);
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery & case outcome')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Record the outcome only when the animal’s condition — and, where needed, the veterinarian — supports it.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        for (final o in FarmModule.closures)
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: o,
            // ignore: deprecated_member_use
            groupValue: outcome,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => outcome = v!),
            title: Text(o),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: widget.controller.today);
            if (picked != null) setState(() => date = picked);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date: ${formatDate(date)}'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Condition and notes', hintText: 'e.g. eating normally, udder swelling gone, vet advised stop on …')),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: confirmed,
          onChanged: (v) => setState(() => confirmed = v ?? false),
          title: const Text('I confirm this is based on the animal’s current condition and veterinary guidance where needed.'),
        ),
        for (final b in blockers)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(10)),
            child: Text(b, style: const TextStyle(fontSize: 12)),
          ),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600))),
        SizedBox(height: 50, child: FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Save outcome'))),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.i, required this.urgent});

  final FarmRecord i;
  final bool urgent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: urgent ? const [Color(0xFF8C1D18), Color(0xFFB3261E)] : const [AppColors.navy, AppColors.navyLight]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(FarmRecord.displayName(i['animal']), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          Text('${FarmRecord.refId(i['animal']).toUpperCase()} · ${i['species']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Pill('${i['stage']}'),
            _Pill('Severity: ${i['severity']}'),
            if (urgent) const _Pill('URGENT'),
          ]),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink)),
      );
}

class _Advice extends StatelessWidget {
  const _Advice({required this.text, required this.urgent});

  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: urgent ? const Color(0xFFFDE7E4) : const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(urgent ? Icons.emergency : Icons.health_and_safety_outlined, color: urgent ? const Color(0xFFB3261E) : const Color(0xFF9A5B00)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontWeight: urgent ? FontWeight.w800 : FontWeight.w500))),
        ]),
      );
}

class _Lifecycle extends StatelessWidget {
  const _Lifecycle({required this.steps});

  final List<(String, bool)> steps;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (i, (label, done)) in steps.indexed)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? AppColors.brand : Colors.black38),
            label: Text('${i + 1}. $label', style: const TextStyle(fontSize: 11)),
          ),
      ]);
}

class _DiagnosisChip extends StatelessWidget {
  const _DiagnosisChip({required this.status, required this.diagnosis});

  final String status;
  final String diagnosis;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      FarmModule.diagConfirmed => (const Color(0xFFE1F3E8), 'Confirmed by veterinarian'),
      FarmModule.diagSuspected => (const Color(0xFFFFF0D8), 'Suspected by veterinarian — not confirmed'),
      _ => (const Color(0xFFEDEDED), 'Not evaluated by a veterinarian yet'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        if (diagnosis.isNotEmpty) Text(diagnosis, style: const TextStyle(fontSize: 14)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE7EDE8))),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink))),
                if (trailing != null) trailing!,
              ]),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color))),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap, {this.warn = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: warn ? const Color(0xFF9A5B00) : AppColors.brand, size: 20),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      );
}
