import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:handles_core/handles_core.dart';

import 'screens/console_screen.dart';
import 'services/catalog_api_client.dart';
import 'services/catalog_api_config.dart';
import 'services/secure_credential_store.dart';
import 'services/shared_prefs_settings_store.dart';
import 'state/app_state.dart';
import 'state/app_state_scope.dart';
import 'theme/handles_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Without this, Android (Samsung/OneUI in particular) commonly renders a
  // Flutter app capped at 60Hz even on a 120Hz panel - the OS won't switch
  // refresh rate unless the app explicitly asks. Android-only API
  // (flutter_displaymode has no Windows implementation); a device that
  // can't switch modes at all just no-ops rather than throwing past this.
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {
      // Not fatal - the app still runs, just at whatever the default is.
    }
  }

  // Two separate error channels, both routed to the same audit trail
  // (GET /catalog/events, same as AppState._logAction): FlutterError.onError
  // catches framework/widget-build errors, runZonedGuarded catches
  // everything else (async errors outside a widget's build/event
  // callback). Neither replaces normal error handling elsewhere in the
  // app - this is a last-resort net so an unhandled crash someone hits
  // during testing leaves a real record instead of just "the app closed."
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportCrash(details.exception, details.stack ?? StackTrace.current);
  };

  runZonedGuarded(
    () => runApp(const HandlesApp()),
    (error, stack) => _reportCrash(error, stack),
  );
}

/// Loads whatever catalog server config is currently saved and posts a
/// crash event directly - doesn't go through `AppState` since a crash can
/// happen before it exists (or because of it). Every failure path here is
/// swallowed on purpose: a broken crash reporter must never itself crash
/// the app, and there's nothing more useful to do with a reporting
/// failure than drop it.
void _reportCrash(Object error, StackTrace stack) {
  unawaited(() async {
    try {
      final config = await CatalogApiConfigStore(SecureCredentialStore()).load();
      if (!config.isComplete) return;
      await CatalogApiClient(config: config).logEvent(
        severity: EventSeverity.error,
        source: 'app_crash',
        message: '$error\n${stack.toString().split('\n').take(20).join('\n')}',
      );
    } catch (_) {
      // Reporting the crash failed too (server unreachable, etc.) -
      // nothing left to do but not crash again over it.
    }
  }());
}

class HandlesApp extends StatefulWidget {
  /// [appState] is injectable so tests can pass in-memory stores instead of
  /// the real platform-channel-backed ones (secure storage, shared prefs),
  /// which have no backend to talk to inside a widget test.
  const HandlesApp({super.key, AppState? appState}) : _injectedAppState = appState;

  final AppState? _injectedAppState;

  @override
  State<HandlesApp> createState() => _HandlesAppState();
}

class _HandlesAppState extends State<HandlesApp> {
  late final AppState _appState = widget._injectedAppState ??
      AppState(
        settingsStore: SharedPrefsSettingsStore(),
        credentialStore: SecureCredentialStore(),
      );

  @override
  void initState() {
    super.initState();
    _appState.init();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in AnimatedBuilder, not just AppStateScope, because
    // MaterialApp's own `theme:` (Scaffold background, default widget
    // colors) is only ever read once when *this* build() runs -
    // AppStateScope alone only rebuilds the descendants that actually
    // read it (ConsoleScreen, SettingsScreen, ...), not MaterialApp
    // itself. Listening here means picking a new palette re-evaluates
    // buildHandlesTheme() too, not just the custom widgets that already
    // read HandlesColors directly on every build.
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) => AppStateScope(
        appState: _appState,
        child: MaterialApp(
          title: 'Handles',
          debugShowCheckedModeBanner: false,
          theme: buildHandlesTheme(),
          home: const ConsoleScreen(),
        ),
      ),
    );
  }
}
