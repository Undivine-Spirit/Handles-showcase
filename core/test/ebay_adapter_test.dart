import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A [CredentialStore] pre-seeded with a token that never expires, so
/// tests exercise only the adapter's own REST calls, not the OAuth flow
/// (that's covered separately in ebay_oauth_client_test.dart).
Future<EbayOAuthClient> _fakeAuthedOAuth(String accountKey) async {
  final store = InMemoryCredentialStore();
  await store.write(accountKey, {
    'access_token': 'test-token',
    'refresh_token': 'refresh-1',
    'access_token_expires_at':
        DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
  });
  return EbayOAuthClient(
    accountKey: accountKey,
    clientId: 'client-id',
    clientSecret: 'client-secret',
    redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
    credentialStore: store,
  );
}

const _accountConfig = EbayAccountConfig(
  fulfillmentPolicyId: 'fulfillment-1',
  paymentPolicyId: 'payment-1',
  returnPolicyId: 'return-1',
  merchantLocationKey: 'warehouse-1',
);

CatalogItem _sampleItem({int quantity = 5}) => CatalogItem(
      sku: 'HND-0142',
      title: "Nike Air Force 1 '07 - Triple White",
      description: 'Deadstock, size 10.',
      price: 109,
      quantity: quantity,
      condition: 'New',
      images: const ['https://example.com/af1.jpg'],
      category: 'Sneakers',
    );

void main() {
  group('EbayAdapter.createListing', () {
    test('PUTs the inventory item, POSTs the offer, then publishes it', () async {
      final calls = <String>[];

      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');

          if (request.method == 'PUT' &&
              request.url.path == '/sell/inventory/v1/inventory_item/HND-0142') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(
              body['availability']['shipToLocationAvailability']['quantity'],
              5,
            );
            expect(body['condition'], 'NEW');
            expect(body['product']['title'], "Nike Air Force 1 '07 - Triple White");
            return http.Response('', 200);
          }

          if (request.method == 'POST' &&
              request.url.path == '/sell/inventory/v1/offer') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['sku'], 'HND-0142');
            expect(body['categoryId'], '15709');
            expect(body['pricingSummary']['price']['value'], '109.00');
            expect(body['listingPolicies']['fulfillmentPolicyId'], 'fulfillment-1');
            return http.Response(jsonEncode({'offerId': 'offer-abc'}), 201);
          }

          if (request.method == 'POST' &&
              request.url.path == '/sell/inventory/v1/offer/offer-abc/publish') {
            return http.Response(jsonEncode({'listingId': 'listing-xyz'}), 200);
          }

          fail('unexpected request: ${request.method} ${request.url}');
        }),
      );

      final result = await adapter.createListing(_sampleItem());

      expect(result.externalListingId, 'listing-xyz');
      expect(result.externalOfferId, 'offer-abc');
      expect(calls, [
        'PUT /sell/inventory/v1/inventory_item/HND-0142',
        'POST /sell/inventory/v1/offer',
        'POST /sell/inventory/v1/offer/offer-abc/publish',
      ]);
    });
  });

  group('EbayAdapter.updateListing', () {
    test('a price change only touches the offer', () async {
      var putOfferCalled = false;

      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path == '/sell/inventory/v1/offer/offer-abc') {
            putOfferCalled = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['pricingSummary']['price']['value'], '99.00');
            return http.Response('', 200);
          }
          fail('unexpected request: ${request.method} ${request.url}');
        }),
      );

      await adapter.updateListing('offer-abc', price: 99);

      expect(putOfferCalled, isTrue);
    });

    test('a quantity change looks up the SKU via the offer, then PUTs the inventory item', () async {
      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/sell/inventory/v1/offer/offer-abc') {
            return http.Response(jsonEncode({'sku': 'HND-0142'}), 200);
          }
          if (request.method == 'PUT' &&
              request.url.path == '/sell/inventory/v1/inventory_item/HND-0142') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(
              body['availability']['shipToLocationAvailability']['quantity'],
              0,
            );
            return http.Response('', 200);
          }
          fail('unexpected request: ${request.method} ${request.url}');
        }),
      );

      await adapter.updateListing('offer-abc', quantity: 0);
    });
  });

  group('EbayAdapter.delist', () {
    test('withdraws the offer instead of deleting anything', () async {
      var withdrawn = false;

      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sell/inventory/v1/offer/offer-abc/withdraw');
          withdrawn = true;
          return http.Response('', 200);
        }),
      );

      await adapter.delist('offer-abc');

      expect(withdrawn, isTrue);
    });
  });

  group('EbayAdapter.getListing', () {
    test('returns null when the offer does not exist', () async {
      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async => http.Response('', 404)),
      );

      expect(await adapter.getListing('missing'), isNull);
    });

    test('combines the offer and inventory item into one RemoteListing', () async {
      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async {
          if (request.url.path == '/sell/inventory/v1/offer/offer-abc') {
            return http.Response(
              jsonEncode({
                'sku': 'HND-0142',
                'status': 'PUBLISHED',
                'pricingSummary': {
                  'price': {'value': '109.00', 'currency': 'USD'},
                },
              }),
              200,
            );
          }
          if (request.url.path == '/sell/inventory/v1/inventory_item/HND-0142') {
            return http.Response(
              jsonEncode({
                'availability': {
                  'shipToLocationAvailability': {'quantity': 5},
                },
              }),
              200,
            );
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final listing = await adapter.getListing('offer-abc');

      expect(listing, isNotNull);
      expect(listing!.quantity, 5);
      expect(listing.price, 109.0);
      expect(listing.isLive, isTrue);
    });
  });

  group('error mapping', () {
    test('a 429 becomes StoreAdapterRateLimitException', () async {
      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient(
          (request) async => http.Response('', 429, headers: {'retry-after': '30'}),
        ),
      );

      expect(
        () => adapter.delist('offer-abc'),
        throwsA(
          isA<StoreAdapterRateLimitException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 30),
          ),
        ),
      );
    });

    test('other non-2xx responses become StoreAdapterRequestException', () async {
      final adapter = EbayAdapter(
        oauth: await _fakeAuthedOAuth('ebay_test'),
        accountConfig: _accountConfig,
        categoryResolver: (item) => '15709',
        httpClient: MockClient((request) async => http.Response('bad input', 400)),
      );

      expect(
        () => adapter.delist('offer-abc'),
        throwsA(isA<StoreAdapterRequestException>()),
      );
    });
  });
}
