import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/main.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Console screen renders the masthead, stat row, and sample catalog', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(HandlesApp(appState: await testAppState()));
    await tester.pumpAndSettle();

    expect(find.text('HANDLES'), findsOneWidget);
    // StatTile and StatusPill uppercase their labels (matches the Handles
    // Console mockup's text-transform: uppercase) - assert against what's
    // actually rendered, not the mixed-case string passed in.
    expect(find.text('TOTAL SKUS'), findsOneWidget);
    expect(find.text("Nike Air Force 1 '07 — Triple White"), findsOneWidget);
  });

  testWidgets('an item at zero quantity shows Auto-Delisted', (WidgetTester tester) async {
    await tester.pumpWidget(HandlesApp(appState: await testAppState()));
    await tester.pumpAndSettle();

    expect(find.textContaining('AUTO-DELISTED'), findsOneWidget);
  });
}
