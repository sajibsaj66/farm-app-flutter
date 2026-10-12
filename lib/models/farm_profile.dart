/// How feed cost is recognised in profit and loss.
enum FeedCostBasis {
  /// Feed is charged when it is fed (Feed Records). Feed purchases recorded as
  /// expenses are treated as stock bought, not as cost, so they are not counted
  /// twice.
  consumption('When fed (feed records)'),

  /// Feed is charged when bought (Expenses → Feed). Only manual, expense-only
  /// feed records are added on top.
  purchases('When bought (feed expenses)');

  const FeedCostBasis(this.label);
  final String label;
}

/// How the purchase price of individual animals is treated.
enum AssetMethod {
  /// Purchase price is kept as an asset; its book value is charged only when
  /// the animal is sold or dies.
  capitalize('Keep as asset (no depreciation)'),

  /// Straight-line depreciation over [FarmProfile.depreciationYears] down to
  /// [FarmProfile.residualPercent] of the price.
  depreciate('Straight-line depreciation');

  const AssetMethod(this.label);
  final String label;
}

/// Farm details and the calculation settings used in reports.
class FarmProfile {
  const FarmProfile({
    required this.name,
    this.location = '',
    this.phone = '',
    this.currency = '৳',
    this.milkPrice = 120,
    this.feedCostBasis = FeedCostBasis.consumption,
    this.assetMethod = AssetMethod.capitalize,
    this.depreciationYears = 5,
    this.residualPercent = 20,
    this.mortalityAlertPercent = 3,
    this.lowMilkPercent = 70,
    this.lowFeedPercent = 70,
    this.healthRecentDays = 3,
    this.healthBaselineDays = 14,
    this.reminderLeadDays = 1,
    this.recoveredShowDays = 30,
    this.defaultVetName = '',
    this.defaultVetPhone = '',
    this.approvalLimit = 20000,
    this.monthlyBudget = 150000,
  });

  factory FarmProfile.fromJson(Map<String, dynamic> json) {
    double num(String key, double fallback) => double.tryParse('${json[key] ?? ''}') ?? fallback;
    return FarmProfile(
      name: '${json['name'] ?? defaults.name}',
      location: '${json['location'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      currency: '${json['currency'] ?? '৳'}',
      milkPrice: num('milkPrice', defaults.milkPrice),
      feedCostBasis: FeedCostBasis.values.firstWhere((v) => v.name == json['feedCostBasis'], orElse: () => FeedCostBasis.consumption),
      assetMethod: AssetMethod.values.firstWhere((v) => v.name == json['assetMethod'], orElse: () => AssetMethod.capitalize),
      depreciationYears: num('depreciationYears', 5),
      residualPercent: num('residualPercent', 20),
      mortalityAlertPercent: num('mortalityAlertPercent', 3),
      lowMilkPercent: num('lowMilkPercent', 70),
      lowFeedPercent: num('lowFeedPercent', 70),
      healthRecentDays: num('healthRecentDays', 3).round(),
      healthBaselineDays: num('healthBaselineDays', 14).round(),
      reminderLeadDays: num('reminderLeadDays', 1).round(),
      recoveredShowDays: num('recoveredShowDays', 30).round(),
      defaultVetName: '${json['defaultVetName'] ?? ''}',
      defaultVetPhone: '${json['defaultVetPhone'] ?? ''}',
      approvalLimit: num('approvalLimit', 20000),
      monthlyBudget: num('monthlyBudget', 150000),
    );
  }

  static const defaults = FarmProfile(name: 'Nabijah Demo Farm', location: 'Gazipur, Dhaka');

  final String name;
  final String location;
  final String phone;
  final String currency;

  /// Price per litre used only to *estimate* the value of milk in an animal's
  /// profile. Reported revenue always comes from actual sales.
  final double milkPrice;

  final FeedCostBasis feedCostBasis;
  final AssetMethod assetMethod;
  final double depreciationYears;
  final double residualPercent;

