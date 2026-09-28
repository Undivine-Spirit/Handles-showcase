import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('SourcedListing JSON round-trip', () {
    test('preserves every field, listings map included', () {
      final listing = SourcedListing(
        sku: 'SRC-0001',
        title: 'Example Sourced Item',
        sourceAsin: 'B00EXAMPLE',
        sourcePrice: 24.99,
        destinationFeeRate: 0.13,
        desiredProfit: 8,
        supplierStatus: SupplierStockStatus.inStock,
        lastCheckedAt: DateTime.utc(2026, 8, 27, 12),
        listings: {'walmart': 'w-123'},
      );

      final restored = SourcedListing.fromJson(listing.toJson());

      expect(restored.sku, 'SRC-0001');
      expect(restored.sourceAsin, 'B00EXAMPLE');
      expect(restored.supplierStatus, SupplierStockStatus.inStock);
      expect(restored.listings, {'walmart': 'w-123'});
      expect(restored.lastCheckedAt, DateTime.utc(2026, 8, 27, 12));
    });

    test('defaults supplier status to unknown when absent, not out-of-stock', () {
      final json = {
        'sku': 'SRC-0002',
        'title': 'Item',
        'source_asin': 'B00X',
        'source_price': 10.0,
        'destination_fee_rate': 0.13,
        'desired_profit': 5.0,
        'listings': <String, dynamic>{},
      };

      final listing = SourcedListing.fromJson(json);

      expect(listing.supplierStatus, SupplierStockStatus.unknown);
    });
  });

  group('SourcedListing.isLive / isSourcedOut', () {
    test('isLive is false with no listings, true with at least one', () {
      final notLive = SourcedListing(
        sku: 'a',
        title: 'a',
        sourceAsin: 'B00A',
        sourcePrice: 10,
        destinationFeeRate: 0.13,
        desiredProfit: 5,
      );
      expect(notLive.isLive, isFalse);

      final live = notLive.copyWith(listings: {'walmart': 'w-1'});
      expect(live.isLive, isTrue);
    });

    test('isSourcedOut reflects supplierStatus, not listings', () {
      final listing = SourcedListing(
        sku: 'a',
        title: 'a',
        sourceAsin: 'B00A',
        sourcePrice: 10,
        destinationFeeRate: 0.13,
        desiredProfit: 5,
        supplierStatus: SupplierStockStatus.outOfStock,
      );

      expect(listing.isSourcedOut, isTrue);
    });
  });
}
