import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/screens/settings_screen.dart';
import 'package:handles_app/state/app_state_scope.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('tapping a category chip adds it to the priority list', (tester) async {
    final appState = await testAppState();

    await tester.pumpWidget(
      AppStateScope(appState: appState, child: const MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(appState.settings.priorityCategories, isEmpty);

    await tester.ensureVisible(find.text('+ Sneakers'));
    await tester.tap(find.text('+ Sneakers'));
    await tester.pumpAndSettle();

    expect(appState.settings.priorityCategories, ['Sneakers']);
    // Persisted, not just held in memory on the widget.
    final reloaded = await appState.settingsStore.load();
    expect(reloaded.priorityCategories, ['Sneakers']);
  });

  testWidgets('adding a custom category makes it available as a priority chip', (tester) async {
    final appState = await testAppState();

    await tester.pumpWidget(
      AppStateScope(appState: appState, child: const MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('+ Add Category'));
    await tester.tap(find.text('+ Add Category'));
    await tester.pumpAndSettle();

    // Scope to the dialog - the Settings screen behind it also has
    // TextFields (eBay app config), so an unscoped find would be ambiguous.
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), 'Home Goods');
    await tester.enterText(dialogFields.at(1), 'candle, mug');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(appState.settings.customCategories.map((c) => c.name), contains('Home Goods'));
    expect(find.text('+ Home Goods'), findsOneWidget);
  });
}
