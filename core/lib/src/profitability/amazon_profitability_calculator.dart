import 'amazon_fee_model.dart';

enum ProfitabilityVerdict { worthIt, marginal, notWorthIt }

class ProfitabilityResult {
  const ProfitabilityResult({
    required this.netProceeds,
    required this.margin,
    required this.verdict,
    required this.amazonLink,
    required this.fees,
  });

  /// What's left of [ProfitabilityCalculation.observedPrice] after
  /// Amazon's own fees.
  final double netProceeds;

  /// [netProceeds] minus the cost basis - what's actually left over.
  final double margin;

  final ProfitabilityVerdict verdict;

  /// Where a human completes the purchase themselves - Handles never
  /// auto-buys, see `docs/PROJECT_PLAN.md` section 9's "no auto-buy"
  /// decision.
  final String amazonLink;

  final AmazonFeeEstimate fees;
}

/// Section 9's shared calculator - answers "is this worth it on Amazon's
/// own fee structure," serving all three angles the plan describes
/// (sourcing, cross-list, competitive pricing) with the same math, just
/// different `costBasis` inputs from the caller.
class AmazonProfitabilityCalculator {
  const AmazonProfitabilityCalculator({this.feeModel = const AmazonFeeModel()});

  final AmazonFeeModel feeModel;

  /// [marginalThreshold] is the line between "worth it" and "marginal" -
  /// a margin at or below zero is always [ProfitabilityVerdict.notWorthIt]
  /// regardless of this threshold.
  ProfitabilityResult evaluate({
    required String asin,
    required double observedPrice,
    required String category,
    required double costBasis,
    FulfillmentMethod fulfillment = FulfillmentMethod.fba,
    bool includeLowInventoryFee = false,
    double marginalThreshold = 5,
  }) {
    final fees = feeModel.estimate(
      price: observedPrice,
      category: category,
      fulfillment: fulfillment,
      includeLowInventoryFee: includeLowInventoryFee,
    );

    final netProceeds = observedPrice - fees.total;
    final margin = netProceeds - costBasis;

    final verdict = margin <= 0
        ? ProfitabilityVerdict.notWorthIt
        : (margin < marginalThreshold ? ProfitabilityVerdict.marginal : ProfitabilityVerdict.worthIt);

    return ProfitabilityResult(
      netProceeds: netProceeds,
      margin: margin,
      verdict: verdict,
      amazonLink: 'https://www.amazon.com/dp/$asin',
      fees: fees,
    );
  }
}
