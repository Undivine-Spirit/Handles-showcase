import '../adapters/exceptions.dart';
import '../adapters/store_adapter.dart';
import 'sourced_listing.dart';
import 'supplier_stock_checker.dart';

enum SourcingMonitorOutcome {
  /// Checked, supplier still has stock - nothing to do.
  stillInStock,

  /// Supplier just went out of stock, and this listing wasn't live
  /// anywhere yet - nothing to delist, just record the status.
  outOfStockNotYetListed,

  /// Supplier went out of stock and this listing WAS live somewhere -
  /// delisted from every store it was on. The actual "out of stock
  /// checker" behavior from `docs/PROJECT_PLAN.md` section 10.
  delistedEverywhere,

  /// Delisting from at least one store failed - recorded, not retried
  /// here (same division of responsibility as `ReconciliationEngine`:
  /// this decides what should happen, not how to retry a failure).
  error,
}

class SourcingMonitorAction {
  SourcingMonitorAction({required this.accountKey, this.detail});

  /// Which store this action applied to - null when the action is about
  /// the listing as a whole (e.g. the stock check itself), not any one
  /// store's delist call.
  final String? accountKey;
  final String? detail;

  @override
  String toString() => '${accountKey ?? '(listing)'}: ${detail ?? ''}';
}

class SourcingMonitorResult {
  SourcingMonitorResult({
    required this.listing,
    required this.outcome,
    required this.actions,
  });

  final SourcedListing listing;
  final SourcingMonitorOutcome outcome;
  final List<SourcingMonitorAction> actions;

  bool get hasError => outcome == SourcingMonitorOutcome.error;
}

/// Checks one [SourcedListing]'s supplier stock and delists it everywhere
/// if the supplier just ran out - `docs/PROJECT_PLAN.md` section 10's
/// supplier stock/price monitor, component 2.
class SourcingMonitor {
  SourcingMonitor({required this.stockChecker, required Map<String, StoreAdapter> adapters})
      : _adapters = adapters;

  final SupplierStockChecker stockChecker;
  final Map<String, StoreAdapter> _adapters;

  Future<SourcingMonitorResult> check(SourcedListing listing) async {
    final status = await stockChecker.checkStock(listing.sourceAsin);
    final now = DateTime.now();

    if (status != SupplierStockStatus.outOfStock) {
      return SourcingMonitorResult(
        listing: listing.copyWith(supplierStatus: status, lastCheckedAt: now),
        outcome: SourcingMonitorOutcome.stillInStock,
        actions: [],
      );
    }

    if (!listing.isLive) {
      return SourcingMonitorResult(
        listing: listing.copyWith(supplierStatus: status, lastCheckedAt: now),
        outcome: SourcingMonitorOutcome.outOfStockNotYetListed,
        actions: [],
      );
    }

    final actions = <SourcingMonitorAction>[];
    var anyError = false;
    final remainingListings = Map<String, String>.from(listing.listings);

    for (final entry in listing.listings.entries) {
      final accountKey = entry.key;
      final externalListingId = entry.value;
      final adapter = _adapters[accountKey];

      if (adapter == null) {
        actions.add(SourcingMonitorAction(
          accountKey: accountKey,
          detail: 'no adapter configured, could not delist - needs manual action',
        ));
        anyError = true;
        continue;
      }

      try {
        await adapter.delist(externalListingId);
        actions.add(SourcingMonitorAction(accountKey: accountKey, detail: 'delisted (supplier out of stock)'));
        remainingListings.remove(accountKey);
      } on StoreAdapterException catch (e) {
        actions.add(SourcingMonitorAction(accountKey: accountKey, detail: 'delist failed: ${e.message}'));
        anyError = true;
      }
    }

    return SourcingMonitorResult(
      listing: listing.copyWith(
        supplierStatus: status,
        lastCheckedAt: now,
        listings: remainingListings,
      ),
      outcome: anyError ? SourcingMonitorOutcome.error : SourcingMonitorOutcome.delistedEverywhere,
      actions: actions,
    );
  }
}
