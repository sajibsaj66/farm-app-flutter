/// Dates are stored as `YYYY-MM-DD` text throughout the app.
String formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [from] to [to] (negative if [to] is earlier).
int daysBetween(DateTime from, DateTime to) => dateOnly(to).difference(dateOnly(from)).inDays;

/// Formats a quantity without trailing zeros: 12 → "12", 12.5 → "12.5".
String formatQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
