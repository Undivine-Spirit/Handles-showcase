import '../categorization/category.dart';

/// User-configurable preferences - lives behind [SettingsStore] so the app
/// can pick whatever persistence fits each platform without this model
/// caring.
class HandlesSettings {
  const HandlesSettings({
    this.priorityCategories = const [],
    this.customCategories = const [],
    this.defaultDesiredProfit = 8,
    this.defaultDestinationFeeRate = 0.13,
    this.autoSyncIntervalMinutes = 3,
    this.themeId = 'console_navy',
    this.customPaletteColors,
  });

  factory HandlesSettings.fromJson(Map<String, dynamic> json) => HandlesSettings(
        priorityCategories:
            (json['priority_categories'] as List<dynamic>?)?.cast<String>() ?? const [],
        customCategories: (json['custom_categories'] as List<dynamic>?)
                ?.map((c) => Category.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        defaultDesiredProfit: (json['default_desired_profit'] as num?)?.toDouble() ?? 8,
        defaultDestinationFeeRate:
            (json['default_destination_fee_rate'] as num?)?.toDouble() ?? 0.13,
        autoSyncIntervalMinutes: (json['auto_sync_interval_minutes'] as num?)?.toInt() ?? 3,
        themeId: json['theme_id'] as String? ?? 'console_navy',
        customPaletteColors: (json['custom_palette_colors'] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, value as int)),
      );

  /// Category names the user wants surfaced first - in the catalog view,
  /// and eventually as the default scan order for the Amazon profitability
  /// engine (PROJECT_PLAN.md section 9) once that's built. Order matters:
  /// index 0 is highest priority.
  final List<String> priorityCategories;

  /// Categories the user added beyond [defaultCategories], each with its
  /// own keywords for [CategoryRecommender].
  final List<Category> customCategories;

  /// Defaults fed to [SourcingPriceCalculator] when generating a listing
  /// price for a new [SourcedListing] - not secrets (unlike the Keepa API
  /// key or any store's OAuth credentials), just starting points a user
  /// can override per item. `defaultDestinationFeeRate` is a *starting*
  /// guess, not a verified rate for any specific category - same caveat
  /// the calculator's own doc comment already makes.
  final double defaultDesiredProfit;
  final double defaultDestinationFeeRate;

  /// How often the app pulls the catalog repo on its own, while running -
  /// PROJECT_PLAN.md section 11's actual latency budget for a monitor-only
  /// platform delist notification, since for Mercari/Poshmark/Vinted this
  /// polling-and-notifying IS the automation, not a nice-to-have. `0`
  /// disables it (manual "Sync Now" only, the only option before this
  /// existed). Deliberately independent of the *daemon's* own
  /// RECONCILE_INTERVAL_MINUTES (default 15) - polling faster than the
  /// daemon produces new events just means most polls find nothing new,
  /// which is cheap, not wasteful in any way that matters here.
  final int autoSyncIntervalMinutes;

  /// Which built-in palette is active (e.g. `'console_navy'`, the
  /// original/default one), or `'custom'` if [customPaletteColors] should
  /// be used instead. A plain string id, not an enum, so the app package
  /// (where the actual `HandlesPalette` presets live - this is pure Dart,
  /// no `dart:ui` `Color` type available here) can add presets without
  /// this model needing to know their names in advance.
  final String themeId;

  /// Raw ARGB ints (`Color.value`/`Color(...)`, not a Flutter `Color`
  /// itself - same reason as [themeId]) for a user-built palette from the
  /// custom theme maker, keyed by semantic role (`'bg'`, `'surface'`,
  /// `'ink'`, etc. - the app package owns the actual key set). `null`
  /// until the user has built one; [themeId] stays whatever built-in
  /// preset was active until they explicitly switch to `'custom'`.
  final Map<String, int>? customPaletteColors;

  /// The full set a picker/recommender should consider - defaults plus
  /// whatever the user has added, with user edits to a same-named default
  /// category's keywords taking precedence.
  List<Category> get allCategories {
    final byName = {for (final c in defaultCategories) c.name: c};
    for (final custom in customCategories) {
      byName[custom.name] = custom;
    }
    return byName.values.toList();
  }

  HandlesSettings copyWith({
    List<String>? priorityCategories,
    List<Category>? customCategories,
    double? defaultDesiredProfit,
    double? defaultDestinationFeeRate,
    int? autoSyncIntervalMinutes,
    String? themeId,
    Map<String, int>? customPaletteColors,
  }) {
    return HandlesSettings(
      priorityCategories: priorityCategories ?? this.priorityCategories,
      customCategories: customCategories ?? this.customCategories,
      defaultDesiredProfit: defaultDesiredProfit ?? this.defaultDesiredProfit,
      defaultDestinationFeeRate: defaultDestinationFeeRate ?? this.defaultDestinationFeeRate,
      autoSyncIntervalMinutes: autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
      themeId: themeId ?? this.themeId,
      customPaletteColors: customPaletteColors ?? this.customPaletteColors,
    );
  }

  Map<String, dynamic> toJson() => {
        'priority_categories': priorityCategories,
        'custom_categories': customCategories.map((c) => c.toJson()).toList(),
        'default_desired_profit': defaultDesiredProfit,
        'default_destination_fee_rate': defaultDestinationFeeRate,
        'auto_sync_interval_minutes': autoSyncIntervalMinutes,
        'theme_id': themeId,
        if (customPaletteColors != null) 'custom_palette_colors': customPaletteColors,
      };
}

/// Where [HandlesSettings] is persisted - platform-specific implementation
/// lives in the app package (e.g. backed by `shared_preferences`), same
/// split as [CredentialStore] and for the same reason: this package stays
/// plain Dart, no Flutter dependency.
abstract interface class SettingsStore {
  Future<HandlesSettings> load();
  Future<void> save(HandlesSettings settings);
}

/// Keeps settings only for the process lifetime - for tests, or before a
/// real store is wired up.
class InMemorySettingsStore implements SettingsStore {
  HandlesSettings _settings = const HandlesSettings();

  @override
  Future<HandlesSettings> load() async => _settings;

  @override
  Future<void> save(HandlesSettings settings) async => _settings = settings;
}
