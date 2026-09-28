/// Computes a listing price for a *sourced* item (bought from a supplier
/// like Amazon, resold on eBay/Walmart/etc.) - deliberately a different
/// formula from section 9's Amazon profitability calculator. That one
/// answers "is it worth selling ON Amazon" (Amazon's own fees apply).
/// This one answers "what should I charge on the DESTINATION platform"
/// (that platform's fees apply instead) - conflating the two would price
/// every sourced listing wrong.
///
/// `destinationFeeRate` is a required parameter, never a hardcoded
/// constant on purpose: eBay/Walmart final-value/referral fees vary by
/// category and change over time (same caveat `docs/API_RESEARCH.md`
/// already makes about Amazon's own fees) - verify the current rate for
/// the actual category before relying on this for a real listing.
class SourcingPriceCalculator {
  const SourcingPriceCalculator();

  /// Solves for the listing price P such that, after the destination
  /// platform takes its cut, [desiredProfit] is what's actually left over
  /// source cost and shipping:
  ///
  ///   P - (P * destinationFeeRate) - sourceCost - shippingCost = desiredProfit
  ///   P * (1 - destinationFeeRate) = sourceCost + shippingCost + desiredProfit
  double computeListingPrice({
    required double sourceCost,
    required double destinationFeeRate,
    required double desiredProfit,
    double shippingCost = 0,
  }) {
    _checkFeeRate(destinationFeeRate);
    return (sourceCost + shippingCost + desiredProfit) / (1 - destinationFeeRate);
  }

  /// The reverse question: given a candidate listing price, what profit
  /// would actually land after the destination platform's fee? Useful for
  /// checking a price someone typed in by hand, not just generating one.
  double computeActualProfit({
    required double listingPrice,
    required double sourceCost,
    required double destinationFeeRate,
    double shippingCost = 0,
  }) {
    _checkFeeRate(destinationFeeRate);
    final feeAmount = listingPrice * destinationFeeRate;
    return listingPrice - feeAmount - sourceCost - shippingCost;
  }

  void _checkFeeRate(double rate) {
    if (rate < 0 || rate >= 1) {
      throw ArgumentError.value(
        rate,
        'destinationFeeRate',
        'must be a fraction between 0 and 1 (e.g. 0.13 for a 13% fee), not a percentage or a raw dollar amount',
      );
    }
  }
}
