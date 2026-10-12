import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/dates.dart';
import '../core/utils/units.dart';
import '../data/demo_activity.dart';
import '../data/demo_data.dart';
import '../models/access_policy.dart';
import '../models/activity_entry.dart';
import '../models/farm_module.dart';
import '../models/farm_profile.dart';
import '../models/farm_record.dart';
import '../models/field_spec.dart';
import '../services/local_storage_service.dart';
import 'health_rules.dart';

/// A write that would break a farm rule (negative stock, selling more than is
/// produced, deleting a record other records depend on…). Nothing is changed.
class FarmRuleException implements Exception {
  const FarmRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// App-wide source of truth (the repository) for farm records, the farm
/// profile and the activity log.
///
/// Every write goes through [add], [update] or [remove]. They:
///  1. fill in calculated fields ([_prepare]),
///  2. check integrity rules and throw [FarmRuleException] when broken,
///  3. keep linked records in step — feed issues and stock transactions,
///     semen straws, animal weight, Sold/Dead status, sale payments — so an
///     edit or delete reverses exactly what the original write did.
class FarmController extends ChangeNotifier {
  FarmController(this._storage, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static final FarmController instance = FarmController(LocalStorageService.instance);

  static const activityLimit = 200;
  static const backupVersion = 1;
  static const dataVersion = 4;
  static const _dataVersionKey = 'data_version';
  static const _autoBackupKey = 'auto_backup_before_reset';

  /// Version of the demo farm. 2: at least 10 demo records on every screen,
  /// plus a demo activity log. 3: livestock only (no poultry, fish or bees).
  /// 4: staff, daily tasks, requests, managers' reports and approvals.
  static const demoDataVersion = 4;
  static const _demoVersionKey = 'demo_data_version';

  final LocalStorageService _storage;
  final DateTime Function() _clock;
  final Map<String, List<FarmRecord>> _records = {};
  final List<ActivityEntry> _activity = [];

  bool ready = false;
  FarmProfile _profile = FarmProfile.defaults;
  Map<String, List<Map<String, dynamic>>>? _demo;

  /// Returns the name of whoever is making changes, for the activity log.
  String? Function() actor = () => null;

  /// The signed-in user's rights. When set (the app sets it), every write is
  /// checked here — not only hidden in the screens — and refused with a
  /// [FarmRuleException] when not allowed. Left null for headless use.
  AccessPolicy Function()? access;

  void _authorize(bool Function(AccessPolicy a) allowed, String what) {
    final a = access?.call();
    if (a == null || allowed(a)) return;
    final who = a.role?.label ?? 'Signed-out user';
    throw FarmRuleException('$who cannot $what. Ask the farm owner.');
  }

  void _authorizeWrite(String module) => _authorize((a) => a.canEditModule(module), 'change $module');

  DateTime get today => dateOnly(_clock());

  Map<String, List<Map<String, dynamic>>> get defaults => _demo ??= buildDemoRecords(_clock());

  List<String> get modules => FarmModule.all.map((m) => m.name).toList();

  List<ActivityEntry> get activity => List.unmodifiable(_activity);

  FarmProfile get profile => _profile;

  // ---------------------------------------------------------------------------
  // Loading and migration

  Future<void> init() async {
    await _storage.init();
    _records.clear();
    _activity.clear();
    final existingInstall = _storage.hasSavedRecords;
    for (final module in modules) {
      final saved = _storage.readRecords(module);
      // A fresh install gets the full demo farm. An existing install only gets
      // configuration (species, locations) for new modules — never demo
      // activity mixed into real data.
      final seed = !existingInstall || configurationModules.contains(module) ? (defaults[module] ?? const []) : const <Map<String, dynamic>>[];
      _records[module] = (saved ?? seed).map(FarmRecord.fromJson).toList();
      if (saved == null && existingInstall) await _persist(module);
      if (_repairIds(module) > 0) await _persist(module);
    }
    _activity.addAll(_storage.readActivity().map(ActivityEntry.fromJson));
    final savedProfile = _storage.readProfile();
    _profile = savedProfile == null ? FarmProfile.defaults : FarmProfile.fromJson(savedProfile);
    if (existingInstall) {
      await _migrate();
      await _upgradeDemo();
    } else {
      // Fresh install: save every module now. Otherwise modules the user never
      // edits would not be in storage, and the next start (seeing an existing
      // install) would bring them back empty.
      await _recalculateDemo();
      await _persistAll(modules.toSet());
      if (_activity.isEmpty) await _seedDemoActivity();
    }
    await _storage.writeValue(_dataVersionKey, '$dataVersion');
    for (final (key, keptAs) in _storage.unreadable) {
      await log('Saved data "$key" could not be read. It was kept unchanged as "$keptAs" and the app continued without it.');
    }
    _storage.unreadable.clear();
    if (_storage.migratedFromPreferences > 0) {
      await log('Saved data moved to Hive local storage (${_storage.migratedFromPreferences} items copied unchanged)');
      _storage.migratedFromPreferences = 0;
    }
    ready = true;
    notifyListeners();
  }

  /// Records saved without an id (damaged data) get one, so they stay usable
  /// and nothing is dropped.
  int _repairIds(String module) {
    var fixed = 0;
    final rows = list(module);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id.isEmpty) {
        rows[i] = FarmRecord({...rows[i].toJson(), 'id': 'REPAIRED-${i + 1}-${DateTime.now().microsecondsSinceEpoch}'});
        fixed++;
      }
    }
    return fixed;
  }

  /// Seed records skip [add], so run their calculated fields through the same
  /// rules as user entries (sale totals include later payments; illness
  /// stages and animal health status come from the health records).
  Future<void> _recalculateDemo() async {
    final sales = list(FarmModule.sales);
    for (var i = 0; i < sales.length; i++) {
      sales[i] = FarmRecord(_prepare(FarmModule.sales, sales[i].toJson(), sales[i]));
    }
    await _persist(FarmModule.sales);
    final touched = <String>{};
    for (final c in [...list(FarmModule.illness)]) {
      _syncIllness(c.id, touched);
    }
    _syncAllAnimalHealth(touched);
    await _persistAll(touched);
  }

  /// Brings records saved by earlier versions up to the current fields,
  /// without losing anything.
  Future<void> _migrate() async {
    final from = int.tryParse(_storage.readValue(_dataVersionKey) ?? '') ?? 1;
    if (from >= dataVersion) return;
    var changed = 0;
    void fix(String module, Map<String, dynamic> Function(Map<String, dynamic>) f) {
      final rows = list(module);
      for (var i = 0; i < rows.length; i++) {
        final before = jsonEncode(rows[i].data);
        final after = f(rows[i].toJson());
        if (jsonEncode(after) != before) {
          rows[i] = FarmRecord(after);
          changed++;
        }
      }
    }

    fix(FarmModule.animals, (a) {
      if ('${a['species'] ?? ''}'.isEmpty) {
        final type = '${a['type']}'.toLowerCase();
        a['species'] = type == 'goat' ? 'Goat' : (type == 'sheep' ? 'Sheep' : 'Cattle');
      }
      return a;
    });
    fix(FarmModule.feedRecords, (f) {
      final item = feedItem(f['feed']);
      f['source'] = '${f['source'] ?? ''}'.isEmpty ? FarmModule.fromInventory : f['source'];
      if ('${f['unit'] ?? ''}'.isEmpty) f['unit'] = '${item?['unit'] ?? 'kg'}';
      if ('${f['unitPrice'] ?? ''}'.isEmpty) f['unitPrice'] = formatQty(item?.number('unitCost') ?? 0);
      f['qty'] = formatQty(FarmRecord.leadingNumber(f['qty']) ?? 0);
      return _prepare(FarmModule.feedRecords, f, null);
    });
    fix(FarmModule.sales, (s) {
      final qty = FarmRecord.leadingNumber(s['qty']) ?? 1;
      final amount = FarmRecord.leadingNumber(s['amount']) ?? 0;
      if ('${s['unitPrice'] ?? ''}'.isEmpty) {
        s['unit'] = '${s['unit'] ?? ''}'.isNotEmpty ? s['unit'] : (RegExp(r'\bL\b').hasMatch('${s['qty']}') ? 'L' : 'pcs');
        s['qty'] = formatQty(qty <= 0 ? 1 : qty);
        s['unitPrice'] = (amount / (qty <= 0 ? 1 : qty)).toStringAsFixed(2);
      }
      if ('${s['product'] ?? ''}'.isEmpty) s['product'] = '${s['item']}'.toLowerCase().contains('milk') ? 'Milk' : 'Other';
      if ('${s['paidAtSale'] ?? ''}'.isEmpty) s['paidAtSale'] = s['status'] == 'Paid' ? formatQty(amount) : '0';
      return _prepare(FarmModule.sales, s, null);
    });
    fix(FarmModule.expenses, (e) {
      if ('${e['scope'] ?? ''}'.isEmpty) e['scope'] = FarmModule.scopeFarm;
      if ('${e['allocation'] ?? ''}'.isEmpty) e['allocation'] = FarmModule.allocNone;
      return e;
    });
    // Give every stock item an opening transaction so its history adds up.
    final tx = list(FarmModule.inventoryTx);
    for (final item in list(FarmModule.inventory)) {
      if (tx.any((t) => '${t['item']}' == '${item['name']}')) continue;
      tx.add(FarmRecord({
        'id': 'TX-OPEN-${item.id}',
        'date': formatDate(today),
        'item': item['name'],
        'type': FarmModule.txOpening,
        'quantity': formatQty(item.number('qty')),
        'unitCost': '${item['unitCost'] ?? ''}',
        'reference': 'Balance when upgraded',
        'notes': ''
      }));
      changed++;
    }
    // Version 4: every animal gets a health status (from its illness cases).
    final healthTouched = <String>{};
    _syncAllAnimalHealth(healthTouched);
    if (healthTouched.isNotEmpty) changed += list(FarmModule.animals).length;
    for (final m in modules) {
      await _persist(m);
    }
    if (changed > 0) await log('Data upgraded to version $dataVersion ($changed records updated)');
  }

