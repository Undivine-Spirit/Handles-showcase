import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../catalog_item.dart';
import '../exceptions.dart';
import '../store_adapter.dart';
import 'ebay_oauth_client.dart';

/// Account-level eBay config that isn't tied to any one item - eBay's
/// Business Policies (fulfillment/payment/return) are set up once per
/// seller account in Seller Hub, not per listing, and are required on
/// every offer.
class EbayAccountConfig {
  const EbayAccountConfig({
    this.marketplaceId = 'EBAY_US',
    required this.fulfillmentPolicyId,
    required this.paymentPolicyId,
    required this.returnPolicyId,
    this.merchantLocationKey,
  });

  final String marketplaceId;
  final String fulfillmentPolicyId;
  final String paymentPolicyId;
  final String returnPolicyId;

  /// Required by eBay's offer creation for most categories - the seller's
  /// configured inventory location key from Seller Hub.
  final String? merchantLocationKey;
}

/// Maps a [CatalogItem] to the eBay numeric category ID its listing
/// belongs under. eBay's category taxonomy is deep and marketplace-specific
/// (thousands of leaf categories) and isn't something to hardcode a mapping
/// table for here - the account wiring this adapter up supplies the
/// mapping logic (e.g. backed by a lookup table keyed on
/// [CatalogItem.category], or eBay's own Taxonomy API).
typedef EbayCategoryResolver = String Function(CatalogItem item);

