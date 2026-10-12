import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/account_controllers.dart';
import '../controllers/auth_controller.dart';
import '../controllers/illness_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_profile.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dialogs.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final controller = ChangePasswordController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await controller.submit();
    if (!ok || !mounted) return;
    showToast(context, 'Password changed');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Change password')),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Form(
            key: controller.formKey,
            child: ListView(padding: const EdgeInsets.all(18), children: [
              TextFormField(
                controller: controller.current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => (v == null || v.isEmpty) ? 'Please enter your current password' : null,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: controller.next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_reset), helperText: 'At least ${AuthController.minPasswordLength} characters'),
                validator: AuthController.validatePassword,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: controller.confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_reset)),
                validator: controller.validateConfirm,
              ),
              if (controller.error != null) ...[
                const SizedBox(height: 10),
                Text(controller.error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              SizedBox(height: 50, child: FilledButton.icon(onPressed: controller.busy ? null : _submit, icon: const Icon(Icons.check), label: const Text('Change password'))),
            ]),
          ),
        ),
      );
}

class FarmProfilePage extends StatefulWidget {
  const FarmProfilePage({super.key});

  @override
  State<FarmProfilePage> createState() => _FarmProfilePageState();
}

class _FarmProfilePageState extends State<FarmProfilePage> {
  final controller = FarmProfileController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await controller.save();
    if (!ok || !mounted) return;
    showToast(context, 'Farm profile saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Farm profile')),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Form(
            key: controller.formKey,
            child: ListView(padding: const EdgeInsets.all(18), children: [
              TextFormField(
                  controller: controller.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Farm name', prefixIcon: Icon(Icons.agriculture)),
                  validator: controller.validateName),
              const SizedBox(height: 13),
              TextFormField(
                  controller: controller.location,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Location (optional)', prefixIcon: Icon(Icons.place_outlined))),
              const SizedBox(height: 13),
              TextFormField(
                  controller: controller.phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Contact phone (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: controller.validatePhone),
              const SizedBox(height: 13),
              TextFormField(
                  controller: controller.currency,
                  decoration: const InputDecoration(labelText: 'Currency symbol', prefixIcon: Icon(Icons.payments_outlined), helperText: 'Shown before every amount, e.g. ৳'),
                  validator: controller.validateCurrency),
              const SizedBox(height: 13),
              TextFormField(
                  controller: controller.milkPrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Milk price per litre', prefixIcon: Icon(Icons.water_drop_outlined), helperText: 'Used to value each cow’s milk in her profile and reports'),
                  validator: controller.validateMilkPrice),
              const SizedBox(height: 18),
              SizedBox(height: 50, child: FilledButton.icon(onPressed: controller.busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Save profile'))),
            ]),
          ),
        ),
      );
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final controller = BackupController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _copyBackup() async {
    await Clipboard.setData(ClipboardData(text: controller.buildBackup()));
    if (mounted) showToast(context, 'Backup copied — paste it somewhere safe (email, notes, Drive)');
  }

  Future<void> _restore() async {
    final ok = await confirmDialog(
      context,
      title: 'Restore from backup?',
      message: 'All current records, the farm profile and the activity log will be replaced by the backup. User accounts are not changed.',
      confirmLabel: 'Restore',
    );
    if (!ok) return;
    final restored = await controller.restore();
    if (restored && mounted) showToast(context, 'Data restored from backup');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backup & restore')),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(padding: const EdgeInsets.all(18), children: [
            const SectionTitle('Back up'),
            const SizedBox(height: 6),
            const Text('Copies every record, the farm profile and the activity log as text. Passwords are never included.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            SizedBox(height: 48, child: FilledButton.icon(onPressed: _copyBackup, icon: const Icon(Icons.copy), label: const Text('Copy backup to clipboard'))),
            if (controller.autoBackupDate != null) ...[
              const SizedBox(height: 28),
              const SectionTitle('Automatic backup'),
              const SizedBox(height: 6),
              Text('Saved before demo data was loaded on ${controller.autoBackupDate!.toIso8601String().replaceFirst('T', ' ').split('.').first}.', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () async {
                          final ok = await confirmDialog(context,
                              title: 'Restore the automatic backup?', message: 'Current records are replaced by the data saved before the demo was loaded.', confirmLabel: 'Restore');
                          if (!ok) return;
                          final restored = await controller.restoreAutoBackup();
                          if (context.mounted) showToast(context, restored ? 'Your data has been restored' : (controller.error ?? 'Restore failed'));
                        },
                  icon: const Icon(Icons.history),
                  label: const Text('Restore automatic backup'),
                ),
              ),
            ],
            const SizedBox(height: 28),
            const SectionTitle('Restore'),
            const SizedBox(height: 6),
            const Text('Paste a backup made with this app, then tap Restore.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: controller.restoreInput,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(hintText: '{ "app": "technovate_farm", ... }', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) controller.restoreInput.text = data!.text!;
                },
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste from clipboard'),
              ),
            ),
            if (controller.error != null) Text(controller.error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(height: 48, child: OutlinedButton.icon(onPressed: controller.busy ? null : _restore, icon: const Icon(Icons.settings_backup_restore), label: const Text('Restore'))),
          ]),
        ),
      );
}

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final controller = ActivityLogController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Activity log')),
        body: ListenableBuilder(
          listenable: Listenable.merge([controller, controller.farm]),
          builder: (context, _) {
            final entries = controller.entries;
            return ListView(padding: const EdgeInsets.all(18), children: [
              TextField(onChanged: controller.setQuery, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by action, person or date…')),
              const SizedBox(height: 12),
              Text('${entries.length} entries · last ${controller.farm.activity.length} of up to 200 kept', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 8),
              if (entries.isEmpty) const EmptyHint('No activity matches this search.'),
              ...entries.map((e) => Card(
                    color: Colors.white,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: AppColors.brandSoft, child: Icon(Icons.history, color: AppColors.brand)),
                      title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(e.subtitle),
                    ),
                  )),
            ]);
          },
        ),
      );
}

