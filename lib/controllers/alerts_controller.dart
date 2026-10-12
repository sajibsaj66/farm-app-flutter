import 'package:flutter/material.dart';

import '../core/utils/dates.dart';
import '../models/alert_item.dart';
import '../models/farm_module.dart';
import '../models/farm_record.dart';
import '../services/local_storage_service.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'batch_analytics.dart';
import 'health_analytics.dart';
import 'health_rules.dart';
import 'herd_analytics.dart';

/// Reminders computed live from farm records, limited to what the signed-in
/// user's role can act on. Users can mark alerts read; that is remembered per
/// user until the underlying record changes.
class AlertsController extends ChangeNotifier {
  AlertsController({FarmController? farm, AuthController? auth, LocalStorageService? storage, DateTime Function()? clock})
      : farm = farm ?? FarmController.instance,
        _auth = auth ?? AuthController.instance,
        _storage = storage ?? LocalStorageService.instance,
        _clock = clock ?? DateTime.now;

  static final AlertsController instance = AlertsController();

  /// Health follow-ups within this many days are flagged.
  static const followUpWindowDays = 7;

  final FarmController farm;
  final AuthController _auth;
  final LocalStorageService _storage;
  final DateTime Function() _clock;

  Set<String> _dismissed = {};
  String? _loadedFor;

  /// Every alert the current role may see, including ones marked read.
  List<AlertItem> get all {
    final access = _auth.access;
    if (!access.isSignedIn) return const [];
    return _computeAll().where((a) => a.module == null || access.canOpenModule(a.module!)).toList();
  }

  /// Alerts not yet marked read.
  List<AlertItem> get active {
    _ensureLoaded();
    return all.where((a) => !_dismissed.contains(a.id)).toList();
  }

  int get activeCount => active.length;

  int get dismissedCount => all.length - active.length;

  Future<void> dismiss(String id) async {
    _ensureLoaded();
    _dismissed.add(id);
    await _save();
  }

  Future<void> restoreDismissed() async {
    _ensureLoaded();
    _dismissed.clear();
    await _save();
  }

  void _ensureLoaded() {
    final username = _auth.currentUser?.username;
    if (username == _loadedFor) return;
    _loadedFor = username;
    _dismissed = username == null ? {} : _storage.readDismissedAlerts(username);
  }

  Future<void> _save() async {
    final username = _auth.currentUser?.username;
    if (username != null) {
      // Drop ids whose alert no longer exists so the stored set stays small.
      final live = all.map((a) => a.id).toSet();
      _dismissed.removeWhere((id) => !live.contains(id));
      await _storage.writeDismissedAlerts(username, _dismissed);
    }
    notifyListeners();
  }

  DateTime get _today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  List<AlertItem> _computeAll() => [
        ..._stockAlerts(),
        ..._healthAlerts(),
        ..._breedingAlerts(),
        ..._semenAlerts(),
        ..._salesAlerts(),
        ..._productionAlerts(),
        ..._illnessAlerts(),
        ..._teamAlerts(),
      ];