/// eBay implementation of [StoreAdapter], bound to one seller account.
///
/// Uses eBay's Inventory API, which splits a listing into two linked
/// objects (`docs/API_RESEARCH.md`): an inventory item (product data,
/// keyed by SKU) and an offer (the live price/quantity, published to make
/// it actually appear on eBay). [createListing] does both steps; a plain
/// quantity/price change only touches one or the other.
class EbayAdapter implements StoreAdapter {
  EbayAdapter({
    required this.oauth,
    required this.accountConfig,
    required this.categoryResolver,
    this.baseUrl = 'https://api.ebay.com',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final EbayOAuthClient oauth;
  final EbayAccountConfig accountConfig;
  final EbayCategoryResolver categoryResolver;
  final String baseUrl;
  final http.Client _http;

  @override
  String get platform => 'ebay';

  @override
  Future<RemoteListing?> getListing(String externalListingId) async {
    final offer = await _get('/sell/inventory/v1/offer/$externalListingId');
    if (offer == null) return null;

    final sku = offer['sku'] as String;
    final inventoryItem = await _get('/sell/inventory/v1/inventory_item/$sku');
    final quantity = inventoryItem == null
        ? 0
        : (_availabilityQuantity(inventoryItem) ?? 0);

    final price = double.parse(
      (offer['pricingSummary']?['price']?['value'] as String?) ?? '0',
    );

    return RemoteListing(
      externalListingId: externalListingId,
      externalOfferId: externalListingId,
      quantity: quantity,
      price: price,
      isLive: offer['status'] == 'PUBLISHED',
    );
  }

  @override
  Future<int> getInventory(String externalListingId) async {
    final listing = await getListing(externalListingId);
    return listing?.quantity ?? 0;
  }

  @override
  Future<CreatedListing> createListing(CatalogItem item) async {
    await _putInventoryItem(item);

    final offerBody = <String, dynamic>{
      'sku': item.sku,
      'marketplaceId': accountConfig.marketplaceId,
      'format': 'FIXED_PRICE',
      'availableQuantity': item.quantity,
      'categoryId': categoryResolver(item),
      if (item.description != null) 'listingDescription': item.description,
      'pricingSummary': {
        'price': {'value': item.price.toStringAsFixed(2), 'currency': 'USD'},
      },
      'listingPolicies': {
        'fulfillmentPolicyId': accountConfig.fulfillmentPolicyId,
        'paymentPolicyId': accountConfig.paymentPolicyId,
        'returnPolicyId': accountConfig.returnPolicyId,
      },
      if (accountConfig.merchantLocationKey != null)
        'merchantLocationKey': accountConfig.merchantLocationKey,
    };

    final offerResponse = await _post('/sell/inventory/v1/offer', offerBody);
    final offerId = offerResponse['offerId'] as String;

    final publishResponse =
        await _post('/sell/inventory/v1/offer/$offerId/publish', const {});
    final listingId = publishResponse['listingId'] as String?;

    return CreatedListing(
      externalListingId: listingId ?? offerId,
      externalOfferId: offerId,
    );
  }

  @override
  Future<void> updateListing(
    String externalListingId, {
    int? quantity,
    double? price,
  }) async {
    if (price != null) {
      await _put('/sell/inventory/v1/offer/$externalListingId', {
        'pricingSummary': {
          'price': {'value': price.toStringAsFixed(2), 'currency': 'USD'},
        },
      });
    }

    if (quantity != null) {
      final offer = await _get('/sell/inventory/v1/offer/$externalListingId');
      if (offer == null) {
        throw StoreAdapterNotFoundException(
          'eBay offer "$externalListingId" not found - cannot update quantity.',
        );
      }
      final sku = offer['sku'] as String;
      await _put('/sell/inventory/v1/inventory_item/$sku', {
        'availability': {
          'shipToLocationAvailability': {'quantity': quantity},
        },
      });
    }
  }

  @override
  Future<void> delist(String externalListingId) async {
    // Withdraw, not delete - keeps the underlying inventory item so the
    // SKU can be relisted later without recreating product data from
    // scratch. See StoreAdapter.delist's doc comment.
    await _post('/sell/inventory/v1/offer/$externalListingId/withdraw', const {});
  }

  Future<void> _putInventoryItem(CatalogItem item) async {
    await _put('/sell/inventory/v1/inventory_item/${item.sku}', {
      'availability': {
        'shipToLocationAvailability': {'quantity': item.quantity},
      },
      'condition': _ebayCondition(item.condition),
      'product': {
        'title': item.title,
        if (item.description != null) 'description': item.description,
        if (item.images.isNotEmpty) 'imageUrls': item.images,
      },
    });
  }

  int? _availabilityQuantity(Map<String, dynamic> inventoryItem) {
    final availability =
        inventoryItem['availability']?['shipToLocationAvailability'];
    return availability == null ? null : availability['quantity'] as int?;
  }

  /// Free-text `condition` (catalog schema) -> eBay's condition enum.
  /// Deliberately small and defaulting to USED rather than guessing wrong
  /// in the NEW direction - refine as real catalog condition values are
  /// seen. See eBay's condition enum docs for the full list per category.
  String _ebayCondition(String? condition) {
    final normalized = condition?.toLowerCase().trim();
    return switch (normalized) {
      'new' => 'NEW',
      'new with tags' => 'NEW_WITH_TAGS',
      'new without tags' => 'NEW_WITHOUT_TAGS',
      'like new' || 'excellent' => 'LIKE_NEW',
      'good' => 'USED_GOOD',
      'fair' => 'USED_ACCEPTABLE',
      _ => 'USED_GOOD',
    };
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final token = await oauth.getValidAccessToken();
    final response = await _http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 404) return null;
    _throwIfError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final token = await oauth.getValidAccessToken();
    final response = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    _throwIfError(response);
    return response.body.isEmpty
        ? const {}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final token = await oauth.getValidAccessToken();
    final response = await _http.put(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
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
        'eBay rate limit hit (${oauth.accountKey}).',
        retryAfter: retryAfterHeader == null
            ? null
            : Duration(seconds: int.tryParse(retryAfterHeader) ?? 0),
      );
    }

    if (response.statusCode == 401) {
      throw StoreAdapterAuthException(
        'eBay rejected the access token for ${oauth.accountKey}: ${response.body}',
      );
    }

    throw StoreAdapterRequestException(
      'eBay API error for ${oauth.accountKey}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }
}
