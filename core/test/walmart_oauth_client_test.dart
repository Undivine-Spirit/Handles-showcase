import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('WalmartOAuthClient', () {
    test('fetches a token with client-credentials grant, no consent flow needed', () async {
      final store = InMemoryCredentialStore();
      final client = WalmartOAuthClient(
        accountKey: 'walmart',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        credentialStore: store,
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], startsWith('Basic '));
          expect(request.headers['WM_QOS.CORRELATION_ID'], isNotEmpty);
          expect(Uri.splitQueryString(request.body)['grant_type'], 'client_credentials');
          return http.Response(
            jsonEncode({'access_token': 'wm-token-1', 'expires_in': 900}),
            200,
          );
        }),
      );

      final token = await client.getValidAccessToken();

      expect(token, 'wm-token-1');
      final stored = await store.read('walmart');
      expect(stored?['access_token'], 'wm-token-1');
    });

    test('reuses a still-valid cached token without a new network call', () async {
      final store = InMemoryCredentialStore();
      await store.write('walmart', {
        'access_token': 'still-good',
        'access_token_expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      });
      var callCount = 0;

      final client = WalmartOAuthClient(
        accountKey: 'walmart',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        credentialStore: store,
        httpClient: MockClient((request) async {
          callCount++;
          return http.Response('{}', 200);
        }),
      );

      final token = await client.getValidAccessToken();

      expect(token, 'still-good');
      expect(callCount, 0);
    });

    test('refreshes with a tighter margin than eBay - Walmart tokens only last ~15 minutes', () async {
      final store = InMemoryCredentialStore();
      // Only 20 seconds left - inside WalmartOAuthClient's 30s margin, so
      // this should trigger a refresh even though it's not literally expired.
      await store.write('walmart', {
        'access_token': 'about-to-expire',
        'access_token_expires_at': DateTime.now().add(const Duration(seconds: 20)).toIso8601String(),
      });

      final client = WalmartOAuthClient(
        accountKey: 'walmart',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        credentialStore: store,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'access_token': 'refreshed', 'expires_in': 900}),
            200,
          ),
        ),
      );

      final token = await client.getValidAccessToken();

      expect(token, 'refreshed');
    });

    test('a rejected token request throws StoreAdapterAuthException', () async {
      final client = WalmartOAuthClient(
        accountKey: 'walmart',
        clientId: 'bad',
        clientSecret: 'bad',
        credentialStore: InMemoryCredentialStore(),
        httpClient: MockClient((request) async => http.Response('invalid_client', 401)),
      );

      expect(client.getValidAccessToken, throwsA(isA<StoreAdapterAuthException>()));
    });
  });
}
