import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Makes one [AppState] reachable from anywhere below it without prop-
/// drilling through every screen's constructor.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required AppState appState, required super.child})
      : super(notifier: appState);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in context');
    return scope!.notifier!;
  }
}
