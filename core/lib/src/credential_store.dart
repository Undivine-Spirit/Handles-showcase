import 'dart:convert';
import 'dart:io';

/// Where an adapter's per-account secrets (OAuth tokens, API keys) come
/// from and get persisted back to after a refresh.
///
/// This is a placeholder abstraction, not a finished design. Real secure
/// storage (Windows Credential Manager vs. Android Keystore) is still an
/// open question - see `docs/PROJECT_PLAN.md` section 12 ("Credential
/// storage strategy across two OS environments"). Adapters are written
/// against this interface so that question can be answered later without
/// touching adapter code - only the [CredentialStore] implementation
/// swapped in at app startup changes.
abstract interface class CredentialStore {
  /// Returns `null` if nothing is stored yet for [accountKey] - the caller
  /// (e.g. the eBay OAuth flow) is responsible for deciding what that means
  /// (usually: run the human consent flow before anything else can work).
  Future<Map<String, String>?> read(String accountKey);

  Future<void> write(String accountKey, Map<String, String> values);

  Future<void> delete(String accountKey);
}

/// Local-file-backed [CredentialStore] for development only.
///
/// Reads/writes plain JSON under `<directoryPath>/<accountKey>.json`. That
/// directory is expected to be gitignored (see this repo's `.gitignore`
/// `secrets/` entry) so it can't accidentally get committed - but plain
/// JSON on disk is NOT secure storage. Do not point this at real production
/// credentials once the real cross-platform secure-storage decision
/// (section 12) is made; swap in that implementation instead.
class FileCredentialStore implements CredentialStore {
  FileCredentialStore(this.directoryPath);

  final String directoryPath;

  @override
  Future<Map<String, String>?> read(String accountKey) async {
    final file = File('$directoryPath/$accountKey.json');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }

  @override
  Future<void> write(String accountKey, Map<String, String> values) async {
    final file = File('$directoryPath/$accountKey.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(values));
  }

  @override
  Future<void> delete(String accountKey) async {
    final file = File('$directoryPath/$accountKey.json');
    if (await file.exists()) await file.delete();
  }
}

/// Keeps credentials only for the lifetime of the process - useful for
/// tests, or for wiring up an adapter before any storage decision exists.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, Map<String, String>> _values = {};

  @override
  Future<Map<String, String>?> read(String accountKey) async => _values[accountKey];

  @override
  Future<void> write(String accountKey, Map<String, String> values) async {
    _values[accountKey] = Map.of(values);
  }

  @override
  Future<void> delete(String accountKey) async {
    _values.remove(accountKey);
  }
}
