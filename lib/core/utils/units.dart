/// Units used for feed, production and sales, and conversion between units
/// of the same kind (kg ↔ g, L ↔ ml, pcs ↔ dozen).
class Units {
  Units._();

  static const feedUnits = ['kg', 'g', 'L', 'ml', 'piece', 'bundle', 'bag'];

  /// Units offered in forms. Older units (dozen, tray, birds) are still
  /// converted when read from saved records.
  static const productUnits = ['L', 'ml', 'kg', 'g', 'pcs', 'head'];

  /// unit → (base unit, factor to convert into the base unit).
  static const _toBase = <String, (String, double)>{
    'kg': ('kg', 1),
    'g': ('kg', 0.001),
    'gram': ('kg', 0.001),
    'l': ('L', 1),
    'liter': ('L', 1),
    'litre': ('L', 1),
    'ml': ('L', 0.001),
    'pcs': ('pcs', 1),
    'piece': ('pcs', 1),
    'egg': ('pcs', 1),
    'eggs': ('pcs', 1),
    'dozen': ('pcs', 12),
    'tray': ('pcs', 30),
    'head': ('head', 1),
    'birds': ('head', 1),
    'fish': ('head', 1),
  };

  static (String, double)? _lookup(String unit) => _toBase[unit.trim().toLowerCase()];

  /// The base unit for [unit] (kg, L, pcs, head), or the unit itself.
  static String baseOf(String unit) => _lookup(unit)?.$1 ?? unit.trim();

  static bool compatible(String a, String b) => baseOf(a).toLowerCase() == baseOf(b).toLowerCase();

  /// [qty] in [unit] expressed in its base unit.
  static double toBase(double qty, String unit) => qty * (_lookup(unit)?.$2 ?? 1);

  /// Converts [qty] from [from] to [to]; null when the units are not compatible.
  static double? convert(double qty, String from, String to) {
    if (from.trim().toLowerCase() == to.trim().toLowerCase()) return qty;
    final a = _lookup(from);
    final b = _lookup(to);
    if (a == null || b == null || a.$1 != b.$1) return null;
    return qty * a.$2 / b.$2;
  }

  /// Weight in kg, or null when [unit] is not a weight.
  static double? kg(double qty, String unit) => convert(qty, unit, 'kg');
}
