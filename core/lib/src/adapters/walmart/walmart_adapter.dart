import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../catalog_item.dart';
import '../exceptions.dart';
import '../store_adapter.dart';
import 'walmart_oauth_client.dart';

/// Account-level config that isn't tied to any one item.
class WalmartAccountConfig {
  const WalmartAccountConfig({this.shipNode});

  /// Some sellers' Inventory API calls need to specify which fulfillment
  /// location a quantity applies to - not universal, so left optional and
  /// omitted from requests when null rather than guessed at.
  final String? shipNode;
}

/// Walmart implementation of [StoreAdapter], bound to one seller account.
///
/// Structurally different from [EbayAdapter] in three ways that are worth
/// knowing before touching this file, not just implementation detail:
///
/// 1. **No separate offer/listing ID.** Walmart identifies a listing by
///    its SKU directly - there's nothing equivalent to eBay's offer ID.
///    [externalListingId] parameters here are just the SKU.
/// 2. **Item creation/update is feed-based and asynchronous** (submit,
///    then poll for completion), not a synchronous call-and-get-an-ID-back
///    like eBay's Inventory API. [createListing]/[updateListing]'s price
///    path poll internally so they can still honor [StoreAdapter]'s
///    synchronous-looking contract.
/// 3. **The exact MP_ITEM/MP_MAINTENANCE feed JSON schema below is a
///    best-effort placeholder, not verified against Walmart's current
///    docs** (`docs/API_RESEARCH.md` flags this explicitly) - the feed
///    submit-and-poll *mechanism* is the confident, tested part; the
///    payload shape inside a feed needs a real docs pass, and likely
///    category-specific attributes, before this creates a real listing.
class WalmartAdapter implements StoreAdapter {
  WalmartAdapter({
    required this.oauth,
    this.accountConfig = const WalmartAccountConfig(),
    this.baseUrl = 'https://marketplace.walmartapis.com',
    http.Client? httpClient,
    this.feedPollInterval = const Duration(seconds: 3),
    this.feedPollTimeout = const Duration(minutes: 2),
  }) : _http = httpClient ?? http.Client();

  final WalmartOAuthClient oauth;
  final WalmartAccountConfig accountConfig;
  final String baseUrl;
  final Duration feedPollInterval;
  final Duration feedPollTimeout;
  final http.Client _http;

  @override
  String get platform => 'walmart';

  @override
  Future<RemoteListing?> getListing(String externalListingId) async {
    final inventory = await _get('/v3/inventory?sku=$externalListingId');
    if (inventory == null) return null;

    final quantity = (inventory['quantity']?['amount'] as num?)?.toInt() ?? 0;

    // Price isn't on the Inventory response - a separate lookup, best
    // guess at the right endpoint until confirmed (see class doc comment).
    final item = await _get('/v3/items/$externalListingId');
    final price = double.tryParse(
          item?['price']?['amount']?.toString() ?? '',
        ) ??
        0;

    return RemoteListing(
      externalListingId: externalListingId,
      quantity: quantity,
      price: price,
      isLive: quantity > 0,
    );
  }

  @override
  Future<int> getInventory(String externalListingId) async {
    final listing = await getListing(externalListingId);
    return listing?.quantity ?? 0;
  }

  @override
  Future<CreatedListing> createListing(CatalogItem item) async {
    final feedId = await _submitFeed(
      feedType: 'MP_ITEM',
      payload: _buildItemFeedPayload(item),
    );
    await _pollFeedUntilDone(feedId);

    // Set initial quantity via the Inventory API rather than the item feed
    // - keeps quantity's source of truth in one place (the confident,
    // synchronous API) regardless of how item creation itself works.
    await _putInventory(item.sku, item.quantity);

    return CreatedListing(externalListingId: item.sku);
  }

  @override
  Future<void> updateListing(
    String externalListingId, {
    int? quantity,
    double? price,
  }) async {
    if (quantity != null) {
      await _putInventory(externalListingId, quantity);
    }

    if (price != null) {
      final feedId = await _submitFeed(
        feedType: 'MP_MAINTENANCE',
        payload: _buildPriceMaintenancePayload(externalListingId, price),
      );
      await _pollFeedUntilDone(feedId);
    }
  }

  @override
  Future<void> delist(String externalListingId) async {
    // No confirmed eBay-style "withdraw" - zeroing quantity is the
    // confident mechanism (see class doc comment). Reuses the same
    // auto-unlist behavior section 5's reconciliation logic already
    // depends on for every adapter.
    await _putInventory(externalListingId, 0);
  }

  Future<void> _putInventory(String sku, int quantity) async {
    await _put('/v3/inventory?sku=$sku', {
      'sku': sku,
      'quantity': {
        'unit': 'EACH',
        'amount': quantity,
      },
      if (accountConfig.shipNode != null) 'shipNode': accountConfig.shipNode,
    });
  }

  Map<String, dynamic> _buildItemFeedPayload(CatalogItem item) {
    return {
      'MPItemFeedHeader': {
        'version': '5.0',
        'requestId': item.sku,
        'totalItemsCount': 1,
      },
      'MPItem': [
        {
          'sku': item.sku,
          'productName': item.title,
          if (item.description != null) 'productDescription': item.description,
          'price': {'currency': 'USD', 'amount': item.price},
          if (item.images.isNotEmpty) 'mainImageUrl': item.images.first,
          if (item.condition != null) 'condition': item.condition,
        },
      ],
    };
  }

  Map<String, dynamic> _buildPriceMaintenancePayload(String sku, double price) {
    return {
      'MPMaintenanceFeedHeader': {
        'version': '5.0',
        'requestId': sku,
      },
      'MPMaintenance': [
        {
          'sku': sku,
          'price': {'currency': 'USD', 'amount': price},
        },
      ],
    };
  }

  Future<String> _submitFeed({
    required String feedType,
    required Map<String, dynamic> payload,
  }) async {
    final token = await oauth.getValidAccessToken();
    final uri = Uri.parse('$baseUrl/v3/feeds').replace(queryParameters: {'feedType': feedType});

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'application/json'})
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          utf8.encode(jsonEncode(payload)),
          filename: 'feed.json',
        ),
      );

    final streamedResponse = await _http.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    _throwIfError(response);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['feedId'] as String;
  }

  Future<void> _pollFeedUntilDone(String feedId) async {
    final deadline = DateTime.now().add(feedPollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await _get('/v3/feeds/$feedId');
      final feedStatus = status?['feedStatus'] as String?;

      if (feedStatus == 'PROCESSED') return;
      if (feedStatus == 'ERROR') {
        throw StoreAdapterRequestException(
          'Walmart feed $feedId finished with errors: ${status?['itemsFailed']} item(s) failed',
        );
      }

      await Future.delayed(feedPollInterval);
    }

    throw StoreAdapterRequestException('Walmart feed $feedId did not finish within $feedPollTimeout');
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final token = await oauth.getValidAccessToken();
    final response = await _http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (response.statusCode == 404) return null;
    _throwIfError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final token = await oauth.getValidAccessToken();
    final response = await _http.put(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    _throwIfError(response);
  }

  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    if (response.statusCode == 429) {
      final retryAfterHeader = response.headers['retry-after'];
      throw StoreAdapterRateLimitException(
        'Walmart rate limit hit.',
        retryAfter:
            retryAfterHeader == null ? null : Duration(seconds: int.tryParse(retryAfterHeader) ?? 0),
      );
    }

    if (response.statusCode == 401) {
      throw StoreAdapterAuthException('Walmart rejected the access token: ${response.body}');
    }

    throw StoreAdapterRequestException(
      'Walmart API error',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }
}
