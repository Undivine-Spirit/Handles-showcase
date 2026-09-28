import 'package:handles_core/handles_core.dart';

/// Walmart's client-credentials grant ties directly to one seller account -
/// unlike eBay, there's no separate "app config shared across multiple
/// accounts" concept to model, since this project only has one Walmart
/// account (`catalog/stores.json`). Simpler on purpose, not an
/// oversimplification.
class WalmartAppConfig {
  const WalmartAppConfig({required this.clientId, required this.clientSecret});

  final String clientId;
  final String clientSecret;

  bool get isComplete => clientId.isNotEmpty && clientSecret.isNotEmpty;

  static const empty = WalmartAppConfig(clientId: '', clientSecret: '');
}

class WalmartAppConfigStore {
  WalmartAppConfigStore(this._credentialStore);

  static const _key = 'walmart_app_config';

  final CredentialStore _credentialStore;

  Future<WalmartAppConfig> load() async {
    final values = await _credentialStore.read(_key);
    if (values == null) return WalmartAppConfig.empty;
    return WalmartAppConfig(
      clientId: values['client_id'] ?? '',
      clientSecret: values['client_secret'] ?? '',
    );
  }

  Future<void> save(WalmartAppConfig config) async {
    await _credentialStore.write(_key, {
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
    });
  }
}
