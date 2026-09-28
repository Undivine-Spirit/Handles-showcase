import 'package:handles_core/handles_core.dart';

/// Where the app's catalog server is - `docs/PROJECT_PLAN.md` section 2's
/// 2026-09-02 update: the app talks to a real backend (`core/bin/api_server.dart`,
/// running alongside the daemon on a self-hosted server) over HTTP now,
/// not its own independent git clone. Two fields instead of the old
/// three (remote URL/access token/catalog subpath) - the API hides the
/// git/filesystem details entirely, that's the point of it.
class CatalogApiConfig {
  const CatalogApiConfig({required this.baseUrl, required this.apiToken});

  /// e.g. `https://handles.example.com` or `http://192.168.1.50:8080` -
  /// no trailing slash expected (CatalogApiClient normalizes it anyway).
  final String baseUrl;

  /// Sent as `Authorization: Bearer <apiToken>` on every request - the
  /// server's own `API_AUTH_TOKEN`. This is the one secret protecting the
  /// whole catalog if [baseUrl] is reachable from the open internet -
  /// treat it like the git access token it replaced.
  final String apiToken;

  bool get isComplete => baseUrl.isNotEmpty && apiToken.isNotEmpty;

  static const empty = CatalogApiConfig(baseUrl: '', apiToken: '');
}

class CatalogApiConfigStore {
  CatalogApiConfigStore(this._credentialStore);

  static const _key = 'catalog_api_config';

  final CredentialStore _credentialStore;

  Future<CatalogApiConfig> load() async {
    final values = await _credentialStore.read(_key);
    if (values == null) return CatalogApiConfig.empty;
    return CatalogApiConfig(
      baseUrl: values['base_url'] ?? '',
      apiToken: values['api_token'] ?? '',
    );
  }

  Future<void> save(CatalogApiConfig config) async {
    await _credentialStore.write(_key, {
      'base_url': config.baseUrl,
      'api_token': config.apiToken,
    });
  }
}
