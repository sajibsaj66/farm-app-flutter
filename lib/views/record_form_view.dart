import 'package:flutter/material.dart';

import '../controllers/record_form_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/dates.dart';
import '../core/utils/field_utils.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import '../models/field_spec.dart';
import 'widgets/call_vet_button.dart';
import 'widgets/semen_check_card.dart';

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, required this.module, this.existing, this.initialValues = const {}});

  final String module;
  final FarmRecord? existing;

  /// Pre-filled values for a new record (e.g. the animal, from its profile).
  final Map<String, String> initialValues;

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  late final controller = RecordFormController(module: widget.module, existing: widget.existing, initialValues: widget.initialValues);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await controller.save();
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(controller.title)),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final semenCheck = controller.semenCheck;
            final withdrawal = controller.withdrawalWarning;
            final hint = controller.contextHint;
            return Form(
              key: controller.formKey,
              child: ListView(padding: const EdgeInsets.all(18), children: [
                if (!controller.canEdit)
                  const _Banner(icon: Icons.visibility_outlined, text: 'View only — your role can see these records but not change them.', tone: _Tone.info)
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.save_outlined, color: AppColors.brand),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_intro, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 12))),
                    ]),
                  ),
                const SizedBox(height: 18),
                ...controller.fields.where((f) => f != 'id' && controller.isVisible(f)).map((field) => Padding(padding: const EdgeInsets.only(bottom: 13), child: _fieldFor(context, field))),
                if (controller.illnessAdvice != null) ...[
                  _Banner(
                    icon: controller.isEmergency ? Icons.emergency : Icons.health_and_safety_outlined,
                    text: controller.illnessAdvice!,
                    tone: controller.isEmergency ? _Tone.error : _Tone.warning,
                  ),
                  if (controller.isEmergency || controller.valueOf('severity') == 'High')
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: CallVetButton(phone: controller.vetPhone, emergency: controller.isEmergency)),
                ],
                if (widget.module == FarmModule.illness)
                  const _Banner(
                    icon: Icons.info_outline,
                    text: 'This records what you observed. The app does not diagnose illness or recommend medicines — only a veterinarian can.',
                    tone: _Tone.info,
                  ),
                if (hint != null) _Banner(icon: Icons.info_outline, text: hint, tone: _Tone.info),
                if (withdrawal != null)
                  _Banner(
                    icon: Icons.block_outlined,
                    text: 'This animal is in a medicine withdrawal period until ${formatDate(withdrawal)}. The milk will be saved as Withheld and not counted as sellable.',
                  ),
                if (semenCheck != null) ...[
                  const Text('Semen suitability', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  SemenCheckCard(result: semenCheck),
                ],
                if (controller.error != null) _Banner(icon: Icons.error_outline, text: controller.error!, tone: _Tone.error),
                const SizedBox(height: 8),
                if (controller.canEdit) ...[
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: controller.saving ? null : _save,
                      icon: controller.saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                      label: Text(controller.saving ? 'Saving…' : 'Save record'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(height: 46, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(controller.canEdit ? 'Cancel' : 'Close'))),
              ]),
            );
          },
        ),
      );

  String get _intro => switch (widget.module) {
        FarmModule.illness => 'Report Animal Illness. Record only what you saw — leave measurements you did not take blank.',
        FarmModule.consultations => 'What the veterinarian found. Only choose "Veterinarian confirmed" if the vet confirmed the diagnosis.',
        FarmModule.treatments => 'Enter the treatment exactly as prescribed by the veterinarian. The app never calculates or suggests doses.',
        FarmModule.medication => 'Record each dose as Given, Delayed, Missed or Discontinued. A given dose from stock is taken out of Inventory once.',
        FarmModule.followUps => 'Schedule a check, or record how the animal is doing. Recovery is recorded separately on the illness case.',
        FarmModule.feedRecords => 'Record what one animal or a group ate. "From inventory" takes it out of stock; edits and deletes put it back.',
        FarmModule.breeding => 'For AI, one straw is taken from Semen Inventory and the semen is checked against the animal’s pedigree.',
        FarmModule.milkProduction => 'Record each shift separately. Milk during a withdrawal period is held back automatically.',
        FarmModule.weights => 'The animal’s current weight is updated from its latest weight record.',
        FarmModule.production => 'Record manure, wool, births and other products. Production is not income — record sales separately.',
        FarmModule.productUsage => 'Product used on the farm, given away or wasted. It is taken out of unsold stock.',
        FarmModule.sales => 'Net sales = quantity × price − discount − deductions. Later payments go in Payments Received.',
        FarmModule.collections => 'A payment received later for a sale. The sale’s outstanding amount updates automatically.',
        FarmModule.inventoryTx => 'Purchases, adjustments, wastage and physical counts change the stock and are kept as history.',
        FarmModule.inventory => 'The opening quantity is recorded as an opening stock movement. After that, stock changes only through Stock Transactions and feed records.',
        FarmModule.batches => 'A flock, pond, hive group or other batch tracked by head count.',
        FarmModule.batchMovements => 'Animals added to or taken out of a batch other than by death or sale.',
        FarmModule.mortality => 'Deaths and losses. An individual animal is marked Dead; deleting this record restores it.',
        FarmModule.expenses => 'Charge a cost to one animal or location, or share a farm-wide cost by an allocation method.',
        _ => 'This form saves to local app storage. No server is required.',
      };

  Widget _fieldFor(BuildContext context, String field) {
    final spec = controller.specFor(field);
    final label = controller.labelFor(field) + (spec.required || controller.isReadOnly(field) ? '' : ' (optional)');
    final hint = spec.hint;

    if (controller.isReadOnly(field)) {
      return TextFormField(
        controller: controller.textControllers[field],
        enabled: false,
        minLines: 1,
        maxLines: controller.isLongText(field) ? 8 : 1,
        decoration: InputDecoration(
          labelText: label,
          helperText: spec.computed ? 'Calculated automatically' : hint,
          helperMaxLines: 3,
          prefixIcon: Icon(fieldIcon(field)),
        ),
      );
    }

    switch (spec.type) {
      case FieldType.choice:
      case FieldType.animal:
      case FieldType.customer:
      case FieldType.semen:
      case FieldType.feedItem:
      case FieldType.inventoryItem:
      case FieldType.species:
      case FieldType.location:
      case FieldType.batch:
      case FieldType.sale:
      case FieldType.illness:
      case FieldType.treatment:
      case FieldType.staff:
        final options = controller.optionsFor(field);
        final current = controller.valueOf(field);
        final canClear = !spec.required && current.isNotEmpty;
        return DropdownButtonFormField<String>(
          // Rebuild when the value changes from outside (keeps the key unique per value).
          key: ValueKey('$field:$current'),
          initialValue: current.isEmpty ? null : current,
          isExpanded: true,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(controller.optionLabel(field, o), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => controller.setValue(field, v ?? ''),
          validator: (v) => controller.validate(field, v),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(_iconFor(spec, field)),
            helperText: options.isEmpty ? _emptyHint(spec.type) : hint,
            helperMaxLines: 3,
            suffixIcon: canClear ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => controller.setValue(field, '')) : null,
          ),
        );
      case FieldType.multiChoice:
        final selected = controller.selectedOf(field);
        return InputDecorator(
          decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 3, prefixIcon: const Icon(Icons.warning_amber_rounded)),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in spec.options)
              FilterChip(
                label: Text(o),
                selected: selected.contains(o),
                selectedColor: const Color(0xFFFDE7E4),
                onSelected: (v) => controller.toggleChoice(field, o, v),
              ),
          ]),
        );
      case FieldType.dateTime:
        return TextFormField(
          controller: controller.textControllers[field],
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Choose date and time',
            helperText: hint,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.schedule),
            suffixIcon: spec.required || controller.valueOf(field).isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => controller.setValue(field, '')),
          ),
          validator: (v) => controller.validate(field, v),
          onTap: () async {
            final initial = controller.initialDateFor(field);
            final day = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (day == null || !context.mounted) return;
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
            if (time == null) return;
            controller.setValue(field, RecordFormController.formatDateTime(DateTime(day.year, day.month, day.day, time.hour, time.minute)));
          },
        );
      case FieldType.date:
        return TextFormField(
          controller: controller.textControllers[field],
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Choose a date',
            helperText: hint,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            suffixIcon: spec.required || controller.valueOf(field).isEmpty ? null : IconButton(tooltip: 'Clear date', icon: const Icon(Icons.clear), onPressed: () => controller.setValue(field, '')),
          ),
          validator: (v) => controller.validate(field, v),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: controller.initialDateFor(field), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) controller.setValue(field, RecordFormController.formatDate(picked));
          },
        );
      case FieldType.number:
      case FieldType.phone:
      case FieldType.text:
        return TextFormField(
          controller: controller.textControllers[field],
          textInputAction: controller.isLongText(field) ? TextInputAction.newline : TextInputAction.next,
          minLines: 1,
          maxLines: controller.isLongText(field) ? 8 : 1,
          keyboardType: switch (spec.type) {
            FieldType.number => const TextInputType.numberWithOptions(decimal: true),
            FieldType.phone => TextInputType.phone,
            _ => controller.isLongText(field) ? TextInputType.multiline : TextInputType.text,
          },
          onChanged: spec.type == FieldType.number ? (_) => controller.touched(field) : null,
          decoration: InputDecoration(labelText: label, hintText: 'Enter ${controller.labelFor(field).toLowerCase()}', helperText: hint, helperMaxLines: 3, prefixIcon: Icon(fieldIcon(field))),
          validator: (v) => controller.validate(field, v),
        );
    }
  }

  IconData _iconFor(FieldSpec spec, String field) => switch (spec.type) {
        FieldType.semen => Icons.science_outlined,
        FieldType.feedItem || FieldType.inventoryItem => Icons.inventory_2_outlined,
        FieldType.species => Icons.category_outlined,
        FieldType.location => Icons.holiday_village_outlined,
        FieldType.batch => Icons.groups_outlined,
        FieldType.sale => Icons.receipt_outlined,
        FieldType.illness => Icons.sick_outlined,
        FieldType.treatment => Icons.medication_outlined,
        FieldType.staff => Icons.badge_outlined,
        _ => fieldIcon(field),
      };

  String? _emptyHint(FieldType type) => switch (type) {
        FieldType.animal => 'Add an animal first',
        FieldType.customer => 'Add a customer first',
        FieldType.semen => 'Add a semen batch in Semen Inventory first',
        FieldType.feedItem => 'Add a Feed item in Inventory first',
        FieldType.inventoryItem => 'Add an item in Inventory first',
        FieldType.species => 'Add a species in Species & Categories first',
        FieldType.location => 'Add a shed or pen first',
        FieldType.batch => 'Add a batch first',
        FieldType.sale => 'No sales with money outstanding',
        FieldType.illness => 'No open illness cases — report one first',
        FieldType.treatment => 'No ongoing treatment plans — add one to the illness case first',
        FieldType.staff => 'Add staff first (the owner manages Staff)',
        _ => null,
      };
}

enum _Tone { warning, info, error }

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.tone = _Tone.warning});

  final IconData icon;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _Tone.warning => (const Color(0xFFFFF0D8), const Color(0xFF9A5B00)),
      _Tone.info => (AppColors.brandSoft, AppColors.brand),
      _Tone.error => (const Color(0xFFFDE7E4), const Color(0xFFB3261E)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: tone == _Tone.error ? fg : null, fontWeight: tone == _Tone.error ? FontWeight.w600 : null))),
      ]),
    );
  }
}