/// Owner only: how profit, feed cost and animal asset cost are calculated,
/// and the alert thresholds.
class CalculationSettingsPage extends StatefulWidget {
  const CalculationSettingsPage({super.key});

  @override
  State<CalculationSettingsPage> createState() => _CalculationSettingsPageState();
}

class _CalculationSettingsPageState extends State<CalculationSettingsPage> {
  final controller = CalculationSettingsController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await controller.save();
    if (!ok || !mounted) return;
    showToast(context, 'Calculation settings saved — reports use them now');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calculation settings')),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Form(
            key: controller.formKey,
            child: ListView(padding: const EdgeInsets.all(18), children: [
              const SectionTitle('Feed cost'),
              const SizedBox(height: 4),
              const Text('Choose when feed is charged in profit and loss. The other is never added on top, so feed is not counted twice.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              for (final v in FeedCostBasis.values)
                RadioListTile<FeedCostBasis>(
                  contentPadding: EdgeInsets.zero,
                  value: v,
                  // ignore: deprecated_member_use
                  groupValue: controller.feedCostBasis,
                  // ignore: deprecated_member_use
                  onChanged: (x) => controller.setFeedCostBasis(x!),
                  title: Text(v.label),
                  subtitle: Text(v == FeedCostBasis.consumption ? 'Recommended. Feed expenses are treated as stock bought.' : 'Feed records issued from stock are then shown for analysis only.'),
                ),
              const SizedBox(height: 14),
              const SectionTitle('Animal purchase price'),
              const SizedBox(height: 4),
              const Text('A purchased animal is an asset. Its price is never charged to every day’s profit.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              for (final v in AssetMethod.values)
                RadioListTile<AssetMethod>(
                  contentPadding: EdgeInsets.zero,
                  value: v,
                  // ignore: deprecated_member_use
                  groupValue: controller.assetMethod,
                  // ignore: deprecated_member_use
                  onChanged: (x) => controller.setAssetMethod(x!),
                  title: Text(v.label),
                  subtitle: Text(v == AssetMethod.capitalize ? 'Book value is charged only when the animal is sold or dies.' : 'A share of the price is charged each day; the rest when sold or lost.'),
                ),
              if (controller.assetMethod == AssetMethod.depreciate) ...[
                TextFormField(
                    controller: controller.years,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Useful life (years)', prefixIcon: Icon(Icons.timelapse)),
                    validator: controller.validateYears),
                const SizedBox(height: 12),
                TextFormField(
                    controller: controller.residual,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Residual value (% of price)', prefixIcon: Icon(Icons.percent)),
                    validator: controller.validateResidual),
              ],
              const SizedBox(height: 18),
              const SectionTitle('Alerts'),
              const SizedBox(height: 10),
              TextFormField(
                  controller: controller.mortality,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'High mortality: % of a group lost in 7 days', prefixIcon: Icon(Icons.heart_broken_outlined)),
                  validator: controller.validatePercent),
              const SizedBox(height: 12),
              TextFormField(
                  controller: controller.lowMilk,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Low milk: below % of the animal’s usual yield', prefixIcon: Icon(Icons.trending_down)),
                  validator: controller.validatePercent),
              const SizedBox(height: 18),
              const SectionTitle('Owner approval & budget'),
              const SizedBox(height: 6),
              const Text('A manager’s expense or purchase above the limit waits for your approval and is not counted until you approve it. Enter 0 for no limit.',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 10),
              TextFormField(
                  controller: controller.approvalLimit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Approval needed above (amount)', prefixIcon: Icon(Icons.approval_outlined)),
                  validator: controller.validateMoney),
              const SizedBox(height: 12),
              TextFormField(
                  controller: controller.budget,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monthly expense budget (0 = none)', prefixIcon: Icon(Icons.savings_outlined)),
                  validator: controller.validateMoney),
              const SizedBox(height: 18),
              const Text('Shared farm-wide costs are allocated by the method chosen on each expense (equal, head count, feed cost or production value). Reports always show the method used.',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 18),
              SizedBox(height: 50, child: FilledButton.icon(onPressed: controller.busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Save settings'))),
            ]),
          ),
        ),
      );
}

