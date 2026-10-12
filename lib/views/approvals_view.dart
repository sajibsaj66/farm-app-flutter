import 'package:flutter/material.dart';

import '../controllers/approvals_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/ui_feedback.dart';
import '../models/farm_module.dart';
import 'record_form_view.dart';
import 'widgets/common_widgets.dart';

/// Farm Owner: approve or reject large expenses, purchases and managers'
/// requests, and review managers' reports. Farm Manager: see what is waiting
/// for the owner and what the owner decided.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final controller = ApprovalsController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _decide(ApprovalItem item, {required bool approve}) async {
    final note = TextEditingController();
    final verb = item.isReport ? 'Mark reviewed' : (approve ? 'Approve' : 'Reject');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$verb?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (item.amount != null) Text(controller.money(item.amount!)),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(labelText: item.isReport ? 'Comment for the manager (optional)' : (approve ? 'Note (optional)' : 'Reason (required)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(verb)),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok != true) return;
    final error = await controller.decide(item, approve: approve, note: text);
    if (mounted) showToast(context, error ?? (item.isReport ? 'Report reviewed' : (approve ? 'Approved' : 'Rejected')));
  }

  void _open(ApprovalItem item) => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(module: item.module, existing: item.record)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.farm]),
        builder: (context, _) {
          final pending = controller.pending;
          final decided = controller.decided();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
            const Text('Approvals', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
            Text(
              controller.canDecide
                  ? 'Large expenses and purchases from managers (above ${controller.money(controller.farm.profile.approvalLimit)}), requests and reports wait here for you.'
                  : 'What is waiting for the owner, and the owner’s decisions on your requests and reports.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            SectionTitle('Waiting for the owner (${pending.length})'),
            const SizedBox(height: 6),
            if (pending.isEmpty) const EmptyHint('Nothing is waiting.'),
            for (final item in pending)
              _ItemCard(
                item: item,
                money: controller.money,
                onOpen: () => _open(item),
                actions: !controller.canDecide
                    ? const []
                    : item.isReport
                        ? [FilledButton.icon(onPressed: () => _decide(item, approve: true), icon: const Icon(Icons.done_all, size: 18), label: const Text('Mark reviewed'))]
                        : [
                            OutlinedButton.icon(onPressed: () => _decide(item, approve: false), icon: const Icon(Icons.close, size: 18, color: AppColors.danger), label: const Text('Reject')),
                            FilledButton.icon(onPressed: () => _decide(item, approve: true), icon: const Icon(Icons.check, size: 18), label: const Text('Approve')),
                          ],
              ),
            const SizedBox(height: 18),
            const SectionTitle('Recently decided'),
            const SizedBox(height: 6),
            if (decided.isEmpty) const EmptyHint('No decisions yet.'),
            for (final item in decided) _ItemCard(item: item, money: controller.money, onOpen: () => _open(item), actions: const []),
          ]);
        },
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.money, required this.onOpen, required this.actions});

  final ApprovalItem item;
  final String Function(double) money;
  final VoidCallback onOpen;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (item.status) {
      'Approved' || 'Reviewed' => (AppColors.positiveSoft, AppColors.positive),
      'Rejected' => (AppColors.dangerSoft, AppColors.danger),
      _ => (AppColors.warningSoft, AppColors.warning),
    };
    final note = '${item.record[item.isReport ? 'ownerComment' : 'decisionNote'] ?? ''}'.trim();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.inputBorder)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(FarmModule.recordIconFor(item.module), color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(item.detail, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (item.amount != null) Text(money(item.amount!), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                  if (note.isNotEmpty) Text('Owner: $note', style: const TextStyle(fontSize: 12, color: AppColors.navy)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Text(item.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}