  // ---------------------------------------------------------------------------
  // Queries

  List<FarmRecord> list(String module) => _records[module] ?? [];

  FarmRecord? find(String module, String id) {
    for (final r in list(module)) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The record a reference such as "AN-1001 · Shona" points at.
  FarmRecord? resolve(String module, dynamic reference) {
    final key = FarmRecord.refId(reference);
    if (key.isEmpty) return null;
    for (final r in list(module)) {
      if (r.id.toLowerCase() == key) return r;
    }
    return null;
  }

  /// Records of [module] dated between [from] and [to] (inclusive).
  List<FarmRecord> inRange(String module, DateTime from, DateTime to, {String field = 'date'}) => list(module).where((r) {
        final d = r.dateOf(field);
        return d != null && !dateOnly(d).isBefore(dateOnly(from)) && !dateOnly(d).isAfter(dateOnly(to));
      }).toList();

  int count(String module) => list(module).length;

  double sum(String module, String field, {bool Function(FarmRecord)? where}) => list(module).where(where ?? (_) => true).fold(0.0, (s, r) => s + r.number(field));

  FarmRecord? byName(String module, dynamic name) {
    final key = '${name ?? ''}'.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final r in list(module)) {
      if ('${r['name']}'.trim().toLowerCase() == key) return r;
    }
    return null;
  }

  FarmRecord? feedItem(dynamic name) => byName(FarmModule.inventory, name);

  FarmRecord? species(dynamic name) => byName(FarmModule.species, name);

