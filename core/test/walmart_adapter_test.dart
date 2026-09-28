import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Future<WalmartOAuthClient> _fakeAuthedOAuth() async {
  final store = InMemoryCredentialStore();
  await store.write('walmart', {
    'access_token': 'test-token',
    'access_token_expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
  });
  return WalmartOAuthClient(
    accountKey: 'walmart',
    clientId: 'client-id',
    clientSecret: 'client-secret',
    credentialStore: store,
  );
}

CatalogItem _sampleItem({int quantity = 5}) => CatalogItem(
      sku: 'HND-0142',
      title: "Nike Air Force 1 '07 - Triple White",
      description: 'Deadstock, size 10.',
      price: 109,
      quantity: quantity,
      condition: 'New',
    );

/// Reads a MultipartRequest's attached JSON file back out, for asserting
/// on feed payload contents.
Future<Map<String, dynamic>> _decodeFeedFile(http.BaseRequest request) async {
  final multipart = request as http.MultipartRequest;
  final file = multipart.files.single;
  final bytes = await file.finalize().toBytes();
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

void main() {
  group('WalmartAdapter.createListing', () {
    test('submits an MP_ITEM feed, polls until processed, then sets initial quantity', () async {
      final calls = <String>[];

      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        feedPollInterval: Duration.zero,
        httpClient: MockClient.streaming((request, bodyStream) async {
          calls.add('${request.method} ${request.url.path}${request.url.query.isEmpty ? '' : '?${request.url.query}'}');

          if (request.method == 'POST' && request.url.path == '/v3/feeds') {
            expect(request.url.queryParameters['feedType'], 'MP_ITEM');
            final payload = await _decodeFeedFile(request);
            expect(payload['MPItem'].single['sku'], 'HND-0142');
            expect(payload['MPItem'].single['price']['amount'], 109);
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'feedId': 'feed-1'}))),
              200,
            );
          }

          if (request.method == 'GET' && request.url.path == '/v3/feeds/feed-1') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'feedStatus': 'PROCESSED'}))),
              200,
            );
          }

          if (request.method == 'PUT' && request.url.path == '/v3/inventory') {
            final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
            expect(body['quantity']['amount'], 5);
            return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
          }

          fail('unexpected request: ${request.method} ${request.url}');
        }),
      );

      final result = await adapter.createListing(_sampleItem());

      expect(result.externalListingId, 'HND-0142', reason: 'Walmart has no separate offer ID - the SKU is the identifier');
      expect(calls, [
        'POST /v3/feeds?feedType=MP_ITEM',
        'GET /v3/feeds/feed-1',
        'PUT /v3/inventory?sku=HND-0142',
      ]);
    });

    test('a feed that finishes with ERROR status throws instead of returning success', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        feedPollInterval: Duration.zero,
        httpClient: MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/v3/feeds') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'feedId': 'feed-1'}))),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'feedStatus': 'ERROR', 'itemsFailed': 1}))),
            200,
          );
        }),
      );

      expect(() => adapter.createListing(_sampleItem()), throwsA(isA<StoreAdapterRequestException>()));
    });
  });

  group('WalmartAdapter.updateListing', () {
    test('a quantity-only change hits the Inventory API, no feed submitted', () async {
      var feedCalled = false;

      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        httpClient: MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/v3/feeds') {
            feedCalled = true;
          }
          expect(request.method, 'PUT');
          expect(request.url.path, '/v3/inventory');
          final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
          expect(body['quantity']['amount'], 0);
          return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
        }),
      );

      await adapter.updateListing('HND-0142', quantity: 0);

      expect(feedCalled, isFalse);
    });

    test('a price change submits an MP_MAINTENANCE feed', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        feedPollInterval: Duration.zero,
        httpClient: MockClient.streaming((request, bodyStream) async {
          if (request.method == 'POST' && request.url.path == '/v3/feeds') {
            expect(request.url.queryParameters['feedType'], 'MP_MAINTENANCE');
            final payload = await _decodeFeedFile(request);
            expect(payload['MPMaintenance'].single['price']['amount'], 99.0);
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'feedId': 'feed-2'}))),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'feedStatus': 'PROCESSED'}))),
            200,
          );
        }),
      );

      await adapter.updateListing('HND-0142', price: 99);
    });
  });

  group('WalmartAdapter.delist', () {
    test('zeroes quantity rather than any eBay-style withdraw call', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        httpClient: MockClient.streaming((request, bodyStream) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/v3/inventory');
          final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
          expect(body['quantity']['amount'], 0);
          return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
        }),
      );

      await adapter.delist('HND-0142');
    });
  });

  group('WalmartAdapter.getListing', () {
    test('combines the Inventory and Item lookups into one RemoteListing', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        httpClient: MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/v3/inventory') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({
                'quantity': {'unit': 'EACH', 'amount': 5},
              }))),
              200,
            );
          }
          if (request.url.path == '/v3/items/HND-0142') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({
                'price': {'currency': 'USD', 'amount': 109.0},
              }))),
              200,
            );
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final listing = await adapter.getListing('HND-0142');

      expect(listing, isNotNull);
      expect(listing!.quantity, 5);
      expect(listing.price, 109.0);
      expect(listing.isLive, isTrue);
    });

    test('returns null when the SKU has no inventory record', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(const Stream.empty(), 404),
        ),
      );

      expect(await adapter.getListing('missing'), isNull);
    });
  });

  group('error mapping', () {
    test('a 429 becomes StoreAdapterRateLimitException', () async {
      final adapter = WalmartAdapter(
        oauth: await _fakeAuthedOAuth(),
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            const Stream.empty(),
            429,
            headers: {'retry-after': '15'},
          ),
        ),
      );

      expect(
        () => adapter.delist('HND-0142'),
        throwsA(
          isA<StoreAdapterRateLimitException>()
              .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 15)),
        ),
      );
    });
  });
}
