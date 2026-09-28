import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../credential_store.dart';
import '../exceptions.dart';

/// Walmart's auth is genuinely simpler than eBay's: a client-credentials
/// grant tied directly to the seller's own account, not a third-party app
/// a human has to separately consent to. No browser flow, no redirect URI
/// - `client_id`/`client_secret` alone are enough to mint a token.
///
/// Not re-verified against Walmart's current developer-portal docs at
/// implementation time (`docs/API_RESEARCH.md` already flags this) -
/// specifically the `WM_SVC.NAME`/`WM_QOS.CORRELATION_ID` headers below,
/// which Walmart's API is known to require on most calls but weren't
/// re-confirmed as required on the *token* call specifically.
class WalmartOAuthConfig {
  const WalmartOAuthConfig({
    this.tokenUrl = 'https://marketplace.walmartapis.com/v3/token',
    this.serviceName = 'Handles',
  });

  final String tokenUrl;
  final String serviceName;
}

/// One instance per connected Walmart account - same pattern as
/// `EbayOAuthClient`, even though the flow itself is simpler here.
class WalmartOAuthClient {
  WalmartOAuthClient({
    required this.accountKey,
    required this.clientId,
    required this.clientSecret,
    required this.credentialStore,
    this.config = const WalmartOAuthConfig(),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String accountKey;
  final String clientId;
  final String clientSecret;
  final CredentialStore credentialStore;
  final WalmartOAuthConfig config;
  final http.Client _http;

  /// Walmart tokens run ~15 minutes (`docs/API_RESEARCH.md`) - a much
  /// tighter window than eBay's ~2 hours, so the safety margin before
  /// refreshing needs to be tighter too, not copy-pasted from eBay's.
  static const _refreshMargin = Duration(seconds: 30);

  Future<String> getValidAccessToken() async {
    final stored = await credentialStore.read(accountKey);
    final expiresAt = DateTime.tryParse(stored?['access_token_expires_at'] ?? '');
    final stillValid =
        expiresAt != null && DateTime.now().isBefore(expiresAt.subtract(_refreshMargin));

    if (stillValid && stored?['access_token'] != null) {
      return stored!['access_token']!;
    }

    return _fetchNewToken();
  }

  Future<String> _fetchNewToken() async {
    final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final response = await _http.post(
      Uri.parse(config.tokenUrl),
      headers: {
        'Authorization': 'Basic $basic',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        'WM_SVC.NAME': config.serviceName,
        'WM_QOS.CORRELATION_ID': _correlationId(),
      },
      body: {'grant_type': 'client_credentials'},
    );

    if (response.statusCode != 200) {
      throw StoreAdapterAuthException(
        'Walmart token request failed for "$accountKey": HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String;
    final expiresIn = body['expires_in'] as int;

    await credentialStore.write(accountKey, {
      'access_token': accessToken,
      'access_token_expires_at':
          DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
    });

    return accessToken;
  }

  String _correlationId() {
    final random = Random();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
