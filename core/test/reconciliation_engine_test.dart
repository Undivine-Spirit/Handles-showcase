import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

import 'fakes/fake_store_adapter.dart';

CatalogItem _item({
  int quantity = 5,
  double price = 109,
  Map<String, StoreListingState> stores = const {},
}) =>
    CatalogItem(
      sku: 'HND-0142',
      title: "Nike Air Force 1 '07 - Triple White",
      price: price,
      quantity: quantity,
      stores: stores,
    );

StoreListingState _confirmed(String id, {required int lastConfirmedQuantity}) => StoreListingState(
      platform: 'ebay',
      externalListingId: id,
      syncStatus: SyncStatus.confirmed,
      lastConfirmedQuantity: lastConfirmedQuantity,
    );

void main() {
  group('ReconciliationEngine - creating', () {
    test('creates a listing when none exists yet, and confirms after write-then-verify', () async {
      final adapter = FakeStoreAdapter();
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(stores: {
        'ebay_test': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.pending),
      });

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.created);
      final newState = result.item.stores['ebay_test']!;
      expect(newState.syncStatus, SyncStatus.confirmed);
      expect(newState.externalListingId, isNotNull);
      expect(newState.lastConfirmedQuantity, 5);
    });

    test('never creates a listing for a SKU that is already sold out', () async {
      final adapter = FakeStoreAdapter();
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 0,
        stores: {'ebay_test': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.pending)},
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.alreadyInSync);
      expect(result.item.stores['ebay_test']!.externalListingId, isNull);
    });

    test('a mismatched write-then-verify after create is reported as an error, not silently confirmed', () async {
      final adapter = FakeStoreAdapter()..simulateWriteDriftOnce = true;
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(stores: {
        'ebay_test': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.pending),
      });

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.error);
      expect(result.item.stores['ebay_test']!.syncStatus, SyncStatus.error);
      expect(result.hasError, isTrue);
    });
  });

  group('ReconciliationEngine - a plain restock (no baseline drop) is just a push', () {
    test('a restock is pushed normally, not flagged - v2\'s whole point vs. v1', () async {
      // Confirmed baseline matches what the store still shows (5) - the
      // store hasn't independently changed. Source of truth increasing to
      // 8 is a restock the store just hasn't heard about yet.
      final adapter = FakeStoreAdapter()..seed('existing-1', quantity: 5, price: 109);
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 8,
        price: 109,
        stores: {'ebay_test': _confirmed('existing-1', lastConfirmedQuantity: 5)},
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.updated);
      expect(result.item.quantity, 8, reason: 'no sale happened - source of truth is untouched');
      final remote = await adapter.getListing('existing-1');
      expect(remote!.quantity, 8);
    });

    test('a store with no confirmed baseline yet is never treated as a mystery sale', () async {
      final adapter = FakeStoreAdapter()..seed('existing-1', quantity: 1, price: 109);
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 5,
        stores: {
          'ebay_test': StoreListingState(
            platform: 'ebay',
            externalListingId: 'existing-1',
            syncStatus: SyncStatus.confirmed,
            // no lastConfirmedQuantity - never been through a v2 write yet
          ),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.updated);
      expect(result.item.quantity, 5, reason: 'no baseline to compare against - just push toward source');
    });

    test('does nothing when the store already matches the source of truth', () async {
      final adapter = FakeStoreAdapter()..seed('existing-1', quantity: 5, price: 109);
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 5,
        price: 109,
        stores: {'ebay_test': _confirmed('existing-1', lastConfirmedQuantity: 5)},
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.alreadyInSync);
    });
  });

  group('ReconciliationEngine - external sales (v2\'s actual two-way merge)', () {
    test('a sale on one store cascades the new quantity to every other connected store', () async {
      final soldOn = FakeStoreAdapter()..seed('ebay-1', quantity: 3, price: 109); // sold 2 of 5
      final stillStale = FakeStoreAdapter()..seed('walmart-1', quantity: 5, price: 109);
      final engine = ReconciliationEngine(adapters: {'ebay_test': soldOn, 'walmart_test': stillStale});

      final item = _item(
        quantity: 5,
        stores: {
          'ebay_test': _confirmed('ebay-1', lastConfirmedQuantity: 5),
          'walmart_test': _confirmed('walmart-1', lastConfirmedQuantity: 5),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.item.quantity, 3, reason: '5 - 2 sold = 3');
      expect(result.hasExternalSale, isTrue);
      final byAccount = {for (final a in result.actions) a.accountKey: a.outcome};
      expect(byAccount['ebay_test'], ReconciliationOutcome.alreadyInSync,
          reason: 'this store already reflects the real sale - nothing to push there');
      expect(byAccount['walmart_test'], ReconciliationOutcome.updated,
          reason: 'cascaded down to match the new real quantity');
      final walmartRemote = await stillStale.getListing('walmart-1');
      expect(walmartRemote!.quantity, 3);

      final saleAction = result.actions.singleWhere((a) => a.outcome == ReconciliationOutcome.externalSaleReconciled);
      expect(saleAction.detail, contains('sold 2 total'));
    });

    test('sales on two different stores in the same pass are summed, not just the first one counted', () async {
      final storeA = FakeStoreAdapter()..seed('a-1', quantity: 3, price: 109); // sold 2
      final storeB = FakeStoreAdapter()..seed('b-1', quantity: 4, price: 109); // sold 1
      final engine = ReconciliationEngine(adapters: {'store_a': storeA, 'store_b': storeB});

      final item = _item(
        quantity: 5,
        stores: {
          'store_a': _confirmed('a-1', lastConfirmedQuantity: 5),
          'store_b': _confirmed('b-1', lastConfirmedQuantity: 5),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.item.quantity, 2, reason: '5 - (2 + 1) = 2, not 5 - max(2,1) = 3');
      final remoteA = await storeA.getListing('a-1');
      final remoteB = await storeB.getListing('b-1');
      expect(remoteA!.quantity, 2);
      expect(remoteB!.quantity, 2);
    });

    test('after a sale, the confirmed baseline moves to the new real quantity', () async {
      final adapter = FakeStoreAdapter()..seed('ebay-1', quantity: 4, price: 109); // sold 1 of 5
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 5,
        stores: {'ebay_test': _confirmed('ebay-1', lastConfirmedQuantity: 5)},
      );

      final result = await engine.reconcile(item);

      expect(result.item.stores['ebay_test']!.lastConfirmedQuantity, 4);
    });
  });

  group('ReconciliationEngine - oversold (the race condition from the plan doc)', () {
    test('two stores each independently selling the last unit is flagged, not auto-resolved', () async {
      final storeA = FakeStoreAdapter()..seed('a-1', quantity: 0, price: 109, isLive: false);
      final storeB = FakeStoreAdapter()..seed('b-1', quantity: 0, price: 109, isLive: false);
      final engine = ReconciliationEngine(adapters: {'store_a': storeA, 'store_b': storeB});

      final item = _item(
        quantity: 1, // only one real unit
        stores: {
          'store_a': _confirmed('a-1', lastConfirmedQuantity: 1),
          'store_b': _confirmed('b-1', lastConfirmedQuantity: 1),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.hasOversold, isTrue);
      expect(result.item.quantity, 0, reason: 'floors at 0, never negative');
      final oversoldAction = result.actions.singleWhere((a) => a.outcome == ReconciliationOutcome.oversold);
      expect(oversoldAction.detail, contains('sold 2 total'));
      expect(oversoldAction.detail, contains('only 1 were available'));
    });

    test('an oversold item still gets fully delisted everywhere - there really is nothing left', () async {
      final storeA = FakeStoreAdapter()..seed('a-1', quantity: 0, price: 109, isLive: false);
      final storeB = FakeStoreAdapter()..seed('b-1', quantity: 0, price: 109); // still live, not yet told
      final engine = ReconciliationEngine(adapters: {'store_a': storeA, 'store_b': storeB});

      final item = _item(
        quantity: 1,
        stores: {
          'store_a': _confirmed('a-1', lastConfirmedQuantity: 1),
          'store_b': _confirmed('b-1', lastConfirmedQuantity: 1),
        },
      );

      final result = await engine.reconcile(item);

      final byAccount = {for (final a in result.actions) a.accountKey: a.outcome};
      expect(byAccount['store_a'], ReconciliationOutcome.alreadyInSync);
      expect(byAccount['store_b'], ReconciliationOutcome.delisted);
      final remoteB = await storeB.getListing('b-1');
      expect(remoteB!.isLive, isFalse);
    });
  });

  group('ReconciliationEngine - auto-unlist on zero', () {
    test('delists (withdraws) a live listing when quantity drops to 0', () async {
      final adapter = FakeStoreAdapter()..seed('existing-1', quantity: 2, price: 109);
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 0,
        stores: {
          'ebay_test': StoreListingState(
            platform: 'ebay',
            externalListingId: 'existing-1',
            syncStatus: SyncStatus.confirmed,
          ),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.delisted);
      final remote = await adapter.getListing('existing-1');
      expect(remote!.isLive, isFalse);
    });

    test('is a no-op when quantity is 0 and the store already reflects that', () async {
      final adapter = FakeStoreAdapter()..seed('existing-1', quantity: 0, price: 109, isLive: false);
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(
        quantity: 0,
        stores: {
          'ebay_test': StoreListingState(
            platform: 'ebay',
            externalListingId: 'existing-1',
            syncStatus: SyncStatus.confirmed,
          ),
        },
      );

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.alreadyInSync);
    });
  });

  group('ReconciliationEngine - errors and skips', () {
    test('records an error when a remembered listing no longer exists on the store', () async {
      final adapter = FakeStoreAdapter(); // nothing seeded
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(stores: {
        'ebay_test': StoreListingState(
          platform: 'ebay',
          externalListingId: 'vanished',
          syncStatus: SyncStatus.confirmed,
        ),
      });

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.error);
      expect(result.item.stores['ebay_test']!.syncStatus, SyncStatus.error);
    });

    test('an adapter exception on the phase-1 read is caught per-account and recorded as an error', () async {
      final adapter = FakeStoreAdapter()
        ..seed('existing-1', quantity: 5, price: 109)
        ..throwOnNextCall = StoreAdapterRateLimitException('rate limited');
      final engine = ReconciliationEngine(adapters: {'ebay_test': adapter});

      final item = _item(stores: {
        'ebay_test': _confirmed('existing-1', lastConfirmedQuantity: 5),
      });

      final result = await engine.reconcile(item);

      expect(result.actions.single.outcome, ReconciliationOutcome.error);
      expect(result.actions.single.detail, contains('rate limited'));
    });

    test('one account failing does not stop other accounts from being reconciled', () async {
      final failingAdapter = FakeStoreAdapter()
        ..throwOnNextCall = StoreAdapterRequestException('boom');
      final workingAdapter = FakeStoreAdapter();
      final engine = ReconciliationEngine(
        adapters: {'ebay_a': failingAdapter, 'ebay_b': workingAdapter},
      );

      final item = _item(stores: {
        'ebay_a': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.pending),
        'ebay_b': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.pending),
      });

      final result = await engine.reconcile(item);

      expect(result.hasError, isTrue);
      final byAccount = {for (final a in result.actions) a.accountKey: a.outcome};
      expect(byAccount['ebay_a'], ReconciliationOutcome.error);
      expect(byAccount['ebay_b'], ReconciliationOutcome.created);
    });

    test('a store that fails its phase-1 read is excluded from the sold-total sum entirely', () async {
      final flaky = FakeStoreAdapter()
        ..seed('a-1', quantity: 5, price: 109)
        ..throwOnNextCall = StoreAdapterRequestException('timeout');
      final soldOn = FakeStoreAdapter()..seed('b-1', quantity: 3, price: 109); // sold 2

      final engine = ReconciliationEngine(adapters: {'store_a': flaky, 'store_b': soldOn});
      final item = _item(
        quantity: 5,
        stores: {
          'store_a': _confirmed('a-1', lastConfirmedQuantity: 5),
          'store_b': _confirmed('b-1', lastConfirmedQuantity: 5),
        },
      );

      final result = await engine.reconcile(item);

      // Only store_b's real drop of 2 counts - store_a's read failure isn't
      // silently treated as "sold 0" contributing nothing, nor guessed at.
      expect(result.item.quantity, 3);
      final byAccount = {for (final a in result.actions) a.accountKey: a.outcome};
      expect(byAccount['store_a'], ReconciliationOutcome.error);
    });

    test('an account with no registered adapter (monitor-only) is left untouched', () async {
      final engine = ReconciliationEngine(adapters: const {});

      final original = StoreListingState(platform: 'poshmark', syncStatus: SyncStatus.manualOnly);
      final item = _item(stores: {'poshmark': original});

      final result = await engine.reconcile(item);

      expect(result.actions, isEmpty);
      expect(result.item.stores['poshmark'], same(original));
    });
  });
}
