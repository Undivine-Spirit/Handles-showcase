import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real implementation of [SettingsStore]. Settings aren't secrets (just
/// category names/keywords and display preferences), so plain
/// `shared_preferences` is the right tool here - unlike credentials, which
/// go through [SecureCredentialStore] instead.
class SharedPrefsSettingsStore implements SettingsStore {
  static const _key = 'handles.settings';

  @override
  Future<HandlesSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const HandlesSettings();
    return HandlesSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(HandlesSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