  /// Owner: decisions waiting, managers' reports, budget. Manager: the
  /// owner's decisions on their requests, and staff tasks still open today.
  Iterable<AlertItem> _teamAlerts() sync* {
    final access = _auth.access;
    final me = _auth.currentUser?.name;
    final cur = farm.profile.currency;
    if (access.canApprove) {
      for (final (m, r) in farm.pendingDecisions) {
        final isReport = m == FarmModule.managerReports;
        yield AlertItem(
          id: 'decide:$m:${r.id}',
          title: isReport ? 'New ${'${r['period']}'.toLowerCase()} report from ${r['submittedBy']}' : 'Waiting for your approval: ${r['description'] ?? r['item'] ?? r['title']}',
          message: isReport
              ? '${r['date']} — review it in Approvals'
              : '${r['date']}${r.number(m == FarmModule.requests ? 'estimatedAmount' : 'amount') > 0 ? ' · $cur${r.number(m == FarmModule.requests ? 'estimatedAmount' : 'amount').toStringAsFixed(0)}' : ''}',
          icon: isReport ? Icons.summarize_outlined : Icons.fact_check_outlined,
          module: m,
          tone: isReport ? AlertTone.info : AlertTone.warning,
        );
      }
      final budget = farm.profile.monthlyBudget;
      if (budget > 0) {
        final spent =
            farm.inRange(FarmModule.expenses, DateTime(_today.year, _today.month), _today).where((e) => !FarmModule.awaitsOrRefused(e['approval'])).fold(0.0, (s, e) => s + e.number('amount'));
        if (spent >= budget * 0.9) {
          yield AlertItem(
            id: 'budget:${_today.year}-${_today.month}:${spent >= budget ? 'over' : 'near'}',
            title: spent >= budget ? 'Monthly budget exceeded' : 'Monthly budget almost used',
            message: '$cur${spent.toStringAsFixed(0)} of $cur${budget.toStringAsFixed(0)} spent this month',
            icon: Icons.savings_outlined,
            module: FarmModule.expenses,
            tone: AlertTone.warning,
          );
        }
      }
    } else if (me != null) {
      for (final r in farm.list(FarmModule.requests).where((r) => '${r['requestedBy']}' == me && '${r['status']}' != 'Pending')) {
        yield AlertItem(
          id: 'request:${r.id}:${r['status']}',
          title: 'Owner ${'${r['status']}'.toLowerCase()} your request: ${r['title']}',
          message: '${r['decisionNote'] ?? ''}'.isEmpty ? 'Decided by ${r['decidedBy']}' : '${r['decisionNote']}',
          icon: Icons.approval_outlined,
          module: FarmModule.requests,
          tone: '${r['status']}' == 'Rejected' ? AlertTone.warning : AlertTone.info,
        );
      }
    }
    final key = formatDate(_today);
    final open = farm.list(FarmModule.tasks).where((t) => '${t['date']}' == key && '${t['status']}' == 'Pending').length;
    if (open > 0 && access.canEditModule(FarmModule.tasks) && !access.isOwner) {
      yield AlertItem(id: 'tasks:$key:$open', title: '$open staff task(s) still open today', message: 'Check them and mark them done', icon: Icons.checklist, module: FarmModule.tasks);
    }
  }

