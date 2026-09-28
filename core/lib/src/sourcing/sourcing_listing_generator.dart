import '../adapters/exceptions.dart';
import '../adapters/store_adapter.dart';
import '../brand_risk/brand_risk_checker.dart';
import '../catalog_item.dart';
import 'sourced_listing.dart';
import 'sourcing_price_calculator.dart';

enum PublishOutcome {
  published,
  error,

  /// Not attempted - the brand matched `BrandRiskChecker`, so this is
  /// held for a human to review rather than auto-published. See
  /// `SourcingListingGenerator`'s own doc comment for why this stops the
  /// whole listing rather than just flagging it after the fact.
  heldForBrandRiskReview,
}

class PublishAction {
  PublishAction({required this.accountKey, required this.outcome, this.detail});

  final String accountKey;
  final PublishOutcome outcome;
  final String? detail;

  @override
  String toString() => '$accountKey: ${outcome.name}${detail == null ? '' : ' ($detail)'}';
}

class PublishResult {
  PublishResult({required this.listing, required this.actions});

  final SourcedListing listing;
  final List<PublishAction> actions;

  bool get hasError => actions.any((a) => a.outcome == PublishOutcome.error);
  bool get hasHeldForReview =>
      actions.any((a) => a.outcome == PublishOutcome.heldForBrandRiskReview);
}

/// Component 3 of `docs/PROJECT_PLAN.md` section 10: given a
/// [SourcedListing] that's cleared whatever profitability bar the caller
/// applied, computes its listing price and pushes it live via the same
/// [StoreAdapter] every other component uses - Walmart and eBay both work
/// here with zero sourcing-specific adapter code, which is the entire
/// point of sharing the interface.
///
/// If [riskChecker] is given and [SourcedListing.brand] matches it, this
/// stops before calling any adapter at all rather than publishing and
/// flagging it after the fact - the whole point of the check (section
/// 10's 2026-08-29 research note) is to keep a legal problem from ever
/// going live in the first place, not to log one once it has. A human
/// has to act (there's no "publish anyway" here yet - see the plan doc)
/// to actually push a held listing.
class SourcingListingGenerator {
  SourcingListingGenerator({
    required Map<String, StoreAdapter> adapters,
    this.priceCalculator = const SourcingPriceCalculator(),
    this.riskChecker,
  }) : _adapters = adapters;

  final Map<String, StoreAdapter> _adapters;
  final SourcingPriceCalculator priceCalculator;
  final BrandRiskChecker? riskChecker;

  /// Publishes to every account in [targetAccountKeys] that isn't already
  /// in [SourcedListing.listings] - already-live accounts are left alone,
  /// not republished, so calling this again after a partial failure only
  /// retries what actually failed.
  Future<PublishResult> publish(SourcedListing listing, List<String> targetAccountKeys) async {
    final actions = <PublishAction>[];
    final updatedListings = Map<String, String>.from(listing.listings);

    final brand = listing.brand;
    if (riskChecker != null && brand != null && brand.isNotEmpty) {
      final verdict = riskChecker!.check(brand);
      if (verdict.isFlagged) {
        for (final accountKey in targetAccountKeys) {
          if (updatedListings.containsKey(accountKey)) continue;
          actions.add(PublishAction(
            accountKey: accountKey,
            outcome: PublishOutcome.heldForBrandRiskReview,
            detail: verdict.matchedEntry!.reason,
          ));
        }
        return PublishResult(listing: listing, actions: actions);
      }
    }

    final price = priceCalculator.computeListingPrice(
      sourceCost: listing.sourcePrice,
      destinationFeeRate: listing.destinationFeeRate,
      desiredProfit: listing.desiredProfit,
      shippingCost: listing.shippingCost,
    );

    for (final accountKey in targetAccountKeys) {
      if (updatedListings.containsKey(accountKey)) continue;

      final adapter = _adapters[accountKey];
      if (adapter == null) {
        actions.add(PublishAction(
          accountKey: accountKey,
          outcome: PublishOutcome.error,
          detail: 'no adapter configured for this account',
        ));
        continue;
      }

      try {
        // A transient bridge to CatalogItem, not a modeling decision -
        // StoreAdapter.createListing's signature is shared with the
        // reconciliation engine's owned-inventory flow, and changing it
        // just for sourced listings would ripple through every adapter.
        // Nothing here gets persisted as a CatalogItem; it exists only
        // for the length of this one API call. See SourcedListing's own
        // doc comment for why the two models stay separate everywhere
        // that actually matters (persistence, "out of stock" meaning).
        final bridgeItem = CatalogItem(
          sku: listing.sku,
          title: listing.title,
          description: listing.description,
          price: price,
          quantity: 1,
          category: listing.category,
        );

        final created = await adapter.createListing(bridgeItem);
        updatedListings[accountKey] = created.externalListingId;
        actions.add(PublishAction(accountKey: accountKey, outcome: PublishOutcome.published));
      } on StoreAdapterException catch (e) {
        actions.add(PublishAction(
          accountKey: accountKey,
          outcome: PublishOutcome.error,
          detail: e.message,
        ));
      }
    }

    return PublishResult(
      listing: listing.copyWith(listings: updatedListings),
      actions: actions,
    );
  }
}
