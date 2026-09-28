import 'package:handles_core/handles_core.dart';

/// The eBay developer app's own credentials - separate from any one
/// seller account's OAuth tokens. One registered app can service both
/// eBay accounts (or the user can register two apps, one per account);
/// either way this is entered once in Settings, not per-connect.
class EbayAppConfig {
  const EbayAppConfig({required this.clientId, required this.clientSecret, required this.redirectUri});

  final String clientId;
  final String clientSecret;

  /// eBay's "RuName" - see EbayLoopbackAuthFlow's doc comment for what
  /// this actually needs to point at.
  final String redirectUri;

  bool get isComplete => clientId.isNotEmpty && clientSecret.isNotEmpty && redirectUri.isNotEmpty;

  static const empty = EbayAppConfig(clientId: '', clientSecret: '', redirectUri: '');
}

/// Persists [EbayAppConfig] through the same [CredentialStore] the OAuth
/// tokens use - a client secret deserves the same protection a token does,
/// even though it isn't itself a per-user secret.
class EbayAppConfigStore {
  EbayAppConfigStore(this._credentialStore);

  static const _key = 'ebay_app_config';

  final CredentialStore _credentialStore;

  Future<EbayAppConfig> load() async {
    final values = await _credentialStore.read(_key);
    if (values == null) return EbayAppConfig.empty;
    return EbayAppConfig(
      clientId: values['client_id'] ?? '',
      clientSecret: values['client_secret'] ?? '',
      redirectUri: values['redirect_uri'] ?? '',
    );
  }

  Future<void> save(EbayAppConfig config) async {
    await _credentialStore.write(_key, {
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'redirect_uri': config.redirectUri,
    });
  }
}
