import 'package:flutter/material.dart';

enum AlertTone { warning, info }

/// A reminder or notice shown on the dashboard and notifications screen.
class AlertItem {
  const AlertItem({required this.id, required this.title, required this.message, required this.icon, this.module, this.tone = AlertTone.info});

  /// Stable id, so a dismissed alert stays dismissed until its data changes.
  final String id;
  final String title;
  final String message;
  final IconData icon;

  /// The section that resolves this alert, if any.
  final String? module;
  final AlertTone tone;
}
