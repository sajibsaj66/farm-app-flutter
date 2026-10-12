import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, required String confirmLabel}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok == true;
}

Future<void> confirmSignOut(BuildContext context) async {
  final ok = await confirmDialog(context, title: 'Sign out?', message: 'You will need your username and password to sign in again.', confirmLabel: 'Sign out');
  if (!ok) return;
  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  await AuthController.instance.logout();
}