  /// In-app reminders for illness care: urgent cases, pending vet
  /// assessments, follow-ups, vet appointments, scheduled doses, and feed
  /// intake drops. Ids come from the record and its date, so editing a record
  /// never creates a duplicate reminder.
  Iterable<AlertItem> _illnessAlerts() sync* {
    final lead = farm.profile.reminderLeadDays;
    final horizon = _today.add(Duration(days: lead));
    String name(dynamic ref) => FarmRecord.displayName(ref);
    for (final c in farm.list(FarmModule.illness).where((c) => HealthRules.isOpen(c.data))) {
      if (HealthRules.isUrgent(farm, c)) {
        yield AlertItem(
          id: 'illness-urgent:${c.id}:${c['severity']}',
          title: 'URGENT: ${name(c['animal'])} — contact a veterinarian now',
          message: '${c['severity']} · ${c['symptoms']}${'${c['dangerSigns'] ?? ''}'.isEmpty ? '' : ' · ${c['dangerSigns']}'}',
          icon: Icons.emergency,
          module: FarmModule.illness,
          tone: AlertTone.warning,
        );
      } else if ('${c['stage']}' == FarmModule.healthAwaitingVet) {
        final reported = c.dateOf('reportedAt');
        yield AlertItem(
          id: 'illness-pending:${c.id}',
          title: '${name(c['animal'])}: awaiting veterinary assessment',
          message: 'Reported ${reported == null ? '' : '${daysBetween(reported, _today)} day(s) ago'} · ${c['symptoms']}',
          icon: Icons.local_hospital_outlined,
          module: FarmModule.illness,
        );
      }
    }
    for (final f in farm.list(FarmModule.followUps).where((f) => '${f['status']}' == 'Scheduled')) {
      final due = f.dateOf('dueDate');
      if (due == null || due.isAfter(horizon)) continue;
      final overdue = due.isBefore(_today);
      yield AlertItem(
        id: 'followup:${f.id}:${f['dueDate']}',
        title: overdue ? '${name(f['animal'])}: follow-up overdue' : '${name(f['animal'])}: follow-up ${due == _today ? 'today' : 'on ${f['dueDate']}'}',
        message: '${f['type']}${overdue ? ' was due ${f['dueDate']}' : ''} · case ${FarmRecord.refId(f['illness']).toUpperCase()}',
        icon: Icons.event_repeat,
        module: FarmModule.followUps,
        tone: overdue ? AlertTone.warning : AlertTone.info,
      );
    }
    for (final c in farm.list(FarmModule.consultations)) {
      final next = c.dateOf('nextDate');
      if (next == null || next.isAfter(horizon) || next.isBefore(_today)) continue;
      final illness = farm.resolve(FarmModule.illness, c['illness']);
      if (illness == null || !HealthRules.isOpen(illness.data)) continue;
      yield AlertItem(
        id: 'vetvisit:${c.id}:${c['nextDate']}',
        title: '${name(c['animal'])}: vet appointment ${next == _today ? 'today' : 'on ${c['nextDate']}'}',
        message: 'With ${c['vetName']}',
        icon: Icons.local_hospital_outlined,
        module: FarmModule.consultations,
      );
    }
    for (final m in farm.list(FarmModule.medication).where((m) => '${m['status']}' == FarmModule.medScheduled)) {
      final at = m.dateOf('scheduledAt');
      if (at == null || dateOnly(at).isAfter(horizon)) continue;
      final overdue = dateOnly(at).isBefore(_today);
      yield AlertItem(
        id: 'dose:${m.id}:${m['scheduledAt']}',
        title: '${name(m['animal'])}: ${m['medicine']} dose ${overdue ? 'overdue' : 'scheduled'}',
        message: 'For ${m['scheduledAt']} — record it as Given, Delayed or Missed',
        icon: Icons.vaccines_outlined,
        module: FarmModule.medication,
        tone: overdue ? AlertTone.warning : AlertTone.info,
      );
    }
    // Feed intake drops (milk drops are covered by the low-milk alert).
    final health = HealthAnalytics(farm, today: _today);
    for (final a in farm.list(FarmModule.animals).where(FarmController.isActive)) {
      for (final r in health.productionReview(a).where((r) => r.triggered && r.metric == 'Feed intake')) {
        yield AlertItem(
          id: 'lowfeed:${a.id}:${formatDate(_today)}',
          title: '${a['name']}: feed intake down — review the animal',
          message: '${r.explanation} Not proof of illness.',
          icon: Icons.grass,
          module: FarmModule.feedRecords,
          tone: AlertTone.warning,
        );
      }
    }
  }

  /// Low milk compared with the animal's own recent average, and batches
  /// losing birds/fish faster than the farm's alert threshold.
  Iterable<AlertItem> _productionAlerts() sync* {
    final profile = farm.profile;
    final herd = HerdAnalytics(farm, today: _today);
    for (final cow in herd.cows) {
      final a = herd.of(cow);
      final recent = a.period(7);
      if (recent.daysWithMilk < 3) continue;
      final earlier = a.milkRecords.where((m) {
        final d = m.dateOf('date');
        return d != null && d.isBefore(_today.subtract(const Duration(days: 6))) && !d.isBefore(_today.subtract(const Duration(days: 37)));
      }).toList();
      final days = earlier.map((m) => '${m['date']}').toSet().length;
      if (days < 7) continue;
      final baseline = earlier.fold(0.0, (s, m) => s + m.number('litres')) / days;
      if (baseline <= 0) continue;
      final ratio = recent.avgMilkPerDay / baseline;
      if (ratio * 100 < profile.lowMilkPercent) {
        yield AlertItem(
          id: 'lowmilk:${cow.id}:${formatDate(_today)}',
          title: '${cow['name']}: milk down to ${(ratio * 100).toStringAsFixed(0)}% of normal',
          message: '${recent.avgMilkPerDay.toStringAsFixed(1)} L/day this week vs ${baseline.toStringAsFixed(1)} L/day before — check health and feed',
          icon: Icons.trending_down,
          module: FarmModule.milkProduction,
          tone: AlertTone.warning,
        );
      }
    }
    for (final b in farm.list(FarmModule.batches).where(FarmController.isActive)) {
      final rate = BatchAnalytics(farm, b, today: _today).recentMortalityRate(7) * 100;
      if (rate > profile.mortalityAlertPercent) {
        yield AlertItem(
          id: 'mortality:${b.id}:${formatDate(_today)}',
          title: '${b['name']}: high mortality',
          message: '${rate.toStringAsFixed(1)}% lost in the last 7 days (alert above ${formatQty(profile.mortalityAlertPercent)}%)',
          icon: Icons.heart_broken_outlined,
          module: FarmModule.mortality,
          tone: AlertTone.warning,
        );
      }
    }
  }

