import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

import 'fakes/fake_store_adapter.dart';

SourcedListing _listing({Map<String, String> listings = const {}, String? brand}) => SourcedListing(
      sku: 'SRC-0001',
      title: 'Example Sourced Item',
      sourceAsin: 'B00EXAMPLE',
      sourcePrice: 20,
      destinationFeeRate: 0.13,
      desiredProfit: 10,
      listings: listings,
      brand: brand,
    );

void main() {
  group('SourcingListingGenerator.publish', () {
    test('computes the listing price once and pushes it to every target account', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart');
      final ebay = FakeStoreAdapter(platform: 'ebay');
      final generator = SourcingListingGenerator(
        adapters: {'walmart': walmart, 'ebay_store_a': ebay},
      );

      final result = await generator.publish(_listing(), ['walmart', 'ebay_store_a']);

      expect(result.hasError, isFalse);
      expect(result.actions.map((a) => a.outcome), everyElement(PublishOutcome.published));
      expect(result.listing.listings.keys, containsAll(['walmart', 'ebay_store_a']));
      expect(result.listing.isLive, isTrue);

      // (20 + 10) / (1 - 0.13) = 34.48... - both stores get the same price.
      final walmartListing = await walmart.getListing(result.listing.listings['walmart']!);
      final ebayListing = await ebay.getListing(result.listing.listings['ebay_store_a']!);
      expect(walmartListing!.price, closeTo(34.48, 0.01));
      expect(ebayListing!.price, closeTo(34.48, 0.01));
    });

    test('skips an account that is already live rather than republishing it', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart')..seed('existing-id', quantity: 1, price: 34.48);
      final generator = SourcingListingGenerator(adapters: {'walmart': walmart});
      final alreadyLive = _listing(listings: {'walmart': 'existing-id'});

      final result = await generator.publish(alreadyLive, ['walmart']);

      expect(result.actions, isEmpty, reason: 'nothing new to do - already live there');
      expect(result.listing.listings['walmart'], 'existing-id', reason: 'untouched, not republished');
    });

    test('a missing adapter for one target is an error but does not block the others', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart');
      final generator = SourcingListingGenerator(adapters: {'walmart': walmart});

      final result = await generator.publish(_listing(), ['walmart', 'ebay_store_a']);

      expect(result.hasError, isTrue);
      expect(result.listing.listings.keys, ['walmart']);
      final errorAction = result.actions.firstWhere((a) => a.accountKey == 'ebay_store_a');
      expect(errorAction.outcome, PublishOutcome.error);
    });

    test('an adapter throwing on create is recorded as an error, not a crash', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart')
        ..throwOnNextCall = StoreAdapterRequestException('boom');
      final generator = SourcingListingGenerator(adapters: {'walmart': walmart});

      final result = await generator.publish(_listing(), ['walmart']);

      expect(result.hasError, isTrue);
      expect(result.listing.isLive, isFalse);
    });

    test('a flagged brand is held for review and never reaches the adapter', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart');
      final generator = SourcingListingGenerator(
        adapters: {'walmart': walmart},
        riskChecker: BrandRiskChecker([
          BrandRiskEntry(brand: 'Nike', reason: 'Known eBay VeRO enforcer', source: BrandRiskSource.curated),
        ]),
      );

      final result = await generator.publish(_listing(brand: 'Nike'), ['walmart']);

      expect(result.hasHeldForReview, isTrue);
      expect(result.hasError, isFalse);
      expect(result.listing.isLive, isFalse, reason: 'never published anywhere');
      expect(result.actions.single.outcome, PublishOutcome.heldForBrandRiskReview);
      expect(result.actions.single.detail, 'Known eBay VeRO enforcer');
      expect(await walmart.getListing('anything'), isNull, reason: 'createListing was never called');
    });

    test('a brand risk checker does not block a brand that is not on the list', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart');
      final generator = SourcingListingGenerator(
        adapters: {'walmart': walmart},
        riskChecker: BrandRiskChecker([
          BrandRiskEntry(brand: 'Nike', reason: 'Known eBay VeRO enforcer', source: BrandRiskSource.curated),
        ]),
      );

      final result = await generator.publish(_listing(brand: 'Some Generic Brand'), ['walmart']);

      expect(result.hasHeldForReview, isFalse);
      expect(result.listing.isLive, isTrue);
    });

    test('no brand set means the risk check is skipped, not treated as clear', () async {
      final walmart = FakeStoreAdapter(platform: 'walmart');
      final generator = SourcingListingGenerator(
        adapters: {'walmart': walmart},
        riskChecker: BrandRiskChecker([
          BrandRiskEntry(brand: 'Nike', reason: 'Known eBay VeRO enforcer', source: BrandRiskSource.curated),
        ]),
      );

      final result = await generator.publish(_listing(), ['walmart']);

      expect(result.hasHeldForReview, isFalse);
      expect(result.listing.isLive, isTrue);
    });
  });
}
