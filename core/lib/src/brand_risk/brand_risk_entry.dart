/// Where a [BrandRiskEntry] came from - not a quality ranking, just
/// provenance, since the two sources mean different things to a human
/// reviewing a flag: [curated] is "someone else's brand/complaint you
/// should know about," [ownHistory] is "this already happened to us."
enum BrandRiskSource {
  curated,
  ownHistory;

  static BrandRiskSource fromJson(String value) => switch (value) {
        'curated' => BrandRiskSource.curated,
        'own_history' => BrandRiskSource.ownHistory,
        _ => throw ArgumentError('Unknown brand risk source: $value'),
      };

  String toJson() => switch (this) {
        BrandRiskSource.curated => 'curated',
        BrandRiskSource.ownHistory => 'own_history',
      };
}

/// One entry in the known-risk list `BrandRiskChecker` matches against -
/// `docs/PROJECT_PLAN.md` section 10's 2026-08-29 research note. This is a
/// blocklist entry, not a legal determination: it means "this brand has
/// shown up as a resale risk before," never "every other brand is safe."
class BrandRiskEntry {
  BrandRiskEntry({
    required this.brand,
    required this.reason,
    required this.source,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().toUtc();

  factory BrandRiskEntry.fromJson(Map<String, dynamic> json) => BrandRiskEntry(
        brand: json['brand'] as String,
        reason: json['reason'] as String,
        source: BrandRiskSource.fromJson(json['source'] as String),
        addedAt: DateTime.parse(json['added_at'] as String),
      );

  /// Matched case-insensitively (see `BrandRiskChecker._normalize`) - the
  /// exact casing here is just for display.
  final String brand;

  /// Human-readable - e.g. "Known eBay VeRO enforcer", "Licensed toy
  /// brand - high complaint category", "Delisted for IP complaint on
  /// eBay, 2026-08-15" (an own-history entry).
  final String reason;

  final BrandRiskSource source;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'reason': reason,
        'source': source.toJson(),
        'added_at': addedAt.toIso8601String(),
      };
}
