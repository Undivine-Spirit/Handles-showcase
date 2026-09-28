import '../adapters/exceptions.dart';
import '../adapters/store_adapter.dart';
import '../catalog_item.dart';

/// What the engine did for one account while reconciling one item - the
/// caller logs/persists these (see `docs/PROJECT_PLAN.md` section 8's
/// event log, and section 11's duty reminders). This engine only decides
/// and reports; it doesn't own logging or git commits itself - those are
/// the separate "GitHub state layer" and "event log" components (section 3).
enum ReconciliationOutcome {
  /// Store already matched the source of truth - nothing to push.
  alreadyInSync,
  created,
  updated,
  delisted,

  /// A real sale happened directly on one or more connected stores since
  /// the last confirmed push, and this pass resolved it: source-of-truth
  /// quantity was decremented by the real total sold, and every other
  /// connected store was cascaded to the new number. See
  /// `ReconciliationEngine`'s own doc comment for the mechanism.
  externalSaleReconciled,

  /// More was sold across connected stores in this pass than the source
  /// of truth had available - two buyers effectively bought the "same"
  /// last unit on two different platforms. Quantity floors at 0 and every
  /// store gets delisted (there really is nothing left), but this always
  /// needs a human: the engine has no way to cancel or refund an order,
  /// and picking a "winner" store isn't its call to make.
  oversold,

  /// The write-then-verify read-back didn't match what was written, the
  /// adapter threw, or an expected listing wasn't found on read. Recorded,
  /// not retried - retry/backoff policy belongs to whatever schedules
  /// calls into this engine, not the engine itself.
  error,
}

class ReconciliationAction {
  ReconciliationAction({
    this.accountKey,
    required this.outcome,
    this.detail,
  });

  /// `null` for an item-level action that isn't really about one account -
  /// [ReconciliationOutcome.externalSaleReconciled] and `.oversold` cover
  /// the whole item, potentially several accounts at once, so smuggling a
  /// comma-joined account list in here would just create a real key
  /// collision the moment there's exactly one seller account (its per-
  /// account action and this summary action would share the same key).
  /// Which accounts were actually involved lives in [detail] instead.
  final String? accountKey;

  final ReconciliationOutcome outcome;
  final String? detail;

  @override
  String toString() =>
      '${accountKey ?? '(item)'}: ${outcome.name}${detail == null ? '' : ' ($detail)'}';
}

class ReconciliationResult {
  ReconciliationResult({required this.item, required this.actions});

  /// The item with each account's `stores` entry updated to reflect what
  /// actually happened, AND - new in v2 - `quantity` itself updated if an
  /// external sale was detected and cascaded. Persist this back to the
  /// catalog repo (the GitHub state layer's job, not this engine's).
  final CatalogItem item;

  final List<ReconciliationAction> actions;

  bool get hasError => actions.any((a) => a.outcome == ReconciliationOutcome.error);
  bool get hasOversold => actions.any((a) => a.outcome == ReconciliationOutcome.oversold);
  bool get hasExternalSale =>
      actions.any((a) => a.outcome == ReconciliationOutcome.externalSaleReconciled);
}

/// Reconciliation engine v2 - `docs/PROJECT_PLAN.md` section 5. Still a
/// one-way push in the sense that the *source of truth stays this item's
/// `quantity` field* - what's new is that this engine now updates that
/// field itself when it detects a real sale on a connected store, instead
/// of only ever pushing outward and flagging a drop for a human (v1's
/// `conflictDetected`, removed - see below).
///
/// **The mechanism, in order:**
/// 1. Read every connected store's live quantity.
/// 2. For each store, compare it against [StoreListingState.lastConfirmedQuantity]
///    - what that store showed the last time this engine verified a write.
///    A drop below that baseline is a real sale on that channel; a store
///    with no baseline yet (never been through a v2 write-then-verify) is
///    skipped, not treated as a mystery sale - there's nothing to compare
///    against yet.
/// 3. **Sum the drops across every store**, not just the first one found -
///    two channels can each sell real units in the same pass, and only
///    counting one would silently undercount. This is the fix for the
///    "remote is behind because of an external sale" vs. "remote is
///    behind because we haven't pushed a restock yet" ambiguity v1 could
///    never resolve (it flagged both as `conflictDetected` for a human).
/// 4. New quantity = old quantity minus total sold, floored at 0. If the
///    total sold would have gone negative - a genuine oversell, two
///    platforms each selling what was really one last unit - that's
///    [ReconciliationOutcome.oversold], not auto-resolved. See its own
///    doc comment for why.
/// 5. Push the new quantity to every connected store (create/update/
///    delist, same shape as v1), including whichever store the sale was
///    detected on - it usually already matches, so this is typically a
///    no-op "already in sync" there and a real push everywhere else.
class ReconciliationEngine {
  ReconciliationEngine({required Map<String, StoreAdapter> adapters})
      : _adapters = adapters;

