import 'package:handles_core/handles_core.dart';
import 'package:handles_app/state/app_state.dart';

/// Builds an [AppState] backed entirely by in-memory stores - no
/// platform-channel calls (secure storage, shared preferences), so it's
/// safe to use from any widget test without a real device/plugin backend.
Future<AppState> testAppState({HandlesSettings? initialSettings}) async {
  final settingsStore = InMemorySettingsStore();
  if (initialSettings != null) {
    await settingsStore.save(initialSettings);
  }
  final appState = AppState(
    settingsStore: settingsStore,
    credentialStore: InMemoryCredentialStore(),
  );
  await appState.init();
  return appState;
}
