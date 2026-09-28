import 'package:handles_core/handles_core.dart';

/// The Keepa API key, once subscribed (`docs/PROJECT_PLAN.md` section 9 -
/// not activated yet). Given a settings
/// home now so entering it later doesn't need a code change - the
/// bulk-sourcing engine (section 10, components 3-4) isn't wired to read
/// this yet, but the field exists so that's the only thing left to do.
class KeepaConfig {
  const KeepaConfig({required this.apiKey});

  final String apiKey;

  bool get isComplete => apiKey.isNotEmpty;

  static const empty = KeepaConfig(apiKey: '');
}

class KeepaConfigStore {
  KeepaConfigStore(this._credentialStore);

  static const _key = 'keepa_config';

  final CredentialStore _credentialStore;

  Future<KeepaConfig> load() async {
    final values = await _credentialStore.read(_key);
    if (values == null) return KeepaConfig.empty;
    return KeepaConfig(apiKey: values['api_key'] ?? '');
  }

  Future<void> save(KeepaConfig config) async {
    await _credentialStore.write(_key, {'api_key': config.apiKey});
  }
}
