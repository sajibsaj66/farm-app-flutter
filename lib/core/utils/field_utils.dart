import 'package:flutter/material.dart';

/// Turns a record key such as `reorder` or `farmName` into a display label.
String fieldLabel(String key) =>
    key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}').replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

IconData fieldIcon(String field) {
  final f = field.toLowerCase();
  if (f.contains('date') || f == 'next') return Icons.calendar_today_outlined;
  if (f.contains('animal') || f.contains('breed') || f.contains('bull')) return Icons.pets_outlined;
  if (f.contains('amount') || f.contains('balance') || f.contains('payment')) return Icons.payments_outlined;
  if (f.contains('phone')) return Icons.phone_outlined;
  if (f.contains('status') || f.contains('result')) return Icons.flag_outlined;
  if (f.contains('qty') || f.contains('litre') || f.contains('weight')) return Icons.scale_outlined;
  return Icons.edit_note_outlined;
}
