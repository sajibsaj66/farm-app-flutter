import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/ui_feedback.dart';
import '../../services/phone_service.dart';

/// "Call vet" — shown only when the number is valid and the device has a
/// dialer. Otherwise offers to copy the number (when there is one).
class CallVetButton extends StatefulWidget {
  const CallVetButton({super.key, required this.phone, this.emergency = false});

  final String phone;
  final bool emergency;

  @override
  State<CallVetButton> createState() => _CallVetButtonState();
}

class _CallVetButtonState extends State<CallVetButton> {
  bool? _canCall;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(CallVetButton old) {
    super.didUpdateWidget(old);
    if (old.phone != widget.phone) _check();
  }

  Future<void> _check() async {
    final ok = await PhoneService.canCall(widget.phone);
    if (mounted) setState(() => _canCall = ok);
  }

  @override
  Widget build(BuildContext context) {
    final number = PhoneService.normalise(widget.phone);
    if (number == null) {
      return const Text('No valid veterinarian phone number recorded. Add one to the case or in Health settings.', style: TextStyle(fontSize: 12));
    }
    if (_canCall == true) {
      final style = widget.emergency ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)) : null;
      return FilledButton.icon(
        style: style,
        onPressed: () async {
          final ok = await PhoneService.call(number);
          if (!ok && context.mounted) showToast(context, 'Could not open the phone dialer. Call $number directly.');
        },
        icon: const Icon(Icons.call),
        label: Text('Call vet · $number'),
      );
    }
    return OutlinedButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: number));
        if (context.mounted) showToast(context, 'Number copied: $number');
      },
      icon: const Icon(Icons.copy, size: 18),
      label: Text(_canCall == null ? 'Vet: $number' : 'Copy vet number · $number'),
    );
  }
}
