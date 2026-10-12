import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/company.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/ui_feedback.dart';
import '../../services/link_service.dart';
import '../../services/phone_service.dart';

/// DeshIT-BD contact details. Each opens the matching app; when the device
/// cannot (no browser, dialer or mail app), the detail is copied instead.
class CompanyCard extends StatelessWidget {
  const CompanyCard({super.key, this.compact = false});

  /// One line of text links (sign-in screen) instead of a card.
  final bool compact;

  Future<void> _go(BuildContext context, Future<bool> Function() open, String copyText) async {
    if (await open()) return;
    await Clipboard.setData(ClipboardData(text: copyText));
    if (context.mounted) showToast(context, 'Copied: $copyText');
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      (Icons.language, Company.websiteLabel, 'Website', () => _go(context, () => LinkService.website(Company.website), Company.websiteLabel)),
      (Icons.phone_outlined, Company.phone, 'Phone', () => _go(context, () => PhoneService.call(Company.phoneDial), Company.phone)),
      (Icons.chat_outlined, Company.phone, 'WhatsApp', () => _go(context, () => LinkService.website(Company.whatsApp), Company.phone)),
      (Icons.email_outlined, Company.email, 'Email', () => _go(context, () => LinkService.email(Company.email), Company.email)),
    ];
    if (compact) {
      return Column(children: [
        const Text('Developed by ${Company.name}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
          for (final (icon, text, label, onTap) in rows)
            if (label != 'Phone') TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label == 'WhatsApp' ? 'WhatsApp $text' : text, style: const TextStyle(fontSize: 12))),
        ]),
      ]);
    }
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Column(children: [
        const ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.orange, child: Icon(Icons.business, color: Colors.white)),
          title: Text(Company.name, style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Farm management software · Bangladesh'),
        ),
        for (final (icon, text, label, onTap) in rows) ...[
          const Divider(height: 1),
          ListTile(dense: true, leading: Icon(icon, color: AppColors.navy), title: Text(text), subtitle: Text(label), trailing: const Icon(Icons.open_in_new, size: 18), onTap: onTap),
        ],
      ]),
    );
  }
}
