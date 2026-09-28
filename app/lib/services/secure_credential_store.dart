import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:handles_core/handles_core.dart';

/// Real cross-platform implementation of [CredentialStore] - resolves
/// PROJECT_PLAN.md section 12's "credential storage strategy across two OS
/// environments" open question. `flutter_secure_storage` backs onto
/// Windows' DPAPI-protected storage and Android's Keystore-backed
/// EncryptedSharedPreferences, so this is the same code on both target
/// platforms with no per-platform branching needed here.
///
/// This is what makes "auto login" real: once a user completes the
/// one-time OAuth consent (see `EbayLoopbackAuthFlow`), the refresh token
/// lands here, encrypted at rest by the OS - not in a plain file like
/// `FileCredentialStore`, which stays around only as a dev/test double.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _keyFor(String accountKey) => 'handles.credentials.$accountKey';

  @override
  Future<Map<String, String>?> read(String accountKey) async {
    final raw = await _storage.read(key: _keyFor(accountKey));
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }

  @override
  Future<void> write(String accountKey, Map<String, String> values) async {
    await _storage.write(key: _keyFor(accountKey), value: jsonEncode(values));
  }

  @override
  Future<void> delete(String accountKey) async {
    await _storage.delete(key: _keyFor(accountKey));
  }
}
