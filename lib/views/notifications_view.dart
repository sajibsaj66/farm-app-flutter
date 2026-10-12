import 'package:flutter/material.dart';

import '../controllers/notifications_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/ui_feedback.dart';
import '../models/alert_item.dart';
import 'widgets/common_widgets.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.onOpenSection});

  final ValueChanged<String> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final c = NotificationsController();
    return ListenableBuilder(
      listenable: Listenable.merge([c.farm, c.alerts]),
      builder: (context, _) {
        final reminders = c.reminders;
        return ListView(padding: const EdgeInsets.all(18), children: [
          const PageHeading(title: 'Notifications', subtitle: 'Reminders worked out from your farm records, plus recent actions.'),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: SectionTitle('Reminders (${reminders.length})')),
            if (reminders.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await c.markAllRead();
                  if (context.mounted) showToast(context, 'All reminders marked as read');
                },
                child: const Text('Mark all read'),
              ),
          ]),
          const SizedBox(height: 8),
          if (reminders.isEmpty) const EmptyHint('You are all caught up. New reminders appear when stock runs low, a follow-up is due, or a payment is outstanding.'),
          ...reminders.map((a) => _ReminderCard(
                alert: a,
                onOpen: a.module == null ? null : () => onOpenSection(a.module!),
                onRead: () async {
                  await c.markRead(a);
                  if (context.mounted) showToast(context, 'Marked as read');
                },
              )),
          if (c.readCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: c.showReadAgain, icon: const Icon(Icons.restore, size: 18), label: Text('Show ${c.readCount} read reminder${c.readCount == 1 ? '' : 's'} again')),
            ),
          const SizedBox(height: 18),
          const SectionTitle('Recent activity'),
          const SizedBox(height: 8),
          if (c.recentActivity.isEmpty) const EmptyHint('Changes made in the app will appear here.'),
          ...c.recentActivity.map((e) => IconListCard(icon: Icons.history, title: e.title, subtitle: e.subtitle)),
        ]);
      },
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.alert, required this.onRead, this.onOpen});

  final AlertItem alert;
  final VoidCallback onRead;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 9),
        child: ListTile(
          onTap: onOpen,
          leading: CircleAvatar(
            backgroundColor: alert.tone == AlertTone.warning ? const Color(0xFFFFEBD9) : AppColors.brandSoft,
            child: Icon(alert.icon, color: alert.tone == AlertTone.warning ? const Color(0xFFB45309) : AppColors.brand),
          ),
          title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(alert.module == null ? alert.message : '${alert.message}\nTap to open ${alert.module}'),
          isThreeLine: alert.module != null,
          trailing: IconButton(tooltip: 'Mark read', icon: const Icon(Icons.check_circle_outline), onPressed: onRead),
        ),
      );
}