  final Map<String, StoreAdapter> _adapters;

  Future<ReconciliationResult> reconcile(CatalogItem item) async {
    // Phase 1: read every connected, already-listed store's live state.
    // A store with no adapter (monitor-only/not wired up - section 13) or
    // no listing yet is left out entirely; phase 3 handles "not listed
    // yet" on its own.
    final remotes = <String, RemoteListing?>{};
    final readErrors = <String, String>{};

    for (final entry in item.stores.entries) {
      final accountKey = entry.key;
      final state = entry.value;
      final adapter = _adapters[accountKey];
      if (adapter == null || state.externalListingId == null) continue;

      try {
        remotes[accountKey] = await adapter.getListing(state.externalListingId!);
      } on StoreAdapterException catch (e) {
        readErrors[accountKey] = e.message;
      }
    }

    // Phase 2: sum real external sales since each store's own last
    // confirmed baseline - the actual two-way-merge math (section 5).
    var totalSold = 0;
    for (final entry in item.stores.entries) {
      final remote = remotes[entry.key];
      final baseline = entry.value.lastConfirmedQuantity;
      if (remote == null || baseline == null) continue;
      final drop = baseline - remote.quantity;
      if (drop > 0) totalSold += drop;
    }

    final oversold = totalSold > item.quantity;
    final newQuantity = totalSold >= item.quantity ? 0 : item.quantity - totalSold;

    // Phase 3: push newQuantity to every connected store.
    final updatedStores = Map<String, StoreListingState>.from(item.stores);
    final actions = <ReconciliationAction>[];
    final saleAccounts = <String>[];

    for (final entry in item.stores.entries) {
      final accountKey = entry.key;
      final state = entry.value;
      final adapter = _adapters[accountKey];
      if (adapter == null) continue;

      final remote = remotes[accountKey];
      final baseline = state.lastConfirmedQuantity;
      if (remote != null && baseline != null && baseline - remote.quantity > 0) {
        saleAccounts.add(accountKey);
      }

      if (readErrors.containsKey(accountKey)) {
        actions.add(ReconciliationAction(
          accountKey: accountKey,
          outcome: ReconciliationOutcome.error,
          detail: readErrors[accountKey],
        ));
        updatedStores[accountKey] = state.copyWith(syncStatus: SyncStatus.error);
        continue;
      }

      try {
        final (action, nextState) =
            await _reconcileOneToQuantity(item, accountKey, state, adapter, remote, newQuantity);
        actions.add(action);
        updatedStores[accountKey] = nextState;
      } on StoreAdapterException catch (e) {
        actions.add(ReconciliationAction(
          accountKey: accountKey,
          outcome: ReconciliationOutcome.error,
          detail: e.message,
        ));
        updatedStores[accountKey] = state.copyWith(syncStatus: SyncStatus.error);
      }
    }

    if (oversold) {
      actions.add(ReconciliationAction(
        outcome: ReconciliationOutcome.oversold,
        detail: 'sold $totalSold total on ${saleAccounts.join(', ')} but only '
            '${item.quantity} were available - a human needs to cancel/refund one order',
      ));
    } else if (totalSold > 0) {
      actions.add(ReconciliationAction(
        outcome: ReconciliationOutcome.externalSaleReconciled,
        detail: 'sold $totalSold total on ${saleAccounts.join(', ')}; quantity '
            '${item.quantity} -> $newQuantity, cascaded to every connected store',
      ));
    }

    return ReconciliationResult(
      item: item.copyWith(quantity: newQuantity, stores: updatedStores),
      actions: actions,
    );
  }

