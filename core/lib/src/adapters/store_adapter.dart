import '../catalog_item.dart';

/// A store's live state for one listing, as read back from the
/// marketplace itself - used by the (future) reconciliation engine's
/// write-then-verify loop and by the two-way conflict check
/// (`docs/PROJECT_PLAN.md` section 5).
class RemoteListing {
  RemoteListing({
    required this.externalListingId,
    this.externalOfferId,
    required this.quantity,
    required this.price,
    required this.isLive,
  });

  final String externalListingId;
  final String? externalOfferId;
  final int quantity;
  final double price;

  /// `false` for a withdrawn/ended/out-of-stock listing - distinct from
  /// "doesn't exist" (that's a [StoreAdapterNotFoundException] instead).
  final bool isLive;
}

/// Result of creating a new listing - just enough to record into the
/// catalog's `stores` map (`external_listing_id` / `external_offer_id`).
class CreatedListing {
  CreatedListing({required this.externalListingId, this.externalOfferId});

  final String externalListingId;
  final String? externalOfferId;
}

/// Shared interface every marketplace adapter implements -
/// `docs/PROJECT_PLAN.md` section 3, component 1. One adapter instance is
/// bound to a single store *account* (not just a platform) - see
/// `StoreAccount` and `catalog/stores.json`. A seller with two eBay
/// stores holds two [StoreAdapter] instances, each with its own
/// credentials, not one shared instance.
///
/// Implementations should NOT implement retry/backoff themselves beyond
/// what's needed to make a single call succeed or fail cleanly - that
/// policy belongs to the reconciliation engine, which calls these methods
/// and decides what to do with the [StoreAdapterException] it gets back.
abstract interface class StoreAdapter {
  /// The `platform` value this adapter handles - e.g. `'ebay'`. Matches
  /// `StoreAccount.platform` and the `platform` field inside a catalog
  /// item's `stores` entry.
  String get platform;

  /// Read the store's current live state for an existing listing. `null`
  /// if the listing doesn't exist (deliberately not an exception - "not
  /// found" is an expected outcome here, e.g. before the first create).
  Future<RemoteListing?> getListing(String externalListingId);

  /// Lighter-weight than [getListing] when only the stock level is
  /// needed - e.g. for a frequent polling pass.
  Future<int> getInventory(String externalListingId);

  /// Publish [item] as a new listing. Throws if a listing already exists
  /// for this SKU on this account - call [updateListing] instead.
  Future<CreatedListing> createListing(CatalogItem item);

  /// Push a quantity and/or price change to an existing listing. Pass only
  /// the fields that changed; `null` means "leave as-is".
  Future<void> updateListing(
    String externalListingId, {
    int? quantity,
    double? price,
  });

  /// End the live listing (per `docs/PROJECT_PLAN.md` section 5's
  /// auto-unlist-on-zero rule). Implementations should prefer a reversible
  /// operation (e.g. eBay's "withdraw offer") over deleting the underlying
  /// product data, so the SKU can be relisted later without recreating it
  /// from scratch.
  Future<void> delist(String externalListingId);
}
