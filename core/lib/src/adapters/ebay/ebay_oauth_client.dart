import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../credential_store.dart';
import '../exceptions.dart';

/// eBay OAuth 2.0 endpoints and scope. Defaults below are believed correct
/// as of this writing but NOT re-verified against eBay's current developer
/// docs at implementation time - `docs/API_RESEARCH.md` explicitly flags
/// that auth flows drift over time. Confirm before pointing this at a real
/// account, especially the exact scope string(s) needed for
/// inventory/listing management.
class EbayOAuthConfig {
  const EbayOAuthConfig({
    this.authorizeUrl = 'https://auth.ebay.com/oauth2/authorize',
    this.tokenUrl = 'https://api.ebay.com/identity/v1/oauth2/token',
    this.scopes = const ['https://api.ebay.com/oauth/api_scope/sell.inventory'],
  });

  /// Sandbox variant for testing without touching a live account -
  /// `auth.sandbox.ebay.com` / `api.sandbox.ebay.com`.
  const EbayOAuthConfig.sandbox()
      : authorizeUrl = 'https://auth.sandbox.ebay.com/oauth2/authorize',
        tokenUrl = 'https://api.sandbox.ebay.com/identity/v1/oauth2/token',
        scopes = const ['https://api.ebay.com/oauth/api_scope/sell.inventory'];

  final String authorizeUrl;
  final String tokenUrl;
  final List<String> scopes;
}

/// Handles the eBay authorization-code OAuth flow for one seller account.
///
/// Getting a token pair for a NEW account is a one-time, human-in-the-loop
/// step (the client has to log into eBay and approve access) - see
/// [buildConsentUrl] and [exchangeAuthorizationCode]. After that,
/// [getValidAccessToken] refreshes automatically with no human involved,
/// for as long as the refresh token stays valid.
///
/// Given this client runs two separate eBay stores
/// (`ebay_store_a`, `ebay_store_b` - `catalog/stores.json`),
/// create one [EbayOAuthClient] per account, each with its own
/// [accountKey] and its own entry in the [CredentialStore].
class EbayOAuthClient {
  EbayOAuthClient({
    required this.accountKey,
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    required this.credentialStore,
    this.config = const EbayOAuthConfig(),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String accountKey;
  final String clientId;
  final String clientSecret;

  /// eBay calls this the "RuName" - configured in the developer portal,
  /// not necessarily a literal URL.
  final String redirectUri;

  final CredentialStore credentialStore;
  final EbayOAuthConfig config;
  final http.Client _http;

  /// The URL to send the client to (in a real browser) to grant Handles
  /// access to this specific eBay account. Not automatable - eBay requires
  /// an actual login + consent click, by design.
  Uri buildConsentUrl() {
    return Uri.parse(config.authorizeUrl).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': config.scopes.join(' '),
    });
  }

  /// Call once, after the client completes the consent flow and eBay
  /// redirects back with `?code=...`. Exchanges that one-time code for the
  /// first access/refresh token pair and persists them.
  Future<void> exchangeAuthorizationCode(String code) async {
    final response = await _http.post(
      Uri.parse(config.tokenUrl),
      headers: _authHeaders(),
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
      },
    );
    await _storeTokenResponse(response, isRefresh: false);
  }

  /// Returns a currently-valid access token, refreshing first if the
  /// stored one has expired (or is close enough to expiry to be unsafe to
  /// use for a call that might take a moment). Throws
  /// [StoreAdapterAuthException] if there's no token on file yet, or the
  /// refresh token itself was rejected (revoked/expired) - either way, the
  /// human consent flow needs to run again for this account.
  Future<String> getValidAccessToken() async {
    final stored = await credentialStore.read(accountKey);
    if (stored == null || stored['refresh_token'] == null) {
      throw StoreAdapterAuthException(
        'No eBay credentials for account "$accountKey" - run the consent '
        'flow (buildConsentUrl / exchangeAuthorizationCode) first.',
      );
    }

    final expiresAt = DateTime.tryParse(stored['access_token_expires_at'] ?? '');
    final stillValid = expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 2)));
    if (stillValid && stored['access_token'] != null) {
      return stored['access_token']!;
    }

    return _refresh(stored['refresh_token']!);
  }

  Future<String> _refresh(String refreshToken) async {
    final response = await _http.post(
      Uri.parse(config.tokenUrl),
      headers: _authHeaders(),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': config.scopes.join(' '),
      },
    );
    return _storeTokenResponse(response, isRefresh: true, existingRefreshToken: refreshToken);
  }

  Map<String, String> _authHeaders() {
    final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
    return {
      'Authorization': 'Basic $basic',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  Future<String> _storeTokenResponse(
    http.Response response, {
    required bool isRefresh,
    String? existingRefreshToken,
  }) async {
    if (response.statusCode != 200) {
      throw StoreAdapterAuthException(
        'eBay ${isRefresh ? 'token refresh' : 'authorization code exchange'} '
        'failed for "$accountKey": HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String;
    final expiresIn = body['expires_in'] as int;
    // A refresh-token-grant response may omit refresh_token entirely (eBay
    // reuses the existing one in that case) - fall back to what we already
    // had rather than losing it.
    final refreshToken = (body['refresh_token'] as String?) ?? existingRefreshToken;
    if (refreshToken == null) {
      throw StoreAdapterAuthException(
        'eBay token response for "$accountKey" had no refresh_token and none '
        'was already on file - cannot proceed without one.',
      );
    }

    await credentialStore.write(accountKey, {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'access_token_expires_at':
          DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
    });

    return accessToken;
  }
}
