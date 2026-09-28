import 'package:handles_core/handles_core.dart';

/// In-memory [StoreAdapter] test double - no network, no eBay-specific
/// shape, just enough state to drive [ReconciliationEngine] scenarios.
class FakeStoreAdapter implements StoreAdapter {
  FakeStoreAdapter({this.platform = 'fake'});

  @override
  final String platform;

  final Map<String, RemoteListing> _listings = {};

  var _nextId = 0;

  /// Seed a listing directly, as if it already existed on the store before
  /// the engine ever looked at it - for setting up conflict/mismatch
  /// scenarios.
  void seed(String externalListingId, {required int quantity, required double price, bool isLive = true}) {
    _listings[externalListingId] = RemoteListing(
      externalListingId: externalListingId,
      quantity: quantity,
      price: price,
      isLive: isLive,
    );
  }

  /// If set, the next matching call throws this instead of doing anything -
  /// for exercising the engine's error path.
  StoreAdapterException? throwOnNextCall;

  /// If true, writes succeed but the listing silently doesn't reflect the
  /// change afterward - for exercising write-then-verify mismatch handling.
  bool simulateWriteDriftOnce = false;

  void _maybeThrow() {
    final toThrow = throwOnNextCall;
    if (toThrow != null) {
      throwOnNextCall = null;
      throw toThrow;
    }
  }

  @override
  Future<RemoteListing?> getListing(String externalListingId) async {
    _maybeThrow();
    return _listings[externalListingId];
  }

  @override
  Future<int> getInventory(String externalListingId) async {
    return _listings[externalListingId]?.quantity ?? 0;
  }

  @override
  Future<CreatedListing> createListing(CatalogItem item) async {
    _maybeThrow();
    final id = 'fake-${_nextId++}';
    if (!simulateWriteDriftOnce) {
      _listings[id] = RemoteListing(
        externalListingId: id,
        quantity: item.quantity,
        price: item.price,
        isLive: true,
      );
    } else {
      simulateWriteDriftOnce = false;
      _listings[id] = RemoteListing(
        externalListingId: id,
        quantity: item.quantity + 999, // deliberately wrong
        price: item.price,
        isLive: true,
      );
    }
    return CreatedListing(externalListingId: id);
  }

  @override
  Future<void> updateListing(String externalListingId, {int? quantity, double? price}) async {
    _maybeThrow();
    final existing = _listings[externalListingId];
    if (existing == null) return;
    if (simulateWriteDriftOnce) {
      simulateWriteDriftOnce = false;
      return; // pretend to update but don't actually change anything
    }
    _listings[externalListingId] = RemoteListing(
      externalListingId: externalListingId,
      quantity: quantity ?? existing.quantity,
      price: price ?? existing.price,
      isLive: existing.isLive,
    );
  }

  @override
  Future<void> delist(String externalListingId) async {
    _maybeThrow();
    final existing = _listings[externalListingId];
    if (existing == null) return;
    if (simulateWriteDriftOnce) {
      simulateWriteDriftOnce = false;
      return; // pretend to withdraw but leave it live
    }
    _listings[externalListingId] = RemoteListing(
      externalListingId: externalListingId,
      quantity: existing.quantity,
      price: existing.price,
      isLive: false,
    );
  }
}
