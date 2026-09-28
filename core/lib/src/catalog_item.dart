/// Sync state of one catalog item on one connected store account.
///
/// Mirrors the `sync_status` enum in `catalog/schema.json` exactly - keep
/// these two in sync if either changes.
enum SyncStatus {
  pending,
  confirmed,
  conflict,
  manualOnly,
  error;

  static SyncStatus fromJson(String value) => switch (value) {
        'pending' => SyncStatus.pending,
        'confirmed' => SyncStatus.confirmed,
        'conflict' => SyncStatus.conflict,
        'manual_only' => SyncStatus.manualOnly,
        'error' => SyncStatus.error,
        _ => throw ArgumentError('Unknown sync_status: $value'),
      };

  String toJson() => switch (this) {
        SyncStatus.pending => 'pending',
        SyncStatus.confirmed => 'confirmed',
        SyncStatus.conflict => 'conflict',
        SyncStatus.manualOnly => 'manual_only',
        SyncStatus.error => 'error',
      };
}

/// One catalog item's state on one connected store *account* - the value
/// side of a `CatalogItem.stores` entry. Keyed by account key (e.g.
/// `ebay_store_a`), not by platform - see `catalog/schema.json`.
class StoreListingState {
  StoreListingState({
    required this.platform,
    this.externalListingId,
    this.externalOfferId,
    this.lastSyncedAt,
    required this.syncStatus,
    this.lastConfirmedQuantity,
    this.listingUrl,
  });

  factory StoreListingState.fromJson(Map<String, dynamic> json) {
    return StoreListingState(
      platform: json['platform'] as String,
      externalListingId: json['external_listing_id'] as String?,
      externalOfferId: json['external_offer_id'] as String?,
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
      syncStatus: SyncStatus.fromJson(json['sync_status'] as String),
      lastConfirmedQuantity: json['last_confirmed_quantity'] as int?,
      listingUrl: json['listing_url'] as String?,
    );
  }

  /// Which store adapter handles this account - e.g. 'ebay', 'walmart'.
  final String platform;

  final String? externalListingId;

  /// eBay-specific: the published offer tied to the inventory item.
  final String? externalOfferId;

  final DateTime? lastSyncedAt;

  final SyncStatus syncStatus;

  /// Direct link to this item's live listing on this account - a human
  /// opens and checks/manages it themselves. The deliberately manual
  /// alternative to scraping for Poshmark/Vinted/Mercari, which have no
  /// official API (docs/API_RESEARCH.md) - never fetched automatically.
  final String? listingUrl;

  /// What this store's own listed quantity was the last time reconciliation
  /// engine v2 verified a write - the baseline `ReconciliationEngine` reads
  /// against to tell "remote is behind because someone bought it there"
  /// apart from "remote is behind because we haven't pushed our own
  /// restock yet" (`docs/PROJECT_PLAN.md` section 5). `null` for a listing
  /// that's never been through a v2 write-then-verify yet - a fresh
  /// create doesn't get treated as a mystery drop just because there's no
  /// baseline to compare against.
  final int? lastConfirmedQuantity;

  StoreListingState copyWith({
    String? externalListingId,
    String? externalOfferId,
    DateTime? lastSyncedAt,
    SyncStatus? syncStatus,
    int? lastConfirmedQuantity,
    String? listingUrl,
  }) {
    return StoreListingState(
      platform: platform,
      externalListingId: externalListingId ?? this.externalListingId,
      externalOfferId: externalOfferId ?? this.externalOfferId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      lastConfirmedQuantity: lastConfirmedQuantity ?? this.lastConfirmedQuantity,
      listingUrl: listingUrl ?? this.listingUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'platform': platform,
        if (externalListingId != null) 'external_listing_id': externalListingId,
        if (externalOfferId != null) 'external_offer_id': externalOfferId,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt!.toIso8601String(),
        'sync_status': syncStatus.toJson(),
        if (lastConfirmedQuantity != null) 'last_confirmed_quantity': lastConfirmedQuantity,
        if (listingUrl != null) 'listing_url': listingUrl,
      };
}

/// One SKU's source-of-truth record. Mirrors `catalog/schema.json` -
/// keep the two in sync if either changes.
class CatalogItem {
  CatalogItem({
    required this.sku,
    required this.title,
    this.description,
    required this.price,
    required this.quantity,
    this.images = const [],
    this.category,
    this.condition,
    this.stores = const {},
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final storesJson = (json['stores'] as Map<String, dynamic>?) ?? {};
    return CatalogItem(
      sku: json['sku'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      images: (json['images'] as List<dynamic>?)?.cast<String>() ?? const [],
      category: json['category'] as String?,
      condition: json['condition'] as String?,
      stores: storesJson.map(
        (key, value) => MapEntry(
          key,
          StoreListingState.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  final String sku;
  final String title;
  final String? description;
  final double price;
  final int quantity;
  final List<String> images;
  final String? category;
  final String? condition;

  /// Keyed by account key (`catalog/stores.json`), not platform.
  final Map<String, StoreListingState> stores;

  /// `quantity == 0` triggers auto-unlist across every connected store -
  /// see `docs/PROJECT_PLAN.md` section 5.
  bool get isSoldOut => quantity == 0;

  CatalogItem copyWith({
    String? title,
    String? description,
    double? price,
    int? quantity,
    List<String>? images,
    String? category,
    String? condition,
    Map<String, StoreListingState>? stores,
  }) {
    return CatalogItem(
      sku: sku,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      images: images ?? this.images,
      category: category ?? this.category,
      condition: condition ?? this.condition,
      stores: stores ?? this.stores,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'title': title,
        if (description != null) 'description': description,
        'price': price,
        'quantity': quantity,
        if (images.isNotEmpty) 'images': images,
        if (category != null) 'category': category,
        if (condition != null) 'condition': condition,
        'stores': stores.map((key, value) => MapEntry(key, value.toJson())),
      };
}