  Iterable<AlertItem> _stockAlerts() => farm.list(FarmModule.inventory).where((r) => r.isLowStock).map((r) {
        final out = (FarmRecord.leadingNumber(r['qty']) ?? 1) <= 0;
        return AlertItem(
          // The quantity is part of the id, so restocking re-arms the alert.
          id: 'stock:${r.id}:${r['qty']}',
          title: out ? '${r['name']} is out of stock' : '${r['name']} is running low',
          message: '${r['qty']} ${r['unit'] ?? ''} remaining · reorder at ${r['reorder'] ?? '-'}'.replaceAll('  ', ' '),
          icon: Icons.warning_amber_rounded,
          module: FarmModule.inventory,
          tone: AlertTone.warning,
        );
      });

  Iterable<AlertItem> _healthAlerts() sync* {
    final horizon = _today.add(const Duration(days: followUpWindowDays));
    for (final r in farm.list(FarmModule.health)) {
      if (r.status.toLowerCase() == 'completed') continue;
      final next = r.dateOf('next');
      final followUp = r.status.toLowerCase().contains('follow');
      if (next == null && !followUp) continue;
      if (next != null && next.isAfter(horizon)) continue;
      final overdue = next != null && next.isBefore(_today);
      final name = FarmRecord.displayName('${r['animal'] ?? ''}'.isNotEmpty ? r['animal'] : r['batch']);
      yield AlertItem(
        id: 'health:${r.id}:${r['next']}:${r.status}',
        title: overdue ? '$name: ${r['type']} follow-up overdue' : '$name needs a ${'${r['type']}'.toLowerCase()} follow-up',
        message: next == null ? '${r['details']}' : '${r['details']} · ${overdue ? 'was due' : 'due'} ${r['next']}',
        icon: Icons.medical_services_outlined,
        module: FarmModule.health,
        tone: overdue ? AlertTone.warning : AlertTone.info,
      );
    }
  }

