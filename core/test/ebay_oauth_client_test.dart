import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('EbayOAuthClient', () {
    test('getValidAccessToken throws when no credentials exist yet', () async {
      final client = EbayOAuthClient(
        accountKey: 'ebay_test',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        credentialStore: InMemoryCredentialStore(),
        httpClient: MockClient((request) async => http.Response('', 500)),
      );

      expect(client.getValidAccessToken, throwsA(isA<StoreAdapterAuthException>()));
    });

    test('exchangeAuthorizationCode stores the returned token pair', () async {
      final store = InMemoryCredentialStore();
      final client = EbayOAuthClient(
        accountKey: 'ebay_test',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        credentialStore: store,
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.headers['Authorization'],
            startsWith('Basic '),
          );
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'expires_in': 7200,
            }),
            200,
          );
        }),
      );

      await client.exchangeAuthorizationCode('one-time-code');

      final stored = await store.read('ebay_test');
      expect(stored?['access_token'], 'access-1');
      expect(stored?['refresh_token'], 'refresh-1');
    });

    test('getValidAccessToken reuses a still-valid cached token without refreshing', () async {
      final store = InMemoryCredentialStore();
      await store.write('ebay_test', {
        'access_token': 'still-good',
        'refresh_token': 'refresh-1',
        'access_token_expires_at':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });

      var callCount = 0;
      final client = EbayOAuthClient(
        accountKey: 'ebay_test',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        credentialStore: store,
        httpClient: MockClient((request) async {
          callCount++;
          return http.Response('{}', 200);
        }),
      );

      final token = await client.getValidAccessToken();

      expect(token, 'still-good');
      expect(callCount, 0, reason: 'should not hit the network for a valid token');
    });

    test('getValidAccessToken refreshes an expired token and keeps the refresh token '
        'when eBay omits one from the response', () async {
      final store = InMemoryCredentialStore();
      await store.write('ebay_test', {
        'access_token': 'expired',
        'refresh_token': 'refresh-1',
        'access_token_expires_at':
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      });

      final client = EbayOAuthClient(
        accountKey: 'ebay_test',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        credentialStore: store,
        httpClient: MockClient((request) async {
          final body = Uri.splitQueryString(request.body);
          expect(body['grant_type'], 'refresh_token');
          expect(body['refresh_token'], 'refresh-1');
          return http.Response(
            jsonEncode({'access_token': 'fresh', 'expires_in': 7200}),
            200,
          );
        }),
      );

      final token = await client.getValidAccessToken();

      expect(token, 'fresh');
      final stored = await store.read('ebay_test');
      expect(stored?['refresh_token'], 'refresh-1', reason: 'must not be lost');
    });

    test('a rejected refresh throws StoreAdapterAuthException', () async {
      final store = InMemoryCredentialStore();
      await store.write('ebay_test', {
        'access_token': 'expired',
        'refresh_token': 'revoked',
        'access_token_expires_at':
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      });

      final client = EbayOAuthClient(
        accountKey: 'ebay_test',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        credentialStore: store,
        httpClient: MockClient((request) async => http.Response('invalid_grant', 400)),
      );

      expect(client.getValidAccessToken, throwsA(isA<StoreAdapterAuthException>()));
    });
  });
}
