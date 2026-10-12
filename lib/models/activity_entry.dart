class ActivityEntry {
  const ActivityEntry({required this.title, required this.time, this.by});

  factory ActivityEntry.now(String title, {String? by}) => ActivityEntry(title: title, time: DateTime.now().toIso8601String(), by: by);

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(title: '${json['title']}', time: '${json['time']}', by: json['by'] as String?);

  final String title;

  /// ISO-8601 timestamp, stored as text so the saved format never changes.
  final String time;

  /// Name of the user who made the change (null for older entries).
  final String? by;

  String get displayTime => time.replaceFirst('T', ' ').split('.').first;

  String get subtitle => by == null ? displayTime : '$displayTime · $by';

  Map<String, dynamic> toJson() => {'title': title, 'time': time, if (by != null) 'by': by};
}
