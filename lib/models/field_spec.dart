/// How a record field is entered and validated in the add/edit form.
enum FieldType {
  text,

  /// A number, optionally followed by a unit ("420", "420 kg").
  number,
  date,
  phone,

  /// Pick one of [FieldSpec.options].
  choice,

  /// Pick an animal from the Animals register.
  animal,

  /// Pick a customer from the Customers list.
  customer,

  /// Pick a semen batch from Semen Inventory.
  semen,

  /// Pick a feed item from Inventory (category Feed).
  feedItem,

  /// Pick any item from Inventory.
  inventoryItem,

  /// Pick a species from Species & Categories.
  species,

  /// Pick a shed, pen, pond or other location.
  location,

  /// Pick a poultry flock, fish pond or other batch.
  batch,

  /// Pick a sale that still has money outstanding.
  sale,

  /// Date and time, stored as `YYYY-MM-DD HH:mm`.
  dateTime,

  /// Any number of [FieldSpec.options], stored separated by `; `.
  multiChoice,

  /// Pick an illness case.
  illness,

  /// Pick a treatment plan.
  treatment,

  /// Pick a staff member from Staff.
  staff,
}

class FieldSpec {
  const FieldSpec(
    this.key, {
    this.type = FieldType.text,
    this.options = const [],
    this.required = true,
    this.label,
    this.hint,
    this.computed = false,
    this.lockedOnEdit = false,
    this.ownerOnly = false,
  });

  final String key;
  final FieldType type;
  final List<String> options;
  final bool required;

  /// Display label; defaults to the key in title case.
  final String? label;

  /// Helper text shown under the field.
  final String? hint;

  /// Worked out by the app when the record is saved; shown read-only.
  final bool computed;

  /// Can be set when the record is created but not changed afterwards
  /// (e.g. stock quantity, which then only changes through transactions).
  final bool lockedOnEdit;

  /// Only the Farm Owner sets this (e.g. an approval decision). Others see it
  /// read-only, and [FarmController] refuses a change from anyone else.
  final bool ownerOnly;
}