/// Owner only: production review thresholds, reminder timing and the default
/// veterinarian used to pre-fill illness forms.
class HealthSettingsPage extends StatefulWidget {
  const HealthSettingsPage({super.key});

  @override
  State<HealthSettingsPage> createState() => _HealthSettingsPageState();
}

class _HealthSettingsPageState extends State<HealthSettingsPage> {
  final controller = HealthSettingsController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await controller.save();
    if (!ok || !mounted) return;
    showToast(context, 'Health settings saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    TextFormField field(TextEditingController c, String label, String? Function(String?) validator, {String? helper, TextInputType type = TextInputType.number}) => TextFormField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
          validator: validator,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Health settings')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Form(
          key: controller.formKey,
          child: ListView(padding: const EdgeInsets.all(18), children: [
            const SectionTitle('Production review'),
            const SizedBox(height: 4),
            const Text('An animal is flagged for review when its recent average falls below these levels of its own earlier average. A drop is not proof of illness.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 10),
            field(controller.milk, 'Milk review level (%)', controller.validatePercent),
            const SizedBox(height: 10),
            field(controller.feed, 'Feed intake review level (%)', controller.validatePercent),
            const SizedBox(height: 10),
            field(controller.recent, 'Recent window (days)', controller.validateDays, helper: 'Days averaged as “recent”'),
            const SizedBox(height: 10),
            field(controller.baseline, 'Normal level window (days)', controller.validateDays, helper: 'Days before the recent window used as the animal’s normal level'),
            const SizedBox(height: 18),
            const SectionTitle('Reminders'),
            const SizedBox(height: 10),
            field(controller.lead, 'Remind this many days ahead', controller.validateLead, helper: 'Follow-ups, vet appointments and scheduled doses (0 = on the day)'),
            const SizedBox(height: 10),
            field(controller.recovered, 'Show “Recovered” for (days)', controller.validateDays, helper: 'After this, a recovered animal shows as Healthy'),
            const SizedBox(height: 18),
            const SectionTitle('Default veterinarian'),
            const SizedBox(height: 10),
            field(controller.vetName, 'Name', (_) => null, type: TextInputType.name),
            const SizedBox(height: 10),
            field(controller.vetPhone, 'Phone', controller.validatePhone, type: TextInputType.phone, helper: 'Used for the “Call vet” button when a case has no number'),
            const SizedBox(height: 18),
            const Text('Reminders appear in the app (Notifications and the Animal Health dashboard). They are not phone notifications while the app is closed.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 18),
            SizedBox(height: 50, child: FilledButton.icon(onPressed: controller.busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Save settings'))),
          ]),
        ),
      ),
    );
  }
}