  /// Alert when a batch loses more than this % of its birds/fish in 7 days.
  final double mortalityAlertPercent;

  /// Alert when an animal's last-7-day milk average falls below this % of
  /// its previous 30-day average.
  final double lowMilkPercent;

  // Health settings.

  /// Review alert when an animal's recent feed intake falls below this % of
  /// its earlier intake.
  final double lowFeedPercent;

  /// Days averaged as "recent" when comparing milk and feed.
  final int healthRecentDays;

  /// Days before the recent window used as the animal's normal level.
  final int healthBaselineDays;

  /// How many days ahead follow-ups and vet visits show as reminders.
  final int reminderLeadDays;

  /// How long an animal shows as "Recovered" after its case is closed.
  final int recoveredShowDays;

  final String defaultVetName;
  final String defaultVetPhone;

  // Owner controls.

  /// An expense or purchase entered by a manager above this amount waits for
  /// the owner's approval and is not counted until approved. 0 = no limit.
  final double approvalLimit;

  /// Planned spending (expenses) per calendar month. 0 = no budget.
  final double monthlyBudget;

  FarmProfile copyWith({
    String? name,
    String? location,
    String? phone,
    String? currency,
    double? milkPrice,
    FeedCostBasis? feedCostBasis,
    AssetMethod? assetMethod,
    double? depreciationYears,
    double? residualPercent,
    double? mortalityAlertPercent,
    double? lowMilkPercent,
    double? lowFeedPercent,
    int? healthRecentDays,
    int? healthBaselineDays,
    int? reminderLeadDays,
    int? recoveredShowDays,
    String? defaultVetName,
    String? defaultVetPhone,
    double? approvalLimit,
    double? monthlyBudget,
  }) =>
      FarmProfile(
        name: name ?? this.name,
        location: location ?? this.location,
        phone: phone ?? this.phone,
        currency: currency ?? this.currency,
        milkPrice: milkPrice ?? this.milkPrice,
        feedCostBasis: feedCostBasis ?? this.feedCostBasis,
        assetMethod: assetMethod ?? this.assetMethod,
        depreciationYears: depreciationYears ?? this.depreciationYears,
        residualPercent: residualPercent ?? this.residualPercent,
        mortalityAlertPercent: mortalityAlertPercent ?? this.mortalityAlertPercent,
        lowMilkPercent: lowMilkPercent ?? this.lowMilkPercent,
        lowFeedPercent: lowFeedPercent ?? this.lowFeedPercent,
        healthRecentDays: healthRecentDays ?? this.healthRecentDays,
        healthBaselineDays: healthBaselineDays ?? this.healthBaselineDays,
        reminderLeadDays: reminderLeadDays ?? this.reminderLeadDays,
        recoveredShowDays: recoveredShowDays ?? this.recoveredShowDays,
        defaultVetName: defaultVetName ?? this.defaultVetName,
        defaultVetPhone: defaultVetPhone ?? this.defaultVetPhone,
        approvalLimit: approvalLimit ?? this.approvalLimit,
        monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        'phone': phone,
        'currency': currency,
        'milkPrice': milkPrice,
        'feedCostBasis': feedCostBasis.name,
        'assetMethod': assetMethod.name,
        'depreciationYears': depreciationYears,
        'residualPercent': residualPercent,
        'mortalityAlertPercent': mortalityAlertPercent,
        'lowMilkPercent': lowMilkPercent,
        'lowFeedPercent': lowFeedPercent,
        'healthRecentDays': healthRecentDays,
        'healthBaselineDays': healthBaselineDays,
        'reminderLeadDays': reminderLeadDays,
        'recoveredShowDays': recoveredShowDays,
        'defaultVetName': defaultVetName,
        'defaultVetPhone': defaultVetPhone,
        'approvalLimit': approvalLimit,
        'monthlyBudget': monthlyBudget,
      };
}
