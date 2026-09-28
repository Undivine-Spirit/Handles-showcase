import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/main.dart';
import 'package:handles_core/handles_core.dart';

import 'test_helpers.dart';

CatalogItem _item(String sku, String title, Map<String, StoreListingState> stores) => CatalogItem(
      sku: sku,
      title: title,
      price: 10,
      quantity: 1,
      stores: stores,
    );

void main() {
  testWidgets('Shared Items tab shows only items listed on more than one store', (tester) async {
    final appState = await testAppState();

    await tester.pumpWidget(HandlesApp(appState: appState));
    await tester.pumpAndSettle();

    // Set after the first pump - HandlesApp's initState() re-runs
    // AppState.init() on mount (that's what lets a freshly-injected
    // AppState load its stores before the console screen reads it), which
    // would otherwise clobber a fixture set before pumpWidget.
    appState.items = [
      _item('SKU-1', 'Solo eBay Item', {
        'ebay_store_a': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.confirmed),
      }),
      _item('SKU-2', 'Dual Listed Item', {
        'ebay_store_a': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.confirmed),
        'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.confirmed),
      }),
    ];
    appState.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Solo eBay Item'), findsOneWidget);
    expect(find.text('Dual Listed Item'), findsOneWidget);

    final sharedItemsTab = find.text('SHARED ITEMS');
    await tester.ensureVisible(sharedItemsTab);
    await tester.tap(sharedItemsTab);
    await tester.pumpAndSettle();

    expect(find.text('Solo eBay Item'), findsNothing);
    expect(find.text('Dual Listed Item'), findsOneWidget);
    // Adding a new item doesn't make sense on a filtered view.
    expect(find.text('+ ADD ITEM'), findsNothing);
  });

  testWidgets('a store filter chip narrows the catalog to that store only', (tester) async {
    final appState = await testAppState();

    await tester.pumpWidget(HandlesApp(appState: appState));
    await tester.pumpAndSettle();

    appState.items = [
      _item('SKU-1', 'Ebay Only Item', {
        'ebay_store_a': StoreListingState(platform: 'ebay', syncStatus: SyncStatus.confirmed),
      }),
      _item('SKU-2', 'Walmart Only Item', {
        'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.confirmed),
      }),
    ];
    appState.notifyListeners();
    await tester.pumpAndSettle();

    final walmartChip = find.text('Walmart');
    await tester.ensureVisible(walmartChip);
    await tester.tap(walmartChip);
    await tester.pumpAndSettle();

    expect(find.text('Ebay Only Item'), findsNothing);
    expect(find.text('Walmart Only Item'), findsOneWidget);

    final allChip = find.text('All');
    await tester.ensureVisible(allChip);
    await tester.tap(allChip);
    await tester.pumpAndSettle();

    expect(find.text('Ebay Only Item'), findsOneWidget);
    expect(find.text('Walmart Only Item'), findsOneWidget);
  });
}
