import 'dart:math' as math;

/// Whether Amazon or the seller handles shipping/storage - the fee
/// structures genuinely differ, not a detail to average away.
enum FulfillmentMethod { fba, fbm }

class AmazonFeeEstimate {
  const AmazonFeeEstimate({
    required this.referralFee,
    required this.fulfillmentFee,
    this.lowInventoryFee = 0,
  });

  final double referralFee;
  final double fulfillmentFee;
  final double lowInventoryFee;

  double get total => referralFee + fulfillmentFee + lowInventoryFee;
}

/// Amazon's own seller fees - referral + FBA fulfillment - per
/// `docs/API_RESEARCH.md`'s researched 2026 rates (frozen since Jan 2024).
/// This is the SAME fee model section 9's profitability calculator was
/// always meant to use; `SourcingPriceCalculator` (section 10) is
/// deliberately a *different* calculator using the DESTINATION platform's
/// fees instead - don't reach for this one when that one is what's needed.
class AmazonFeeModel {
  const AmazonFeeModel();

  static const double minimumReferralFee = 0.30;
  static const double _fuelSurchargeRate = 0.035;

  /// A deliberately small, rough table - most categories sit at 15%, a
  /// handful are documented exceptions. Not exhaustive; verify the actual
  /// category's current rate before relying on this for a real decision,
  /// same caveat `docs/API_RESEARCH.md` already makes.
  double referralRateForCategory(String category) => switch (category.toLowerCase()) {
        'electronics' => 0.08,
        'jewelry' => 0.20,
        'amazon device accessories' => 0.45,
        _ => 0.15,
      };

  /// [fbaBaseFee] is a ballpark for a small/light standard item
  /// (`docs/API_RESEARCH.md`'s researched $3-4 range) - real FBA fees are
  /// weight/dimension-tiered, which this deliberately doesn't model.
  /// Override with a real figure once the item's actual size tier is
  /// known; don't treat the default as accurate for anything but a rough
  /// first pass.
  AmazonFeeEstimate estimate({
    required double price,
    required String category,
    FulfillmentMethod fulfillment = FulfillmentMethod.fba,
    double fbaBaseFee = 3.50,
    bool includeLowInventoryFee = false,
  }) {
    final referral = math.max(price * referralRateForCategory(category), minimumReferralFee);

    final fulfillmentFee =
        fulfillment == FulfillmentMethod.fba ? fbaBaseFee * (1 + _fuelSurchargeRate) : 0.0;

    // Midpoint of the researched $0.89-1.11/unit range - a flag, not a
    // precise figure; only relevant when Amazon's own low-inventory
    // signal actually applies to this item.
    final lowInventoryFee = includeLowInventoryFee ? 1.00 : 0.0;

    return AmazonFeeEstimate(
      referralFee: referral,
      fulfillmentFee: fulfillmentFee,
      lowInventoryFee: lowInventoryFee,
    );
  }
}