  FarmRecord? semenByCode(dynamic code) {
    final key = '${code ?? ''}'.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final s in list(FarmModule.semen)) {
      if ('${s['code']}'.trim().toLowerCase() == key) return s;
    }
    return null;
  }

  static bool isActive(FarmRecord r) => !FarmModule.inactiveStatuses.contains(r.status.toLowerCase());

  /// Species categories of earlier versions that are not livestock.
  static const nonLivestockCategories = {'Poultry & birds', 'Fisheries & aquaculture', 'Other farm operations'};

  /// A species this livestock system works with (cattle, buffalo, goats,
  /// sheep…), tracked animal by animal.
  static bool isLivestockSpecies(FarmRecord s) => '${s['tracking']}' != FarmModule.trackBatch && !nonLivestockCategories.contains('${s['category']}');

  /// Head count of a batch on [asOf] (default today): opening count plus
  /// additions, minus transfers out, culling, deaths, birds/fish sold and
  /// harvested. [excludeId] leaves one record out (when it is being edited).
  double batchCount(dynamic batchRef, {DateTime? asOf, String? excludeId}) {
    final batch = resolve(FarmModule.batches, batchRef);
    if (batch == null) return 0;
    final until = dateOnly(asOf ?? today);
    bool mine(FarmRecord r) => r.id != excludeId && batch.isReferencedBy(r['batch']) && !(r.dateOf('date')?.isAfter(until) ?? false);
    var n = batch.number('initialCount');
    for (final m in list(FarmModule.batchMovements).where(mine)) {
      final q = m.number('quantity');
      n += FarmModule.movementAdds.contains('${m['type']}') ? q : -q;
    }
    n -= list(FarmModule.mortality).where(mine).fold(0.0, (s, r) => s + r.number('count'));
    n -= list(FarmModule.sales).where(mine).fold(0.0, (s, r) => s + r.number('headCount'));
    n -= list(FarmModule.production).where(mine).fold(0.0, (s, r) => s + r.number('headCount'));
    return n;
  }

  /// Products whose unsold stock is tracked (produced − sold − used).
  static const stockedProducts = {'Milk', 'Eggs', 'Meat', 'Fish', 'Shrimp', 'Honey', 'Wool', 'Manure'};

  /// Saleable quantity of [product] produced up to [asOf], in its base unit.
  double producedSaleable(String product, {DateTime? asOf, String? batchRef}) {
    final until = dateOnly(asOf ?? today);
    bool upTo(FarmRecord r) => !(r.dateOf('date')?.isAfter(until) ?? true);
    bool inBatch(FarmRecord r) => batchRef == null || FarmRecord.refId(r['batch']) == FarmRecord.refId(batchRef);
    if (product == 'Milk') {
      if (batchRef != null) return 0;
      return list(FarmModule.milkProduction).where((m) => upTo(m) && isSellableMilk(m)).fold(0.0, (s, m) => s + m.number('litres'));
    }
    return list(FarmModule.production).where((p) => upTo(p) && inBatch(p) && '${p['product']}' == product).fold(0.0, (s, p) => s + Units.toBase(saleableOf(p), '${p['unit']}'));
  }

  static bool isSellableMilk(FarmRecord m) {
    final q = '${m['quality']}';
    return q != FarmModule.qualityWithheld && q != FarmModule.qualityRejected;
  }

  /// Saleable quantity of a production record (in its own unit).
  static double saleableOf(FarmRecord p) {
    if ('${p['saleable'] ?? ''}'.trim().isNotEmpty) return p.number('saleable');
    return p.number('quantity') - p.number('damaged');
  }

  /// Unsold stock of [product] in its base unit (L, pcs, kg…).
  double productStock(String product, {DateTime? asOf, String? excludeId, String? batchRef}) {
    final until = dateOnly(asOf ?? today);
    bool counts(FarmRecord r) =>
        r.id != excludeId && '${r['product']}' == product && !(r.dateOf('date')?.isAfter(until) ?? true) && (batchRef == null || FarmRecord.refId(r['batch']) == FarmRecord.refId(batchRef));
    final sold = list(FarmModule.sales).where(counts).fold(0.0, (s, r) => s + Units.toBase(r.number('qty'), '${r['unit']}'));
    final used = list(FarmModule.productUsage).where(counts).fold(0.0, (s, r) => s + Units.toBase(r.number('quantity'), '${r['unit']}'));
    var produced = producedSaleable(product, asOf: until, batchRef: batchRef);
    if (excludeId != null && product != 'Milk') {
      final p = find(FarmModule.production, excludeId);
      if (p != null && '${p['product']}' == product) produced -= Units.toBase(saleableOf(p), '${p['unit']}');
    }
    return produced - sold - used;
  }

  /// Total received for a sale: paid at sale plus later payments.
  double receivedFor(FarmRecord sale, {String? excludeCollectionId}) =>
      sale.number('paidAtSale') + list(FarmModule.collections).where((c) => c.id != excludeCollectionId && sale.isReferencedBy(c['sale'])).fold(0.0, (s, c) => s + c.number('amount'));

  // ---------------------------------------------------------------------------
  // Links between records

  /// Records that point at [record] — it cannot be deleted while these exist.
  List<(String, FarmRecord)> linksTo(String module, FarmRecord record) {
    final out = <(String, FarmRecord)>[];
    void scan(String m, List<String> fields, bool Function(dynamic v) matches) {
      for (final r in list(m)) {
        if (fields.any((f) => matches(r[f]))) out.add((m, r));
      }
    }

    bool byRef(dynamic v) => record.isReferencedBy(v);
    bool byName(dynamic v) => '${v ?? ''}'.trim().toLowerCase() == '${record['name']}'.trim().toLowerCase() && '${v ?? ''}'.trim().isNotEmpty;
    switch (module) {
      case FarmModule.animals:
        for (final m in modules) {
          scan(m, ['animal', 'dam'], byRef);
        }
      case FarmModule.batches:
        for (final m in modules) {
          scan(m, ['batch'], byRef);
        }
      case FarmModule.species:
        scan(FarmModule.animals, ['species'], byName);
        scan(FarmModule.batches, ['species'], byName);
      case FarmModule.locations:
        scan(FarmModule.animals, ['location'], byName);
        scan(FarmModule.batches, ['location'], byName);
        scan(FarmModule.expenses, ['location'], byName);
      case FarmModule.inventory:
        scan(FarmModule.feedRecords, ['feed'], byName);
        out.addAll(list(FarmModule.inventoryTx).where((t) => byName(t['item']) && '${t['type']}' != FarmModule.txOpening).map((t) => (FarmModule.inventoryTx, t)));
      case FarmModule.customers:
        scan(FarmModule.sales, ['customer'], byName);
      case FarmModule.staff:
        scan(FarmModule.tasks, ['assignedTo'], byName);
      case FarmModule.sales:
        scan(FarmModule.collections, ['sale'], byRef);
      case FarmModule.illness:
        for (final m in [FarmModule.consultations, FarmModule.treatments, FarmModule.followUps]) {
          scan(m, ['illness'], byRef);
        }
      case FarmModule.treatments:
        scan(FarmModule.medication, ['treatment'], byRef);
      case FarmModule.semen:
        scan(FarmModule.breeding, ['semen'], (v) => '${v ?? ''}'.trim().toLowerCase() == '${record['code']}'.trim().toLowerCase());
    }
    return out;
  }

  /// Modules whose records can be archived instead of deleted, and the status
  /// they get.
  static const archiveStatus = {
    FarmModule.staff: 'Inactive',
    FarmModule.animals: 'Archived',
    FarmModule.batches: 'Archived',
    FarmModule.species: 'Inactive',
    FarmModule.locations: 'Inactive',
    FarmModule.customers: 'Inactive',
  };

  // ---------------------------------------------------------------------------
  // Owner decisions

  /// The value an owner-only field starts with on a record someone else adds.
  static String _ownerOnlyDefault(String module, String field) => switch ((module, field)) {
        (FarmModule.requests, 'status') => 'Pending',
        (FarmModule.managerReports, 'status') => 'Submitted',
        _ => '',
      };

  /// Records waiting for the owner: large expenses and purchases, requests,
  /// and managers' reports not yet reviewed. (module, record), newest first.
  List<(String, FarmRecord)> get pendingDecisions => [
        for (final m in [FarmModule.expenses, FarmModule.purchases])
          for (final r in list(m).where((r) => '${r['approval']}' == FarmModule.approvalPending)) (m, r),
        for (final r in list(FarmModule.requests).where((r) => '${r['status']}' == 'Pending')) (FarmModule.requests, r),
        for (final r in list(FarmModule.managerReports).where((r) => '${r['status']}' != 'Reviewed')) (FarmModule.managerReports, r),
      ]..sort((a, b) => '${b.$2['date']}'.compareTo('${a.$2['date']}'));

  /// The owner approves or rejects a large expense, purchase or request, or
  /// marks a manager's report reviewed, with an optional note.
  Future<void> decide(String module, String id, {required bool approve, String note = ''}) async {
    _authorize((a) => a.canApprove, 'approve, reject or review');
    final r = find(module, id);
    if (r == null) throw FarmRuleException('This $module record no longer exists.');
    final data = r.toJson();
    final text = note.trim();
    final String what;
    switch (module) {
      case FarmModule.expenses || FarmModule.purchases:
        data['approval'] = approve ? FarmModule.approvalApproved : FarmModule.approvalRejected;
        if (text.isNotEmpty) data['decisionNote'] = text;
        what = approve ? 'approved' : 'rejected';
      case FarmModule.requests:
        data['status'] = approve ? 'Approved' : 'Rejected';
        if (text.isNotEmpty) data['decisionNote'] = text;
        what = approve ? 'approved' : 'rejected';
      case FarmModule.managerReports:
        data['status'] = 'Reviewed';
        if (text.isNotEmpty) data['ownerComment'] = text;
        what = 'reviewed';
      default:
        throw FarmRuleException('$module records do not need the owner\'s decision.');
    }
    if (!approve && text.isEmpty && module != FarmModule.managerReports) throw const FarmRuleException('Write a short reason for rejecting it.');
    await update(module, FarmRecord(data), activity: '$module $what · $id');
  }

  Future<void> archive(String module, FarmRecord record) async {
    _authorize((a) => a.canDelete, 'archive records');
    final status = archiveStatus[module];
    if (status == null) throw FarmRuleException('$module records cannot be archived.');
    await update(module, FarmRecord({...record.toJson(), 'status': status}), activity: '$module record archived · ${record.id}');
  }

  // ---------------------------------------------------------------------------
  // Writes

  /// Adds a record and returns it (with its new id).
  Future<FarmRecord> add(String module, Map<String, dynamic> fields, {String? activity}) async {
    _authorizeWrite(module);
    final id = '${fields['id'] ?? ''}'.isNotEmpty && find(module, '${fields['id']}') == null ? '${fields['id']}' : _newId(module);
    final stamp = DateTime.now().toIso8601String();
    final record = FarmRecord(_prepare(module, {...fields, 'id': id, '_createdAt': stamp, '_updatedAt': stamp}, null));
    _check(module, record, null);
    _records.putIfAbsent(module, () => []).insert(0, record);
    final touched = <String>{};
    await _effects(module, null, record, touched);
    await _persistAll({module, ...touched});
    await log(activity ?? 'New $module record added · $id');
    return find(module, id) ?? record;
  }

  Future<void> update(String module, FarmRecord record, {String? activity}) async {
    _authorizeWrite(module);
    final rows = list(module);
    final index = rows.indexWhere((r) => r.id == record.id);
    if (index < 0) throw FarmRuleException('This $module record no longer exists.');
    final before = rows[index];
    _guardSystemRecord(module, before, editing: true);
    final updated = FarmRecord(_prepare(
        module,
        {
          ...record.toJson(),
          // Creation time never changes; every edit is time-stamped.
          '_createdAt': before['_createdAt'] ?? record['_createdAt'] ?? '',
          '_updatedAt': DateTime.now().toIso8601String(),
        },
        before));
    _check(module, updated, before);
    rows[index] = updated;
    final touched = <String>{};
    await _effects(module, before, updated, touched);
    await _persistAll({module, ...touched});
    await log(activity ?? '$module record updated · ${record.id}');
  }

  Future<void> remove(String module, String id) async {
    _authorize((a) => a.canDelete, 'delete records');
    final rows = _records[module];
    final index = rows?.indexWhere((r) => r.id == id) ?? -1;
    if (rows == null || index < 0) return;
    final removed = rows[index];
    _guardSystemRecord(module, removed, editing: false);
    final links = linksTo(module, removed);
    if (links.isNotEmpty) {
      final archivable = archiveStatus.containsKey(module) ? ' Archive it instead to keep its history.' : '';
      throw FarmRuleException(
          '${removed.title} is used by ${links.length} other record${links.length == 1 ? '' : 's'} (e.g. ${links.first.$1} ${links.first.$2.id}), so it cannot be deleted.$archivable');
    }
    rows.removeAt(index);
    final touched = <String>{};
    await _effects(module, removed, null, touched);
    if (module == FarmModule.inventory) {
      list(FarmModule.inventoryTx).removeWhere((t) => '${t['item']}' == '${removed['name']}' && '${t['type']}' == FarmModule.txOpening);
      touched.add(FarmModule.inventoryTx);
    }
    await _persistAll({module, ...touched});
    await log('$module record deleted · $id');
  }

  void _guardSystemRecord(String module, FarmRecord r, {required bool editing}) {
    if (module != FarmModule.inventoryTx) return;
    final type = '${r['type']}';
    if (type == FarmModule.txIssue) throw FarmRuleException('This stock movement belongs to feed record ${r['reference']}. ${editing ? 'Edit' : 'Delete'} the feed record instead.');
    if (type == FarmModule.txTreatment) throw FarmRuleException('This stock movement belongs to medication record ${r['reference']}. ${editing ? 'Edit' : 'Delete'} that record instead.');
    if (type == FarmModule.txOpening) throw const FarmRuleException('The opening balance is part of the item’s history and cannot be changed. Use an adjustment or physical count instead.');
  }

  Future<void> updateProfile(FarmProfile profile) async {
    _authorize((a) => a.canManageSettings, 'change farm settings');
    _profile = profile;
    await _storage.writeProfile(profile.toJson());
    await log('Farm profile and calculation settings updated');
  }

  /// Adds an entry to the activity log (also used for user/account changes).
  Future<void> log(String title) async {
    _activity.insert(0, ActivityEntry.now(title, by: actor()));
    if (_activity.length > activityLimit) _activity.removeRange(activityLimit, _activity.length);
    await _storage.writeActivity(_activity.map((a) => a.toJson()).toList());
    notifyListeners();
  }

  /// Replaces all records with demo data. A full backup of the current data is
  /// saved first and can be restored from Backup & restore.
  Future<void> reset() async {
    _authorize((a) => a.canResetData, 'load demo data');
    await _reset();
  }

  Future<void> _reset() async {
    await _storage.writeValue(_autoBackupKey, jsonEncode(exportData()));
    _demo = buildDemoRecords(_clock());
    for (final module in modules) {
      _records[module] = (defaults[module] ?? const []).map(FarmRecord.fromJson).toList();
      await _persist(module);
    }
    await _recalculateDemo();
    await _seedDemoActivity();
    await log('Demo data loaded (previous data saved as an automatic backup)');
  }

  /// The demo farm's activity log (who recorded which demo record).
  Future<void> _seedDemoActivity() async {
    _activity
      ..clear()
      ..addAll(buildDemoActivity(defaults, _clock()).map(ActivityEntry.fromJson));
    await _storage.writeActivity(_activity.map((a) => a.toJson()).toList());
    await _storage.writeValue(_demoVersionKey, '$demoDataVersion');
  }

  /// An install made with an older, smaller demo set gets the current one —
  /// but only if nobody added or changed anything (so nothing real is lost,
  /// and a backup is still taken first). Otherwise the user is told how to
  /// load it, once.
  Future<void> _upgradeDemo() async {
    final from = int.tryParse(_storage.readValue(_demoVersionKey) ?? '') ?? 1;
    if (from >= demoDataVersion) return;
    await _storage.writeValue(_demoVersionKey, '$demoDataVersion');
    if (_isUntouchedDemo()) {
      await _reset();
      await log('Demo farm updated: every screen now has at least 10 demo records');
    } else {
      await log('New demo records are available. Settings → Reset demo data loads them (your current data is saved as an automatic backup first).');
    }
  }

  /// True when every saved record is an unedited record of the demo farm.
  bool _isUntouchedDemo() {
    var any = false;
    for (final m in modules) {
      final demoIds = {for (final r in defaults[m] ?? const <Map<String, dynamic>>[]) '${r['id']}'};
      for (final r in list(m)) {
        if ('${r['_createdAt'] ?? ''}'.isNotEmpty || '${r['_updatedAt'] ?? ''}'.isNotEmpty) return false;
        if (!demoIds.contains(r.id)) return false;
        if (m != FarmModule.species && m != FarmModule.locations) any = true;
      }
    }
    return any;
  }

  /// When the automatic backup taken before the last reset was made.
  DateTime? get autoBackupDate {
    final raw = _storage.readValue(_autoBackupKey);
    if (raw == null) return null;
    try {
      return DateTime.tryParse('${(jsonDecode(raw) as Map)['exportedAt']}');
    } on FormatException {
      return null;
    }
  }

  Future<void> restoreAutoBackup() async {
    final raw = _storage.readValue(_autoBackupKey);
    if (raw == null) throw const FarmRuleException('There is no automatic backup.');
    await restore(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  // ---------------------------------------------------------------------------
  // Calculated fields

  Map<String, dynamic> _prepare(String module, Map<String, dynamic> v, FarmRecord? before) {
    String s(String k) => '${v[k] ?? ''}'.trim();
    double n(String k) => FarmRecord.leadingNumber(v[k]) ?? 0;
    final unique = uniqueFields[module];
    if (unique != null && v[unique] != null) v[unique] = s(unique);
    final who = actor() ?? '';
    String was(String k) => '${before?[k] ?? ''}'.trim();
    switch (module) {
      case FarmModule.expenses || FarmModule.purchases:
        // A manager's entry above the owner's limit waits for approval (and is
        // not counted until approved). The owner's own entries need none.
        final byOwner = access?.call().isOwner ?? true;
        final limit = _profile.approvalLimit;
        final sameAmount = before != null && (before.number('amount') - n('amount')).abs() < 0.005;
        if (byOwner) {
          if (s('approval').isEmpty) v['approval'] = before == null ? FarmModule.approvalNotRequired : (was('approval').isEmpty ? FarmModule.approvalNotRequired : was('approval'));
        } else if (limit > 0 && n('amount') > limit) {
          v['approval'] = sameAmount && was('approval') == FarmModule.approvalApproved ? FarmModule.approvalApproved : FarmModule.approvalPending;
        } else {
          v['approval'] = sameAmount && was('approval') == FarmModule.approvalRejected ? FarmModule.approvalRejected : FarmModule.approvalNotRequired;
        }
      case FarmModule.tasks:
        // Who confirmed a task done is recorded automatically.
        v['checkedBy'] = s('status') == 'Done' ? (was('status') == 'Done' && was('checkedBy').isNotEmpty ? was('checkedBy') : who) : '';
      case FarmModule.requests:
        v['requestedBy'] = before == null ? (s('requestedBy').isEmpty ? who : s('requestedBy')) : was('requestedBy');
        if (s('status').isEmpty) v['status'] = 'Pending';
        v['decidedBy'] = s('status') == 'Pending' ? '' : (s('status') == was('status') && was('decidedBy').isNotEmpty ? was('decidedBy') : who);
      case FarmModule.managerReports:
        v['submittedBy'] = before == null ? (s('submittedBy').isEmpty ? who : s('submittedBy')) : was('submittedBy');
        if (s('status').isEmpty) v['status'] = 'Submitted';
      case FarmModule.inventory:
        if (before != null) v['qty'] = before['qty']; // stock changes only through transactions
        final status = inventoryStatus(v);
        if (status != null) v['status'] = status;
      case FarmModule.semen:
        v['status'] = semenStatus(v);
      case FarmModule.milkProduction:
        // Milk from an animal inside a medicine withdrawal period must not be
        // offered for sale.
        final date = FarmRecord.parseDate(v['date']);
        if (date != null && withdrawalEnd(v['animal'], date) != null) v['quality'] = FarmModule.qualityWithheld;
      case FarmModule.breeding:
        final semen = semenByCode(v['semen']);
        if (semen != null && s('bull').isEmpty) v['bull'] = semen['bull'];
      case FarmModule.feedRecords:
        final item = feedItem(v['feed']);
        if (s('source').isEmpty) v['source'] = FarmModule.fromInventory;
        if (s('unit').isEmpty) v['unit'] = '${item?['unit'] ?? 'kg'}';
        if (s('unitPrice').isEmpty && item != null) v['unitPrice'] = formatQty(item.number('unitCost'));
        v['category'] = item == null ? s('category') : ('${item['feedType'] ?? ''}'.isNotEmpty ? item['feedType'] : item['category']);
        v['species'] = _speciesFor(v);
        v['totalCost'] = (n('qty') * n('unitPrice')).toStringAsFixed(2);
      case FarmModule.mortality:
        if (s('animal').isNotEmpty) v['count'] = '1';
      case FarmModule.sales:
        final gross = n('qty') * n('unitPrice');
        final net = gross - n('discount') - n('deductions');
        v['gross'] = gross.toStringAsFixed(2);
        v['amount'] = net.toStringAsFixed(2);
        final paid = n('paidAtSale') + list(FarmModule.collections).where((c) => FarmRecord.refId(c['sale']) == '${v['id']}'.toLowerCase()).fold(0.0, (t, c) => t + c.number('amount'));
        v['paid'] = paid.toStringAsFixed(2);
        v['due'] = (net - paid).toStringAsFixed(2);
        v['status'] = net - paid <= 0.005 ? 'Paid' : (paid > 0 ? 'Partial' : 'Due');
      case FarmModule.collections:
        final sale = resolve(FarmModule.sales, v['sale']);
        if (sale != null) v['customer'] = sale['customer'];
      case FarmModule.inventoryTx:
        if ('${v['type']}' == FarmModule.txCount) {
          final item = feedItem(v['item']);
          final current = (item?.number('qty') ?? 0) - (before == null ? 0 : _txDelta(before));
          v['_delta'] = formatQty(n('quantity') - current);
        }
      case FarmModule.animals:
        final animal = FarmRecord(v);
        if (animal.id.isNotEmpty) v['healthStatus'] = HealthRules.animalStatus(this, animal, recoveredDays: _profile.recoveredShowDays);
      case FarmModule.illness:
        v['species'] = '${resolve(FarmModule.animals, v['animal'])?['species'] ?? v['species'] ?? ''}';
        v['stage'] = HealthRules.stage(this, v);
        final (status, diagnosis) = HealthRules.diagnosis(this, s('id'));
        v['diagnosisStatus'] = status;
        v['diagnosis'] = diagnosis;
        if (s('reopenedCount').isEmpty) v['reopenedCount'] = '0';
      case FarmModule.consultations || FarmModule.treatments || FarmModule.followUps:
        // The animal always comes from the illness case it belongs to.
        final illness = resolve(FarmModule.illness, v['illness']);
        if (illness != null) v['animal'] = illness['animal'];
      case FarmModule.medication:
        final treatment = resolve(FarmModule.treatments, v['treatment']);
        if (treatment != null) {
          v['animal'] = treatment['animal'];
          v['illness'] = treatment['illness'];
          v['medicine'] = treatment['medicine'];
          if (s('doseGiven').isEmpty && (s('status') == FarmModule.medGiven || s('status') == FarmModule.medDelayed)) {
            v['doseGiven'] = '${treatment['dose']} ${treatment['doseUnit']}'.trim();
          }
        }
    }
    return v;
  }

  String _speciesFor(Map<String, dynamic> v) {
    final animal = resolve(FarmModule.animals, v['animal']);
    if (animal != null) return '${animal['species'] ?? ''}';
    final batch = resolve(FarmModule.batches, v['batch']);
    if (batch != null) return '${batch['species'] ?? ''}';
    final group = '${v['group'] ?? ''}'.trim().toLowerCase();
    if (group.isEmpty) return '${v['species'] ?? ''}';
    for (final a in list(FarmModule.animals)) {
      if ('${a['group']}'.trim().toLowerCase() == group) return '${a['species'] ?? ''}';
    }
    return '${v['species'] ?? ''}';
  }

  /// In stock / Low stock / Out of stock from the quantity and reorder level.
  static String? inventoryStatus(Map<String, dynamic> values) {
    final qty = FarmRecord.leadingNumber(values['qty']);
    if (qty == null) return null;
    final reorder = FarmRecord.leadingNumber(values['reorder']);
    if (qty <= 0) return 'Out of stock';
    if (reorder != null && qty <= reorder) return 'Low stock';
    return 'In stock';
  }

  String semenStatus(Map<String, dynamic> values) {
    if ('${values['status']}' == 'Damaged') return 'Damaged';
    final expiry = FarmRecord.parseDate(values['expiry']);
    if (expiry != null && dateOnly(expiry).isBefore(today)) return 'Expired';
    if ((FarmRecord.leadingNumber(values['straws']) ?? 0) <= 0) return 'Used up';
    return 'Available';
  }

  /// The last day (exclusive) of [animal]'s milk withdrawal period covering
  /// [on], or null when its milk may be sold.
  DateTime? withdrawalEnd(dynamic animal, DateTime on) {
    DateTime? end;
    final day = dateOnly(on);
    // Withdrawal periods come from health records and from treatment plans.
    for (final h in [
      ...list(FarmModule.health),
      ...list(FarmModule.treatments).map((t) => FarmRecord({...t.data, 'date': t['startDate']}))
    ]) {
      if (FarmRecord.refId(h['animal']).isEmpty || FarmRecord.refId(h['animal']) != FarmRecord.refId(animal)) continue;
      final start = h.dateOf('date');
      final days = FarmRecord.leadingNumber(h['withdrawalDays']);
      if (start == null || days == null || days <= 0) continue;
      final until = dateOnly(start).add(Duration(days: days.ceil()));
      if (!day.isBefore(dateOnly(start)) && day.isBefore(until) && (end == null || until.isAfter(end))) end = until;
    }
    return end;
  }

  // ---------------------------------------------------------------------------
  // Integrity rules

  /// Fields other records refer to by value, so they must be unique (ignoring
  /// case and surrounding spaces). An empty animal tag is allowed many times.
  static const uniqueFields = {
    FarmModule.inventory: 'name',
    FarmModule.species: 'name',
    FarmModule.locations: 'name',
    FarmModule.customers: 'name',
    FarmModule.batches: 'name',
    FarmModule.semen: 'code',
    FarmModule.animals: 'tag',
    FarmModule.staff: 'name',
  };

  void _check(String module, FarmRecord r, FarmRecord? before) {
    String s(String k) => '${r[k] ?? ''}'.trim();
    void fail(String m) => throw FarmRuleException(m);
    final date = r.dateOf('date');
    final unique = uniqueFields[module];
    if (unique != null && s(unique).isNotEmpty) {
      final key = s(unique).toLowerCase();
      final clash = list(module).where((x) => x.id != r.id && '${x[unique] ?? ''}'.trim().toLowerCase() == key);
      if (clash.isNotEmpty) fail('"${s(unique)}" is already used by ${clash.first.id}. Choose a different ${FarmModule.specFor(module, unique).label?.toLowerCase() ?? unique}.');
    }
    // Owner-only fields (approval decisions, report reviews) can be set only
    // by the owner; anyone else keeps the saved value.
    final a = access?.call();
    if (a != null && !a.canApprove) {
      for (final spec in FarmModule.byName(module)?.specs ?? const <FieldSpec>[]) {
        if (!spec.ownerOnly || spec.key == 'approval') continue;
        final was = before == null ? _ownerOnlyDefault(module, spec.key) : '${before[spec.key] ?? ''}'.trim();
        if (s(spec.key) != was) fail('Only the Farm Owner can set "${spec.label ?? spec.key}".');
      }
    }
    if (module == FarmModule.tasks && s('status') == 'Not done' && s('notes').isEmpty) fail('Write in the notes why the task was not done.');
    switch (module) {
      case FarmModule.feedRecords:
        if (s('animal').isEmpty && s('batch').isEmpty && s('group').isEmpty) fail('Choose the animal or group that was fed.');
        if (r.number('qty') <= 0) fail('Quantity must be more than zero.');
        if (s('source') == FarmModule.fromInventory) {
          final item = feedItem(r['feed']);
          if (item == null) fail('${r['feed']} is not in Inventory. Add it there, or choose "${FarmModule.manualExpense}".');
          final need = Units.convert(r.number('qty'), s('unit'), '${item!['unit']}');
          if (need == null) fail('${item['name']} is stocked in ${item['unit']}; record the feed in a compatible unit.');
          var available = item.number('qty');
          if (before != null && '${before['source']}' == FarmModule.fromInventory && '${before['feed']}'.toLowerCase() == '${item['name']}'.toLowerCase()) {
            available += Units.convert(before.number('qty'), '${before['unit']}', '${item['unit']}') ?? 0;
          }
          if (need! > available + 1e-9) fail('Only ${formatQty(available)} ${item['unit']} of ${item['name']} in stock.');
        }
      case FarmModule.inventoryTx:
        final item = feedItem(r['item']);
        if (item == null) fail('${r['item']} is not in Inventory.');
        if (r.number('quantity') < 0 || (r.number('quantity') == 0 && s('type') != FarmModule.txCount)) fail('Quantity must be more than zero.');
        final after = item!.number('qty') - (before == null ? 0 : _txDelta(before)) + _txDelta(r);
        if (after < -1e-9) fail('That would take ${item['name']} below zero (only ${formatQty(item.number('qty') - (before == null ? 0 : _txDelta(before)))} ${item['unit']} in stock).');
      case FarmModule.breeding:
        if (s('method') != 'Natural mating' && s('semen').isNotEmpty) {
          final semen = semenByCode(s('semen'));
          final same = before != null && '${before['semen']}'.toLowerCase() == s('semen').toLowerCase();
          if (semen != null && !same && semen.number('straws') < 1) fail('No straws of ${s('semen')} left in stock.');
        }
      case FarmModule.mortality:
        if (s('animal').isEmpty && s('batch').isEmpty) fail('Choose the animal that died.');
        if (s('animal').isNotEmpty) {
          final animal = resolve(FarmModule.animals, r['animal']);
          if (animal == null) fail('That animal is not in the register.');
          final same = before != null && animal!.isReferencedBy(before['animal']);
          if (!same && !isActive(animal!)) fail('${animal['name']} is already ${animal.status}.');
        }
        if (s('batch').isNotEmpty) {
          final alive = batchCount(r['batch'], asOf: date, excludeId: before?.id);
          if (r.number('count') <= 0) fail('Number lost must be more than zero.');
          if (r.number('count') > alive) fail('Only ${formatQty(alive)} left in the batch on that date.');
        }
      case FarmModule.batchMovements:
        if (r.number('quantity') <= 0) fail('Quantity must be more than zero.');
        if (FarmModule.movementRemoves.contains(s('type'))) {
          final alive = batchCount(r['batch'], asOf: date, excludeId: before?.id);
          if (r.number('quantity') > alive) fail('Only ${formatQty(alive)} left in the batch on that date.');
        }
      case FarmModule.production:
        if (r.number('quantity') <= 0) fail('Quantity must be more than zero.');
        if (r.number('saleable') + r.number('damaged') > r.number('quantity') + 1e-9) fail('Saleable plus damaged cannot be more than the total produced.');
        if (r.number('headCount') > 0) {
          if (s('batch').isEmpty) fail('Choose the batch the animals were harvested from.');
          final alive = batchCount(r['batch'], asOf: date, excludeId: before?.id);
          if (r.number('headCount') > alive) fail('Only ${formatQty(alive)} left in the batch on that date.');
        }
      case FarmModule.productUsage:
        _checkStock(s('product'), r.number('quantity'), s('unit'), date, before?.id, 'used');
      case FarmModule.sales:
        if (r.number('qty') <= 0) fail('Quantity sold must be more than zero.');
        if (r.number('amount') < 0) fail('Discount and deductions cannot be more than the gross sale.');
        if (r.number('paidAtSale') > r.number('amount') + 0.005) fail('Paid at sale cannot be more than the net sale.');
        if (stockedProducts.contains(s('product'))) _checkStock(s('product'), r.number('qty'), s('unit'), date, before?.id, 'sold');
        if (r.number('headCount') > 0) {
          if (s('batch').isEmpty) fail('Choose the batch the animals/birds were sold from.');
          final alive = batchCount(r['batch'], asOf: date, excludeId: before?.id);
          if (r.number('headCount') > alive) fail('Only ${formatQty(alive)} left in the batch on that date.');
        }
        if (s('product') == 'Live animal') {
          final animal = resolve(FarmModule.animals, r['animal']);
          if (animal == null) fail('Choose the animal that was sold.');
          final soldBefore = before != null && animal!.isReferencedBy(before['animal']);
          if (!soldBefore && !isActive(animal!)) fail('${animal['name']} is already ${animal.status}.');
        }
      case FarmModule.collections:
        final sale = resolve(FarmModule.sales, r['sale']);
        if (sale == null) fail('Choose the sale this payment is for.');
        if (r.number('amount') <= 0) fail('Amount must be more than zero.');
        final due = sale!.number('amount') - receivedFor(sale, excludeCollectionId: r.id);
        if (r.number('amount') > due + 0.005) fail('Only ${formatQty(due)} is outstanding on ${sale.id}.');
      case FarmModule.expenses:
        if (r.number('amount') <= 0) fail('Amount must be more than zero.');
        final scope = s('scope');
        if (scope == 'Animal' && s('animal').isEmpty) fail('Choose the animal this expense is for.');
        if (scope == 'Batch' && s('batch').isEmpty) fail('Choose the batch this expense is for.');
        if (scope == 'Location' && s('location').isEmpty) fail('Choose the location this expense is for.');
        // Costs that already come from another record must not be entered twice.
        final category = s('category');
        final animalPurchase = category == FarmModule.animalPurchase || category == FarmModule.legacyAnimalPurchase;
        if (animalPurchase && scope == 'Animal') {
          fail('A registered animal’s purchase is counted from its purchase price. Enter it on the animal instead.');
        }
        if ((category == 'Fish/shrimp stocking' || animalPurchase) && scope == 'Batch') {
          fail('A batch’s stocking cost is counted from the batch record (or a Batch Movement with a cost). Enter it there instead.');
        }
        if ((category == 'Veterinary treatment' || category == 'Medicine and vaccines') && (scope == 'Animal' || scope == 'Batch')) {
          final dup = list(FarmModule.health).where((h) =>
              h.number('cost') > 0 &&
              (h.number('cost') - r.number('amount')).abs() < 0.005 &&
              h['date'] == r['date'] &&
              FarmRecord.refId(scope == 'Animal' ? h['animal'] : h['batch']) == FarmRecord.refId(scope == 'Animal' ? r['animal'] : r['batch']));
          if (dup.isNotEmpty) fail('This looks like health record ${dup.first.id}, whose cost is already counted. Don’t enter it twice.');
          if (scope == 'Animal') {
            final same = [
              ...list(FarmModule.treatments).where((t) => t.number('cost') > 0 && (t.number('cost') - r.number('amount')).abs() < 0.005 && t['startDate'] == r['date']),
              ...list(FarmModule.consultations).where((c) => c.number('fee') > 0 && (c.number('fee') - r.number('amount')).abs() < 0.005 && c['date'] == r['date']),
            ].where((x) => FarmRecord.refId(x['animal']) == FarmRecord.refId(r['animal']));
            if (same.isNotEmpty) fail('This looks like ${same.first.id}, whose cost is already counted in profit. Don’t enter it twice.');
          }
        }
      default:
        _checkHealth(module, r, before);
    }
  }

  // ---------------------------------------------------------------------------
  // Health records: referential integrity and safety rules

  void _checkHealth(String module, FarmRecord r, FarmRecord? before) {
    String s(String k) => '${r[k] ?? ''}'.trim();
    Never fail(String m) => throw FarmRuleException(m);
    final now = _clock().add(const Duration(minutes: 5));
    FarmRecord illnessOf(dynamic ref) {
      final i = resolve(FarmModule.illness, ref);
      if (i == null) fail('Choose an existing illness case.');
      return i;
    }

    void mustBeOpen(FarmRecord illness) {
      final sameCase = before != null && FarmRecord.refId(before['illness']) == illness.id.toLowerCase();
      if (!sameCase && !HealthRules.acceptsEntries(illness.data)) fail('Illness case ${illness.id} is closed (${illness['closure']}). Reopen it first if the symptoms came back.');
    }

    switch (module) {
      case FarmModule.illness:
        final animal = resolve(FarmModule.animals, r['animal']);
        if (animal == null) fail('Choose an animal from the register.');
        final changedAnimal = before == null || !animal.isReferencedBy(before['animal']);
        if (changedAnimal && !isActive(animal)) fail('${animal['name']} is ${animal.status}; illness can only be reported for an active animal.');
        final noticed = FarmRecord.parseDate(r['noticedAt']);
        final reported = FarmRecord.parseDate(r['reportedAt']);
        if (noticed == null || reported == null) fail('Enter when symptoms were noticed and when they were reported.');
        if (noticed.isAfter(now)) fail('Symptoms cannot be noticed in the future.');
        if (reported.isAfter(now)) fail('The report time cannot be in the future.');
        if (reported.isBefore(noticed)) fail('The report time is before the symptoms were noticed.');
        final temp = FarmRecord.leadingNumber(r['temperature']);
        if (temp != null) {
          if (s('tempUnit').isEmpty) fail('Choose the temperature unit (°C or °F).');
          final (lo, hi) = s('tempUnit') == '°F' ? (86.0, 113.0) : (30.0, 45.0);
          if (temp < lo || temp > hi) fail('A body temperature of ${formatQty(temp)} ${s('tempUnit')} is not possible — check the reading and unit.');
        }
        // A repeated submit of the same report is refused.
        final dup = list(FarmModule.illness).where((i) =>
            i.id != r.id &&
            FarmRecord.refId(i['animal']) == FarmRecord.refId(r['animal']) &&
            '${i['noticedAt']}' == s('noticedAt') &&
            '${i['symptoms']}'.trim().toLowerCase() == s('symptoms').toLowerCase());
        if (dup.isNotEmpty) fail('This illness is already reported as ${dup.first.id}.');
      case FarmModule.consultations:
        final illness = illnessOf(r['illness']);
        mustBeOpen(illness);
        final date = r.dateOf('date');
        if (date != null && date.isAfter(now)) fail('A consultation cannot be dated in the future. Use "Next consultation" for an appointment.');
        if (s('diagnosisStatus') == FarmModule.diagConfirmed && (s('vetName').isEmpty || s('diagnosis').isEmpty)) {
          fail('A confirmed diagnosis needs the veterinarian’s name and the diagnosis they gave.');
        }
        final next = r.dateOf('nextDate');
        if (next != null && date != null && next.isBefore(date)) fail('The next consultation is before this one.');
      case FarmModule.treatments:
        final illness = illnessOf(r['illness']);
        mustBeOpen(illness);
        final start = r.dateOf('startDate');
        final end = r.dateOf('endDate');
        if (start != null && end != null && end.isBefore(start)) fail('The planned end is before the start.');
        if (s('stockItem').isNotEmpty) {
          if (feedItem(r['stockItem']) == null) fail('${s('stockItem')} is not in Inventory.');
          if (r.number('stockPerDose') <= 0) fail('Enter how much stock each dose uses, or clear "Take from stock".');
        }
        final outcome = s('outcome');
        if (outcome.isNotEmpty && outcome != FarmModule.treatmentOngoing && outcome != 'Completed' && s('outcomeNotes').isEmpty) {
          fail('Record the reason for "$outcome" (e.g. the veterinarian’s instruction).');
        }
      case FarmModule.medication:
        final treatment = resolve(FarmModule.treatments, r['treatment']);
        if (treatment == null) fail('Choose an existing treatment plan.');
        final illness = resolve(FarmModule.illness, treatment['illness']);
        if (illness != null) {
          final sameCase = before != null && FarmRecord.refId(before['treatment']) == treatment.id.toLowerCase();
          if (!sameCase && !HealthRules.acceptsEntries(illness.data)) fail('Illness case ${illness.id} is closed. Reopen it first.');
        }
        final status = s('status');
        final given = status == FarmModule.medGiven || status == FarmModule.medDelayed;
        if (status == FarmModule.medScheduled && s('scheduledAt').isEmpty) fail('Enter when the dose is scheduled.');
        if (given && s('givenAt').isEmpty) fail('Enter when the dose was given.');
        if (given && s('administeredBy').isEmpty) fail('Enter who gave the dose.');
        if ((status == FarmModule.medMissed || status == FarmModule.medDelayed || status == FarmModule.medDiscontinued) && s('reason').isEmpty) {
          fail('Record the reason the dose was ${status.toLowerCase()}.');
        }
        final givenAt = FarmRecord.parseDate(r['givenAt']);
        if (givenAt != null && givenAt.isAfter(now)) fail('A dose cannot be given in the future.');
        final when = s('givenAt').isNotEmpty ? s('givenAt') : s('scheduledAt');
        final dup = list(FarmModule.medication).where((m) =>
            m.id != r.id &&
            FarmRecord.refId(m['treatment']) == treatment.id.toLowerCase() &&
            '${m['status']}' == status &&
            '${'${m['givenAt']}'.isNotEmpty ? m['givenAt'] : m['scheduledAt']}' == when);
        if (when.isNotEmpty && dup.isNotEmpty) fail('This dose is already recorded as ${dup.first.id}.');
        if (given) {
          final item = feedItem(treatment['stockItem']);
          if (item != null) {
            final need = treatment.number('stockPerDose');
            var available = item.number('qty');
            if (before != null && '${before['_stockItem'] ?? ''}'.toLowerCase() == '${item['name']}'.toLowerCase()) available += before.number('_stockIssued');
            if (need > available + 1e-9) fail('Only ${formatQty(available)} ${item['unit']} of ${item['name']} in stock. Record a purchase first, or clear "Take from stock" on the treatment.');
          }
        }
      case FarmModule.followUps:
        final illness = illnessOf(r['illness']);
        mustBeOpen(illness);
        final status = s('status');
        if (status == 'Done') {
          if (s('doneDate').isEmpty) fail('Enter the date the follow-up was done.');
          if (s('progress').isEmpty) fail('Record whether the symptoms improved, stayed the same or got worse.');
          final done = r.dateOf('doneDate');
          if (done != null && done.isAfter(now)) fail('A follow-up cannot be done in the future.');
        }
    }
  }

  /// A given dose takes the treatment's stock-per-dose from Inventory and
  /// records exactly what it took (item and quantity) on itself, so editing or
  /// deleting it reverses that amount — never a second deduction.
  void _issueMedicine(FarmRecord med, {required bool undo, required Set<String> touched}) {
    final tx = list(FarmModule.inventoryTx);
    final txId = 'TX-${med.id}';
    if (undo) {
      final item = feedItem(med['_stockItem']);
      final qty = med.number('_stockIssued');
      if (item != null && qty > 0) _setItemQty(item, item.number('qty') + qty, touched);
      tx.removeWhere((t) => t.id == txId);
      touched.add(FarmModule.inventoryTx);
      return;
    }
    final status = '${med['status']}';
    final treatment = resolve(FarmModule.treatments, med['treatment']);
    final item = feedItem(treatment?['stockItem']);
    final qty = treatment?.number('stockPerDose') ?? 0;
    final rows = list(FarmModule.medication);
    final i = rows.indexWhere((r) => r.id == med.id);
    final issue = (status == FarmModule.medGiven || status == FarmModule.medDelayed) && item != null && qty > 0;
    if (i >= 0) rows[i] = FarmRecord({...rows[i].toJson(), '_stockItem': issue ? item['name'] : '', '_stockIssued': issue ? formatQty(qty) : ''});
    if (!issue) return;
    _setItemQty(item, item.number('qty') - qty, touched);
    tx.insert(
        0,
        FarmRecord({
          'id': txId,
          'date': '${med['givenAt']}'.split(' ').first,
          'item': item['name'],
          'type': FarmModule.txTreatment,
          'quantity': formatQty(qty),
          'unitCost': '${item['unitCost'] ?? ''}',
          'reference': med.id,
          'notes': '${med['medicine']} · ${med['animal']}'
        }));
    touched.add(FarmModule.inventoryTx);
  }

  /// Keeps an illness case's stage and diagnosis current, then its animal's
  /// health status.
  void _syncIllness(String illnessId, Set<String> touched) {
    final rows = list(FarmModule.illness);
    final i = rows.indexWhere((r) => r.id.toLowerCase() == illnessId.toLowerCase());
    if (i < 0) return;
    rows[i] = FarmRecord(_prepare(FarmModule.illness, rows[i].toJson(), rows[i]));
    touched.add(FarmModule.illness);
    _syncAnimalHealth(rows[i]['animal'], touched);
  }

  void _syncAnimalHealth(dynamic animalRef, Set<String> touched) {
    final animal = resolve(FarmModule.animals, animalRef);
    if (animal == null) return;
    final status = HealthRules.animalStatus(this, animal, recoveredDays: _profile.recoveredShowDays);
    if ('${animal['healthStatus'] ?? ''}' == status) return;
    _replace(FarmModule.animals, FarmRecord({...animal.toJson(), 'healthStatus': status}), touched);
  }

  void _syncAllAnimalHealth(Set<String> touched) {
    for (final a in [...list(FarmModule.animals)]) {
      _syncAnimalHealth(a.reference, touched);
    }
  }

  void _checkStock(String product, double qty, String unit, DateTime? date, String? excludeId, String verb) {
    if (qty <= 0) throw const FarmRuleException('Quantity must be more than zero.');
    if (!stockedProducts.contains(product)) return;
    final available = productStock(product, asOf: date, excludeId: excludeId);
    final want = Units.toBase(qty, unit);
    if (want > available + 1e-6) {
      final base = Units.baseOf(unit);
      throw FarmRuleException('Only ${formatQty(available < 0 ? 0 : available)} $base of $product unsold on that date — record the production first, or check the quantity $verb.');
    }
  }

  // ---------------------------------------------------------------------------
  // Linked effects (each is reversible: edit = undo old + apply new)

  Future<void> _effects(String module, FarmRecord? before, FarmRecord? after, Set<String> touched) async {
    // Records that refer to this one by name or code follow a rename.
    void follow(String field, List<(String, String)> targets) {
      if (before == null || after == null) return;
      final from = '${before[field] ?? ''}'.trim();
      final to = '${after[field] ?? ''}'.trim();
      if (from.isEmpty || from == to) return;
      for (final (m, f) in targets) {
        _rename(m, f, from, to, touched);
      }
    }

    switch (module) {
      case FarmModule.species:
        follow('name', [(FarmModule.animals, 'species'), (FarmModule.batches, 'species'), (FarmModule.feedRecords, 'species'), (FarmModule.illness, 'species')]);
      case FarmModule.locations:
        follow('name', [(FarmModule.animals, 'location'), (FarmModule.batches, 'location'), (FarmModule.expenses, 'location')]);
      case FarmModule.customers:
        follow('name', [(FarmModule.sales, 'customer'), (FarmModule.collections, 'customer')]);
      case FarmModule.staff:
        follow('name', [(FarmModule.tasks, 'assignedTo')]);
      case FarmModule.semen:
        follow('code', [(FarmModule.breeding, 'semen')]);
      case FarmModule.animals || FarmModule.batches:
        // References such as "AN-1001 · Shona" show the new name.
        if (before != null && after != null && before.reference != after.reference) {
          for (final m in modules) {
            final rows = list(m);
            for (var i = 0; i < rows.length; i++) {
              final fields = module == FarmModule.animals ? const ['animal', 'dam'] : const ['batch'];
              final hit = fields.where((f) => after.isReferencedBy(rows[i][f]) && '${rows[i][f]}' != after.reference);
              if (hit.isEmpty) continue;
              rows[i] = FarmRecord({...rows[i].toJson(), for (final f in hit) f: after.reference});
              touched.add(m);
            }
          }
        }
      case FarmModule.feedRecords:
        if (before != null) _issueFeed(before, undo: true, touched: touched);
        if (after != null) _issueFeed(after, undo: false, touched: touched);
      case FarmModule.inventoryTx:
        if (before != null) _applyTx(before, undo: true, touched: touched);
        if (after != null) _applyTx(after, undo: false, touched: touched);
      case FarmModule.inventory:
        if (before == null && after != null && after.number('qty') > 0) {
          list(FarmModule.inventoryTx).insert(
              0,
              FarmRecord({
                'id': 'TX-OPEN-${after.id}',
                'date': formatDate(today),
                'item': after['name'],
                'type': FarmModule.txOpening,
                'quantity': after['qty'],
                'unitCost': '${after['unitCost'] ?? ''}',
                'reference': 'Opening balance',
                'notes': ''
              }));
          touched.add(FarmModule.inventoryTx);
        }
        if (before != null && after != null && '${before['name']}' != '${after['name']}') {
          _rename(FarmModule.feedRecords, 'feed', '${before['name']}', '${after['name']}', touched);
          _rename(FarmModule.inventoryTx, 'item', '${before['name']}', '${after['name']}', touched);
        }
      case FarmModule.breeding:
        if (before != null) _useStraw(before, undo: true, touched: touched);
        if (after != null) _useStraw(after, undo: false, touched: touched);
      case FarmModule.weights:
        for (final r in {before?['animal'], after?['animal']}) {
          if (r != null) _syncAnimalWeight(r, touched);
        }
      case FarmModule.mortality:
        if (before != null) _setDisposal(before, undo: true, status: 'Dead', touched: touched);
        if (after != null) _setDisposal(after, undo: false, status: 'Dead', touched: touched, owner: module);
      case FarmModule.sales:
        if (before != null && '${before['product']}' == 'Live animal') _setDisposal(before, undo: true, status: 'Sold', touched: touched);
        if (after != null && '${after['product']}' == 'Live animal') _setDisposal(after, undo: false, status: 'Sold', touched: touched, owner: module);
      case FarmModule.collections:
        for (final ref in {before?['sale'], after?['sale']}) {
          final sale = resolve(FarmModule.sales, ref);
          if (sale == null) continue;
          final rows = list(FarmModule.sales);
          rows[rows.indexWhere((x) => x.id == sale.id)] = FarmRecord(_prepare(FarmModule.sales, sale.toJson(), sale));
          touched.add(FarmModule.sales);
        }
      case FarmModule.medication:
        if (before != null) _issueMedicine(before, undo: true, touched: touched);
        if (after != null) _issueMedicine(after, undo: false, touched: touched);
    }
    // Any health record can move its case to another stage, which changes the
    // animal's health status.
    switch (module) {
      case FarmModule.illness:
        for (final r in {before, after}) {
          if (r != null) _syncAnimalHealth(r['animal'], touched);
        }
        if (after != null) _syncIllness(after.id, touched);
      case FarmModule.consultations || FarmModule.treatments || FarmModule.followUps || FarmModule.medication:
        for (final ref in {before?['illness'], after?['illness']}) {
          if (ref != null && '$ref'.isNotEmpty) _syncIllness(FarmRecord.refId(ref), touched);
        }
      case FarmModule.mortality || FarmModule.animals:
        for (final r in {before, after}) {
          if (r != null) _syncAnimalHealth(module == FarmModule.animals ? r.reference : r['animal'], touched);
        }
    }
  }

  void _rename(String module, String field, String from, String to, Set<String> touched) {
    final rows = list(module);
    for (var i = 0; i < rows.length; i++) {
      if ('${rows[i][field] ?? ''}'.trim().toLowerCase() == from.trim().toLowerCase()) {
        rows[i] = FarmRecord({...rows[i].toJson(), field: to});
        touched.add(module);
      }
    }
  }

  /// A feed record issued from inventory creates a matching stock movement
  /// (id TX-<feed id>) and reduces stock; undoing removes both.
  void _issueFeed(FarmRecord feed, {required bool undo, required Set<String> touched}) {
    if ('${feed['source']}' != FarmModule.fromInventory) return;
    final item = feedItem(feed['feed']);
    if (item == null) return;
    final qty = Units.convert(feed.number('qty'), '${feed['unit']}', '${item['unit']}') ?? 0;
    _setItemQty(item, item.number('qty') + (undo ? qty : -qty), touched);
    final tx = list(FarmModule.inventoryTx);
    final txId = 'TX-${feed.id}';
    tx.removeWhere((t) => t.id == txId);
    if (!undo) {
      tx.insert(
          0,
          FarmRecord({
            'id': txId,
            'date': feed['date'],
            'item': item['name'],
            'type': FarmModule.txIssue,
            'quantity': formatQty(qty),
            'unitCost': '${feed['unitPrice'] ?? ''}',
            'reference': feed.id,
            'notes': ''
          }));
    }
    touched.add(FarmModule.inventoryTx);
  }

  /// Stock change caused by a manual transaction, in the item's unit.
  double _txDelta(FarmRecord tx) {
    final q = tx.number('quantity');
    return switch ('${tx['type']}') {
      FarmModule.txPurchase || FarmModule.txAdjustUp => q,
      FarmModule.txAdjustDown || FarmModule.txWastage => -q,
      FarmModule.txCount => tx.number('_delta'),
      FarmModule.txTreatment => 0, // applied by the medication record
      _ => 0, // opening and feed issues are applied by their owners
    };
  }

  void _applyTx(FarmRecord tx, {required bool undo, required Set<String> touched}) {
    final item = feedItem(tx['item']);
    if (item == null) return;
    final delta = _txDelta(tx);
    if (delta == 0 && '${tx['type']}' != FarmModule.txPurchase) return;
    var updated = item.toJson()..['qty'] = formatQty(item.number('qty') + (undo ? -delta : delta));
    if (!undo && '${tx['type']}' == FarmModule.txPurchase && tx.number('unitCost') > 0) updated['unitCost'] = formatQty(tx.number('unitCost'));
    _replace(FarmModule.inventory, FarmRecord(updated..['status'] = inventoryStatus(updated) ?? updated['status']), touched);
  }

  void _setItemQty(FarmRecord item, double qty, Set<String> touched) {
    final updated = item.toJson()..['qty'] = formatQty(qty);
    updated['status'] = inventoryStatus(updated) ?? updated['status'];
    _replace(FarmModule.inventory, FarmRecord(updated), touched);
  }

  void _useStraw(FarmRecord service, {required bool undo, required Set<String> touched}) {
    if ('${service['method']}' == 'Natural mating') return;
    final semen = semenByCode(service['semen']);
    if (semen == null) return;
    final updated = semen.toJson()..['straws'] = formatQty(semen.number('straws') + (undo ? 1 : -1));
    updated['status'] = semenStatus(updated);
    _replace(FarmModule.semen, FarmRecord(updated), touched);
  }

  /// Marks an animal Sold or Dead, remembering its previous status on the
  /// record that caused it so a delete can put it back.
  void _setDisposal(FarmRecord source, {required bool undo, required String status, required Set<String> touched, String? owner}) {
    final animal = resolve(FarmModule.animals, source['animal']);
    if (animal == null) return;
    if (undo) {
      if (animal.status == status) {
        final prev = '${source['_prevStatus'] ?? 'Active'}';
        _replace(FarmModule.animals, FarmRecord({...animal.toJson(), 'status': prev.isEmpty ? 'Active' : prev}), touched);
      }
      return;
    }
    if (animal.status == status) return;
    if (owner != null) {
      final rows = list(owner);
      final i = rows.indexWhere((r) => r.id == source.id);
      if (i >= 0) rows[i] = FarmRecord({...rows[i].toJson(), '_prevStatus': animal.status});
    }
    _replace(FarmModule.animals, FarmRecord({...animal.toJson(), 'status': status}), touched);
  }

  /// Keeps an animal's current weight equal to its latest weight record.
  void _syncAnimalWeight(dynamic animalRef, Set<String> touched) {
    final animal = resolve(FarmModule.animals, animalRef);
    if (animal == null) return;
    FarmRecord? latest;
    for (final w in list(FarmModule.weights)) {
      if (!animal.isReferencedBy(w['animal'])) continue;
      if (latest == null || '${w['date']}'.compareTo('${latest['date']}') > 0) latest = w;
    }
    if (latest == null || '${latest['weight']}' == '${animal['weight']}') return;
    _replace(FarmModule.animals, FarmRecord({...animal.toJson(), 'weight': '${latest['weight']}'}), touched);
  }

  void _replace(String module, FarmRecord record, Set<String> touched) {
    final rows = list(module);
    final i = rows.indexWhere((r) => r.id == record.id);
    if (i < 0) return;
    rows[i] = record;
    touched.add(module);
  }

  // ---------------------------------------------------------------------------
  // Backup

  /// Everything needed to rebuild this farm's data on another device.
  Map<String, dynamic> exportData() => {
        'app': 'technovate_farm',
        'version': backupVersion,
        'dataVersion': dataVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': _profile.toJson(),
        'records': {for (final m in modules) m: list(m).map((r) => r.toJson()).toList()},
        'activity': _activity.map((a) => a.toJson()).toList(),
      };

  /// Replaces all records, profile and activity with a backup made by
  /// [exportData]. Throws [FormatException] when the backup is not valid; in
  /// that case nothing is changed.
  Future<void> restore(Map<String, dynamic> backup) async {
    _authorize((a) => a.canBackup, 'restore backups');
    if (backup['app'] != 'technovate_farm' || backup['version'] != backupVersion) {
      throw const FormatException('This is not a DeshIT-BD backup.');
    }
    final records = backup['records'];
    if (records is! Map) throw const FormatException('The backup has no records.');
    final parsed = <String, List<FarmRecord>>{};
    for (final module in modules) {
      final rows = records[module];
      if (rows == null) continue;
      if (rows is! List) throw FormatException('$module records are not a list.');
      parsed[module] = rows.map((row) {
        if (row is! Map || row['id'] == null) throw FormatException('A $module record is missing its id.');
        return FarmRecord(Map<String, dynamic>.from(row));
      }).toList();
    }
    final profile = backup['profile'] is Map ? FarmProfile.fromJson(Map<String, dynamic>.from(backup['profile'] as Map)) : _profile;
    final activity = backup['activity'] is List ? (backup['activity'] as List).whereType<Map>().map((e) => ActivityEntry.fromJson(Map<String, dynamic>.from(e))).toList() : <ActivityEntry>[];

    for (final module in modules) {
      _records[module] = parsed[module] ?? [];
      await _persist(module);
    }
    _profile = profile;
    await _storage.writeProfile(profile.toJson());
    _activity
      ..clear()
      ..addAll(activity.take(activityLimit));
    // Backups from older versions are brought up to date.
    final from = (backup['dataVersion'] as num?)?.toInt() ?? 1;
    if (from < dataVersion) {
      await _storage.writeValue(_dataVersionKey, '$from');
      await _migrate();
      await _storage.writeValue(_dataVersionKey, '$dataVersion');
    }
    await log('Data restored from backup');
  }

  String _newId(String module) {
    final prefix = module.split(' ').map((e) => e.isNotEmpty ? e[0] : '').join().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    final base = '${prefix.isEmpty ? 'REC' : prefix}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    // Several records can be created in the same millisecond (e.g. a calving
    // adds a calf and updates the service); keep ids unique.
    var id = base;
    var n = 1;
    while (find(module, id) != null) {
      id = '$base-${n++}';
    }
    return id;
  }

  Future<void> _persistAll(Set<String> modules) async {
    for (final m in modules) {
      await _persist(m);
    }
  }

  Future<void> _persist(String module) => _storage.writeRecords(module, list(module).map((r) => r.toJson()).toList());
}