  Future<(ReconciliationAction, StoreListingState)> _reconcileOneToQuantity(
    CatalogItem item,
    String accountKey,
    StoreListingState state,
    StoreAdapter adapter,
    RemoteListing? remote,
    int targetQuantity,
  ) async {
    final notYetListed = state.externalListingId == null;

    if (notYetListed) {
      if (targetQuantity == 0) {
        // Never create a listing for something that's already at zero.
        return (
          ReconciliationAction(
            accountKey: accountKey,
            outcome: ReconciliationOutcome.alreadyInSync,
            detail: 'sold out, never listed',
          ),
          state.copyWith(syncStatus: SyncStatus.confirmed, lastConfirmedQuantity: 0),
        );
      }
      return await _createAndVerify(item, accountKey, adapter, targetQuantity);
    }

    if (remote == null) {
      // We think there's a listing; the store disagrees. Don't guess why
      // - flag it rather than silently recreating.
      return (
        ReconciliationAction(
          accountKey: accountKey,
          outcome: ReconciliationOutcome.error,
          detail: 'expected listing ${state.externalListingId} not found on store',
        ),
        state.copyWith(syncStatus: SyncStatus.error),
      );
    }

    if (targetQuantity == 0) {
      if (!remote.isLive) {
        return (
          ReconciliationAction(accountKey: accountKey, outcome: ReconciliationOutcome.alreadyInSync),
          state.copyWith(
            syncStatus: SyncStatus.confirmed,
            lastSyncedAt: DateTime.now(),
            lastConfirmedQuantity: 0,
          ),
        );
      }
      return await _delistAndVerify(state, accountKey, adapter);
    }

    if (remote.quantity == targetQuantity && remote.price == item.price) {
      return (
        ReconciliationAction(accountKey: accountKey, outcome: ReconciliationOutcome.alreadyInSync),
        state.copyWith(
          syncStatus: SyncStatus.confirmed,
          lastSyncedAt: DateTime.now(),
          lastConfirmedQuantity: targetQuantity,
        ),
      );
    }

    return await _updateAndVerify(item, state, accountKey, adapter, remote, targetQuantity);
  }

  Future<(ReconciliationAction, StoreListingState)> _createAndVerify(
    CatalogItem item,
    String accountKey,
    StoreAdapter adapter,
    int targetQuantity,
  ) async {
    final created = await adapter.createListing(item.copyWith(quantity: targetQuantity));
    final verified = await adapter.getListing(created.externalListingId);

    final matches = verified != null &&
        verified.quantity == targetQuantity &&
        verified.price == item.price;

    return (
      ReconciliationAction(
        accountKey: accountKey,
        outcome: matches ? ReconciliationOutcome.created : ReconciliationOutcome.error,
        detail: matches ? null : 'write-then-verify mismatch after create',
      ),
      StoreListingState(
        platform: adapter.platform,
        externalListingId: created.externalListingId,
        externalOfferId: created.externalOfferId,
        lastSyncedAt: DateTime.now(),
        syncStatus: matches ? SyncStatus.confirmed : SyncStatus.error,
        lastConfirmedQuantity: matches ? targetQuantity : null,
      ),
    );
  }

  Future<(ReconciliationAction, StoreListingState)> _updateAndVerify(
    CatalogItem item,
    StoreListingState state,
    String accountKey,
    StoreAdapter adapter,
    RemoteListing before,
    int targetQuantity,
  ) async {
    await adapter.updateListing(
      state.externalListingId!,
      quantity: before.quantity != targetQuantity ? targetQuantity : null,
      price: before.price != item.price ? item.price : null,
    );

    final verified = await adapter.getListing(state.externalListingId!);
    final matches = verified != null &&
        verified.quantity == targetQuantity &&
        verified.price == item.price;

    return (
      ReconciliationAction(
        accountKey: accountKey,
        outcome: matches ? ReconciliationOutcome.updated : ReconciliationOutcome.error,
        detail: matches ? null : 'write-then-verify mismatch after update',
      ),
      state.copyWith(
        syncStatus: matches ? SyncStatus.confirmed : SyncStatus.error,
        lastSyncedAt: DateTime.now(),
        lastConfirmedQuantity: matches ? targetQuantity : state.lastConfirmedQuantity,
      ),
    );
  }

  Future<(ReconciliationAction, StoreListingState)> _delistAndVerify(
    StoreListingState state,
    String accountKey,
    StoreAdapter adapter,
  ) async {
    await adapter.delist(state.externalListingId!);

    final verified = await adapter.getListing(state.externalListingId!);
    final confirmed = verified == null || !verified.isLive;

    return (
      ReconciliationAction(
        accountKey: accountKey,
        outcome: confirmed ? ReconciliationOutcome.delisted : ReconciliationOutcome.error,
        detail: confirmed ? null : 'store still reports this listing as live after withdraw',
      ),
      state.copyWith(
        syncStatus: confirmed ? SyncStatus.confirmed : SyncStatus.error,
        lastSyncedAt: DateTime.now(),
        lastConfirmedQuantity: confirmed ? 0 : state.lastConfirmedQuantity,
      ),
    );
  }
}
