/// A single row in any farm module (animal, milk entry, sale, ...).
///
/// Modules have different columns, so the fields are kept as an ordered map;
/// the getters below give views a uniform way to read the common bits.
class FarmRecord {
  FarmRecord(Map<String, dynamic> data) : data = Map<String, dynamic>.from(data);

  factory FarmRecord.fromJson(Map<String, dynamic> json) => FarmRecord(json);

  final Map<String, dynamic> data;

  String get id => '${data['id'] ?? ''}';

  dynamic operator [](String key) => data[key];

  Iterable<MapEntry<String, dynamic>> get entries => data.entries;

  Iterable<String> get keys => data.keys;

  /// The most human-friendly name for this record.
  String get title => '${data['name'] ?? data['animal'] ?? data['customer'] ?? data['item'] ?? data['description'] ?? data['group'] ?? data['id'] ?? 'Record'}';

  /// Short name used in confirmation dialogs.
  String get shortLabel => '${data['name'] ?? data['animal'] ?? data['id']}';

  String get status => '${data['status'] ?? data['result'] ?? data['quality'] ?? ''}';

  bool get needsAttention {
    final s = status.toLowerCase();
    return s.contains('low') || s.contains('out of') || s.contains('due') || s.contains('follow');
  }

  /// "AN-1004 · Moti" → "Moti"; plain names are returned unchanged.
  static String displayName(dynamic reference) {
    final text = '${reference ?? ''}';
    final i = text.indexOf('·');
    return i < 0 ? text.trim() : text.substring(i + 1).trim();
  }

  /// "AN-1004 · Moti" → "an-1004": the id part of a reference, lower-cased,
  /// so references match regardless of the name that follows.
  static String refId(dynamic reference) {
    final text = '${reference ?? ''}';
    final i = text.indexOf('·');
    return (i < 0 ? text : text.substring(0, i)).trim().toLowerCase();
  }

  /// Whether [reference] (e.g. "AN-1001 · Shona") points at this record.
  bool isReferencedBy(dynamic reference) => id.isNotEmpty && refId(reference) == id.toLowerCase();

  /// "AN-1001 · Shona" — how other records refer to this one.
  String get reference => '$id · ${data['name'] ?? ''}'.trim();

  /// The leading number in values such as "150 kg" or "12.5".
  static double? leadingNumber(dynamic value) {
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)').firstMatch('${value ?? ''}');
    return m == null ? null : double.parse(m.group(1)!);
  }

  static DateTime? parseDate(dynamic value) => DateTime.tryParse('${value ?? ''}'.trim());

  double number(String field) => leadingNumber(data[field]) ?? 0;

  DateTime? dateOf(String field) => parseDate(data[field]);

  /// Inventory: at or below the reorder level (falls back to the status text).
  bool get isLowStock {
    final qty = leadingNumber(data['qty']);
    final reorder = leadingNumber(data['reorder']);
    if (qty != null && reorder != null) return qty <= reorder;
    final s = status.toLowerCase();
    return s.contains('low') || s.contains('out of');
  }

  bool matches({required String query, required String filter}) {
    // Internal bookkeeping fields (prefixed "_") are never shown, so they are not searched.
    final text = data.entries.where((e) => !e.key.startsWith('_')).map((e) => e.value).join(' ').toLowerCase();
    final matchesQuery = text.contains(query.toLowerCase());
    return matchesQuery && (filter == 'All' || status.toLowerCase() == filter.toLowerCase());
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}
