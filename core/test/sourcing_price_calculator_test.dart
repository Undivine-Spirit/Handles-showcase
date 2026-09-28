import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  const calculator = SourcingPriceCalculator();

  group('computeListingPrice', () {
    test('solves for a price that leaves the desired profit after the destination fee', () {
      // $20 cost, 13% destination fee, want $10 profit, no shipping.
      // price * 0.87 = 30  =>  price = 30 / 0.87
      final price = calculator.computeListingPrice(
        sourceCost: 20,
        destinationFeeRate: 0.13,
        desiredProfit: 10,
      );

      expect(price, closeTo(34.48, 0.01));

      // Round-trip: plugging that price back in should recover ~$10 profit.
      final profit = calculator.computeActualProfit(
        listingPrice: price,
        sourceCost: 20,
        destinationFeeRate: 0.13,
      );
      expect(profit, closeTo(10, 0.01));
    });

    test('accounts for shipping cost as part of what the price has to cover', () {
      final withShipping = calculator.computeListingPrice(
        sourceCost: 20,
        destinationFeeRate: 0.13,
        desiredProfit: 10,
        shippingCost: 5,
      );
      final withoutShipping = calculator.computeListingPrice(
        sourceCost: 20,
        destinationFeeRate: 0.13,
        desiredProfit: 10,
      );

      expect(withShipping, greaterThan(withoutShipping));
    });

    test('rejects a fee rate expressed as a percentage instead of a fraction', () {
      expect(
        () => calculator.computeListingPrice(sourceCost: 20, destinationFeeRate: 13, desiredProfit: 10),
        throwsArgumentError,
      );
    });
  });

  group('computeActualProfit', () {
    test('a listing price with no cushion above cost+fee yields ~zero profit', () {
      // price covers exactly cost after fees, nothing left over.
      const price = 20 / 0.87; // = cost / (1 - feeRate)
      final profit = calculator.computeActualProfit(
        listingPrice: price,
        sourceCost: 20,
        destinationFeeRate: 0.13,
      );

      expect(profit, closeTo(0, 0.01));
    });

    test('a price too low to cover cost and fees yields a negative profit', () {
      final profit = calculator.computeActualProfit(
        listingPrice: 15,
        sourceCost: 20,
        destinationFeeRate: 0.13,
      );

      expect(profit, lessThan(0));
    });
  });
}