  /// Pregnancy checks, heat watch, repeat AI and expected calvings, worked out
  /// per cow from her breeding history.
  Iterable<AlertItem> _breedingAlerts() sync* {
    final herd = HerdAnalytics(farm, today: _today);
    for (final cow in herd.cows) {
      final a = herd.of(cow);
      final name = '${cow['name']}';
      final pending = a.pendingCheck;
      if (pending != null) {
        final served = pending.dateOf('date');
        if (served != null) {
          final since = daysBetween(served, _today);
          if (since >= Repro.pregnancyCheckDays) {
            yield AlertItem(
              id: 'pd:${pending.id}',
              title: '$name: pregnancy check due',
              message: 'Served $since days ago (${pending['date']}) · ${pending['bull'] ?? ''}',
              icon: Icons.pregnant_woman_outlined,
              module: FarmModule.breeding,
              tone: since > 60 ? AlertTone.warning : AlertTone.info,
            );
          } else if (since >= Repro.heatCycleDays - 3 && since <= Repro.heatCycleDays + 3) {
            yield AlertItem(
              id: 'heat:${pending.id}',
              title: '$name: watch for return to heat',
              message: 'Day $since after service — if she shows heat, the service did not hold',
              icon: Icons.visibility_outlined,
              module: FarmModule.breeding,
            );
          }
        }
      }
      final cycle = a.currentCycleServices;
      if (cycle.isNotEmpty && cycle.last.status == FarmModule.resultOpen) {
        yield AlertItem(
          id: 'repeat:${cycle.last.id}',
          title: '$name: not pregnant — re-breed',
          message: '${cycle.length} service${cycle.length == 1 ? '' : 's'} this cycle · watch for the next heat',
          icon: Icons.replay_outlined,
          module: FarmModule.breeding,
        );
      }
      final due = a.expectedCalving;
      if (due != null) {
        final left = daysBetween(_today, due);
        if (left <= 30) {
          yield AlertItem(
            id: 'calving:${a.currentPregnancy!.id}',
            title: left < 0 ? '$name: calving overdue' : '$name: calving expected in $left days',
            message: 'Expected ${formatDate(due)} (estimate) · prepare the calving pen',
            icon: Icons.child_friendly_outlined,
            module: FarmModule.breeding,
            tone: left <= 7 ? AlertTone.warning : AlertTone.info,
          );
        }
      }
      final withdrawal = a.withdrawalUntil;
      if (withdrawal != null) {
        yield AlertItem(
          id: 'withdrawal:${cow.id}:${formatDate(withdrawal)}',
          title: '$name: milk withdrawal period',
          message: 'Do not sell her milk until ${formatDate(withdrawal)} — it is recorded as Withheld',
          icon: Icons.block_outlined,
          module: FarmModule.milkProduction,
          tone: AlertTone.warning,
        );
      }
    }
  }

  Iterable<AlertItem> _semenAlerts() sync* {
    for (final s in farm.list(FarmModule.semen)) {
      final expiry = s.dateOf('expiry');
      final straws = s.number('straws');
      final label = '${s['code']} (${FarmRecord.displayName(s['bull'])})';
      if (expiry != null && expiry.isBefore(_today)) {
        if (straws > 0) {
          yield AlertItem(
              id: 'semen-exp:${s.id}',
              title: 'Semen $label has expired',
              message: 'Expired ${s['expiry']} · ${formatQty(straws)} straws left — do not use',
              icon: Icons.science_outlined,
              module: FarmModule.semen,
              tone: AlertTone.warning);
        }
        continue;
      }
      if (expiry != null && daysBetween(_today, expiry) <= 30 && straws > 0) {
        yield AlertItem(
            id: 'semen-soon:${s.id}:${s['expiry']}',
            title: 'Semen $label expires soon',
            message: 'Expires ${s['expiry']} · ${formatQty(straws)} straws left',
            icon: Icons.science_outlined,
            module: FarmModule.semen);
      }
      if (straws <= 2) {
        yield AlertItem(
          id: 'semen-low:${s.id}:${s['straws']}',
          title: straws <= 0 ? 'Semen $label is used up' : 'Only ${formatQty(straws)} straw${straws == 1 ? '' : 's'} of $label left',
          message: 'Reorder from ${s['supplier']}',
          icon: Icons.science_outlined,
          module: FarmModule.semen,
          tone: AlertTone.warning,
        );
      }
    }
  }

  Iterable<AlertItem> _salesAlerts() => farm.list(FarmModule.sales).where((r) {
        final s = r.status.toLowerCase();
        return s == 'due' || s == 'partial';
      }).map((r) => AlertItem(
            id: 'sale:${r.id}:${r.status}',
            title: '${r['customer']} has a payment due',
            message: '${farm.profile.currency}${r.number('due').toStringAsFixed(0)} due (of ${farm.profile.currency}${r.number('amount').toStringAsFixed(0)}) · '
                '${'${r['item'] ?? ''}'.trim().isNotEmpty ? r['item'] : r['product']} on ${r['date']}',
            icon: Icons.payments_outlined,
            module: FarmModule.sales,
            tone: AlertTone.warning,
          ));
}
