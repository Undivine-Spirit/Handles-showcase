import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

import 'fakes/fake_store_adapter.dart';

class FakeStockChecker implements SupplierStockChecker {
  FakeStockChecker(this.status);
  SupplierStockStatus status;

  @override
  Future<SupplierStockStatus> checkStock(String asin) async => status;
}

SourcedListing _listing({Map<String, String> listings = const {}}) => SourcedListing(
      sku: 'SRC-0001',
      title: 'Example Sourced Item',
      sourceAsin: 'B00EXAMPLE',
      sourcePrice: 24.99,
      destinationFeeRate: 0.13,
      desiredProfit: 8,
      listings: listings,
    );

void main() {
  group('SourcingMonitor - still in stock', () {
    test('records the status but takes no action', () async {
      final monitor = SourcingMonitor(
        stockChecker: FakeStockChecker(SupplierStockStatus.inStock),
        adapters: {},
      );

      final result = await monitor.check(_listing(listings: {'walmart': 'w-1'}));

      expect(result.outcome, SourcingMonitorOutcome.stillInStock);
      expect(result.actions, isEmpty);
      expect(result.listing.supplierStatus, SupplierStockStatus.inStock);
      expect(result.listing.listings, {'walmart': 'w-1'}, reason: 'still live, untouched');
    });
  });

  group('SourcingMonitor - out of stock, not yet listed anywhere', () {
    test('records the status without trying to delist anything', () async {
      final monitor = SourcingMonitor(
        stockChecker: FakeStockChecker(SupplierStockStatus.outOfStock),
        adapters: {},
      );

      final result = await monitor.check(_listing());

      expect(result.outcome, SourcingMonitorOutcome.outOfStockNotYetListed);
      expect(result.actions, isEmpty);
    });
  });

  group('SourcingMonitor - the actual out-of-stock checker: delist everywhere', () {
    test('delists from every store the item is currently live on', () async {
      final walmartAdapter = FakeStoreAdapter(platform: 'walmart')..seed('w-1', quantity: 3, price: 40);
      final ebayAdapter = FakeStoreAdapter(platform: 'ebay')..seed('e-1', quantity: 3, price: 40);

      final monitor = SourcingMonitor(
        stockChecker: FakeStockChecker(SupplierStockStatus.outOfStock),
        adapters: {'walmart': walmartAdapter, 'ebay_store_a': ebayAdapter},
      );

      final result = await monitor.check(
        _listing(listings: {'walmart': 'w-1', 'ebay_store_a': 'e-1'}),
      );

      expect(result.outcome, SourcingMonitorOutcome.delistedEverywhere);
      expect(result.listing.listings, isEmpty, reason: 'both delisted, none remain live');

      final walmartListing = await walmartAdapter.getListing('w-1');
      final ebayListing = await ebayAdapter.getListing('e-1');
      expect(walmartListing!.isLive, isFalse);
      expect(ebayListing!.isLive, isFalse);
    });

    test('a missing adapter for one store is an error but does not stop the others', () async {
      final walmartAdapter = FakeStoreAdapter(platform: 'walmart')..seed('w-1', quantity: 3, price: 40);

      final monitor = SourcingMonitor(
        stockChecker: FakeStockChecker(SupplierStockStatus.outOfStock),
        adapters: {'walmart': walmartAdapter}, // no adapter for ebay_store_a
      );

      final result = await monitor.check(
        _listing(listings: {'walmart': 'w-1', 'ebay_store_a': 'e-1'}),
      );

      expect(result.outcome, SourcingMonitorOutcome.error);
      expect(result.hasError, isTrue);
      // Walmart still got delisted even though eBay's adapter was missing.
      expect(result.listing.listings, {'ebay_store_a': 'e-1'});
      final walmartListing = await walmartAdapter.getListing('w-1');
      expect(walmartListing!.isLive, isFalse);
    });

    test('a delist call that throws is recorded as an error, not silently dropped', () async {
      final adapter = FakeStoreAdapter(platform: 'walmart')
        ..seed('w-1', quantity: 3, price: 40)
        ..throwOnNextCall = StoreAdapterRequestException('boom');

      final monitor = SourcingMonitor(
        stockChecker: FakeStockChecker(SupplierStockStatus.outOfStock),
        adapters: {'walmart': adapter},
      );

      final result = await monitor.check(_listing(listings: {'walmart': 'w-1'}));

      expect(result.outcome, SourcingMonitorOutcome.error);
      expect(result.listing.listings, {'walmart': 'w-1'}, reason: 'delist failed, still recorded as live');
    });
  });
}
