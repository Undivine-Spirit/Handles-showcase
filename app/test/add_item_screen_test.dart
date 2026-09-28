import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/screens/add_item_screen.dart';
import 'package:handles_app/state/app_state_scope.dart';
import 'package:handles_core/handles_core.dart';

import 'test_helpers.dart';

Future<CatalogItem?> _openAddItemScreen(WidgetTester tester) async {
  final appState = await testAppState();
  CatalogItem? result;

  await tester.pumpWidget(
    AppStateScope(
      appState: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CatalogItem>(
                MaterialPageRoute(builder: (_) => const AddItemScreen()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  testWidgets('typing a recognizable title surfaces a category suggestion', (tester) async {
    await _openAddItemScreen(tester);

    final titleField = find.byType(TextField).at(1); // SKU(0), Title(1)
    await tester.enterText(titleField, "Nike Air Force 1 '07");
    await tester.pump();

    expect(find.text('Sneakers'), findsWidgets);
  });

  testWidgets('accepting a suggestion and submitting returns an item with that category', (
    tester,
  ) async {
    late CatalogItem? result;
    final appState = await testAppState();

    await tester.pumpWidget(
      AppStateScope(
        appState: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<CatalogItem>(
                  MaterialPageRoute(builder: (_) => const AddItemScreen()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'HND-9999'); // SKU
    await tester.enterText(find.byType(TextField).at(1), "Nike Air Force 1 '07"); // Title
    await tester.pump();

    await tester.ensureVisible(find.text('Sneakers').first);
    await tester.tap(find.text('Sneakers').first);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(3), '99.99'); // Price
    // Quantity field already defaults to '1'.
    await tester.pump();

    await tester.ensureVisible(find.text('ADD ITEM'));
    await tester.tap(find.text('ADD ITEM'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sku, 'HND-9999');
    expect(result!.category, 'Sneakers');
    expect(result!.price, 99.99);
    expect(result!.quantity, 1);
  });

  testWidgets('the Add Item button stays disabled until the required fields are valid', (
    tester,
  ) async {
    await _openAddItemScreen(tester);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'ADD ITEM'));
    expect(button.onPressed, isNull);
  });

  group('editing an existing item', () {
    final existing = CatalogItem(
      sku: 'HND-0142',
      title: "Nike Air Force 1 '07",
      price: 109,
      quantity: 6,
      category: 'Sneakers',
      stores: {
        'ebay_store_a': StoreListingState(
          platform: 'ebay',
          externalListingId: 'l-1',
          syncStatus: SyncStatus.confirmed,
        ),
      },
    );

    testWidgets('pre-fills every field and locks the SKU', (tester) async {
      final appState = await testAppState();

      await tester.pumpWidget(
        AppStateScope(
          appState: appState,
          child: MaterialApp(home: AddItemScreen(existingItem: existing)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Item'), findsOneWidget);
      final skuField = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(skuField.controller!.text, 'HND-0142');
      expect(skuField.enabled, isFalse);
      final priceField = tester.widget<TextField>(find.byType(TextField).at(3));
      expect(priceField.controller!.text, '109.0');
    });

    testWidgets('saving a manual quantity change preserves stores/sku, updates only what changed', (
      tester,
    ) async {
      late CatalogItem? result;
      final appState = await testAppState();

      await tester.pumpWidget(
        AppStateScope(
          appState: appState,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<CatalogItem>(
                    MaterialPageRoute(builder: (_) => AddItemScreen(existingItem: existing)),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Quantity field: SKU(0), Title(1), Description(2), Price(3), Quantity(4).
      await tester.enterText(find.byType(TextField).at(4), '2');
      await tester.pump();

      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.sku, 'HND-0142', reason: 'identity is preserved, not editable');
      expect(result!.quantity, 2, reason: 'the manual override this screen exists for');
      expect(result!.price, 109);
      expect(result!.stores, existing.stores, reason: 'fields this form does not touch survive the edit');
    });
  });
}
