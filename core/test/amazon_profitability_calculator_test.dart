import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('AmazonFeeModel', () {
    const model = AmazonFeeModel();

    test('applies the standard 15% referral rate for an unrecognized category', () {
      final estimate = model.estimate(price: 100, category: 'Home & Kitchen');
      expect(estimate.referralFee, 15);
    });

    test('applies the documented exceptions correctly', () {
      expect(model.estimate(price: 100, category: 'Electronics').referralFee, 8);
      expect(model.estimate(price: 100, category: 'Jewelry').referralFee, 20);
    });

    test(r'enforces the $0.30 minimum referral fee on a cheap item', () {
      final estimate = model.estimate(price: 1, category: 'Home & Kitchen');
      expect(estimate.referralFee, AmazonFeeModel.minimumReferralFee);
    });

    test('FBM has no fulfillment fee, FBA does', () {
      final fbm = model.estimate(price: 50, category: 'Home & Kitchen', fulfillment: FulfillmentMethod.fbm);
      final fba = model.estimate(price: 50, category: 'Home & Kitchen', fulfillment: FulfillmentMethod.fba);

      expect(fbm.fulfillmentFee, 0);
      expect(fba.fulfillmentFee, greaterThan(0));
    });

    test('low-inventory fee only applies when explicitly flagged', () {
      final without = model.estimate(price: 50, category: 'Home & Kitchen');
      final with_ = model.estimate(price: 50, category: 'Home & Kitchen', includeLowInventoryFee: true);

      expect(without.lowInventoryFee, 0);
      expect(with_.lowInventoryFee, greaterThan(0));
    });
  });

  group('AmazonProfitabilityCalculator', () {
    const calculator = AmazonProfitabilityCalculator();

    test('a healthy margin is worth it', () {
      final result = calculator.evaluate(
        asin: 'B00EXAMPLE',
        observedPrice: 100,
        category: 'Home & Kitchen',
        costBasis: 30,
      );

      expect(result.verdict, ProfitabilityVerdict.worthIt);
      expect(result.margin, greaterThan(5));
      expect(result.amazonLink, 'https://www.amazon.com/dp/B00EXAMPLE');
    });

    test('a thin margin is marginal, not worth-it', () {
      // netProceeds ~= 100 - (15 + 3.6225) = ~81.38; costBasis close to
      // that leaves only a couple of dollars of margin.
      final result = calculator.evaluate(
        asin: 'B00EXAMPLE',
        observedPrice: 100,
        category: 'Home & Kitchen',
        costBasis: 78,
      );

      expect(result.verdict, ProfitabilityVerdict.marginal);
    });

    test('a negative margin is not worth it, never "marginal"', () {
      final result = calculator.evaluate(
        asin: 'B00EXAMPLE',
        observedPrice: 20,
        category: 'Home & Kitchen',
        costBasis: 50,
      );

      expect(result.verdict, ProfitabilityVerdict.notWorthIt);
      expect(result.margin, lessThan(0));
    });

    test('exposes the fee breakdown, not just the final verdict', () {
      final result = calculator.evaluate(
        asin: 'B00EXAMPLE',
        observedPrice: 100,
        category: 'Electronics',
        costBasis: 30,
      );

      expect(result.fees.referralFee, 8);
    });
  });
}
