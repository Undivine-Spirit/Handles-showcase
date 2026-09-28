/// Whether the supplier (e.g. Amazon) currently has this item in stock -
/// distinct from any [CatalogItem]'s `quantity`, which tracks inventory
/// the seller physically owns. A sourced listing owns nothing; this is
/// the only "stock" concept it has, and it's about someone else's shelf.
enum SupplierStockStatus {
  inStock,
  outOfStock,

  /// Not checked yet, or the last check failed - deliberately distinct
  /// from [outOfStock] so a monitor outage doesn't get treated the same
  /// as a confirmed stock-out and delist something that's actually fine.
  unknown;

  static SupplierStockStatus fromJson(String value) => switch (value) {
        'in_stock' => SupplierStockStatus.inStock,
        'out_of_stock' => SupplierStockStatus.outOfStock,
        'unknown' => SupplierStockStatus.unknown,
        _ => throw ArgumentError('Unknown supplier stock status: $value'),
      };

  String toJson() => switch (this) {
        SupplierStockStatus.inStock => 'in_stock',
        SupplierStockStatus.outOfStock => 'out_of_stock',
        SupplierStockStatus.unknown => 'unknown',
      };
}

/// A listing backed by a supplier's stock, not the seller's own inventory -
/// see `docs/PROJECT_PLAN.md` section 10 for why this is deliberately a
/// separate type from [CatalogItem] rather than force-fit into it. Shares
/// the same [StoreAdapter] interface for actually pushing to a store; only
/// where the price/"in stock" signal comes from differs.
class SourcedListing {
  SourcedListing({
    required this.sku,
    required this.title,
    this.description,
    required this.sourceAsin,
    required this.sourcePrice,
    required this.destinationFeeRate,
    required this.desiredProfit,
    this.shippingCost = 0,
    this.category,
    this.brand,
    this.supplierStatus = SupplierStockStatus.unknown,
    this.lastCheckedAt,
    this.listings = const {},
  });

  factory SourcedListing.fromJson(Map<String, dynamic> json) {
    final listingsJson = (json['listings'] as Map<String, dynamic>?) ?? {};
    return SourcedListing(
      sku: json['sku'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      sourceAsin: json['source_asin'] as String,
      sourcePrice: (json['source_price'] as num).toDouble(),
      destinationFeeRate: (json['destination_fee_rate'] as num).toDouble(),
      desiredProfit: (json['desired_profit'] as num).toDouble(),
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0,
      category: json['category'] as String?,
      brand: json['brand'] as String?,
      supplierStatus: SupplierStockStatus.fromJson(
        json['supplier_status'] as String? ?? 'unknown',
      ),
      lastCheckedAt: json['last_checked_at'] == null
          ? null
          : DateTime.parse(json['last_checked_at'] as String),
      listings: listingsJson.map((key, value) => MapEntry(key, value as String)),
    );
  }

  final String sku;
  final String title;
  final String? description;

  /// The Amazon product this listing is backed by.
  final String sourceAsin;

  /// What it costs to buy from the supplier right now - the input to
  /// [SourcingPriceCalculator], not itself a listing price.
  final double sourcePrice;

  /// The *destination* platform's fee rate (eBay/Walmart, not Amazon's) -
  /// see [SourcingPriceCalculator]'s doc comment for why these are kept
  /// separate and never hardcoded.
  final double destinationFeeRate;

  final double desiredProfit;
  final double shippingCost;
  final String? category;

  /// The Amazon product's brand/manufacturer name, when known - what
  /// `BrandRiskChecker` matches against before this listing gets pushed
  /// anywhere. `null` when not entered yet (manual sourcing, pre-Keepa) -
  /// the risk check is simply skipped in that case, not treated as clear.
  final String? brand;

  final SupplierStockStatus supplierStatus;
  final DateTime? lastCheckedAt;

  /// Account key -> external listing id, once pushed - deliberately no
  /// per-store `sync_status`/quantity like [CatalogItem.stores] carries;
  /// there's no owned quantity here to reconcile, just "is it live."
  final Map<String, String> listings;

  bool get isSourcedOut => supplierStatus == SupplierStockStatus.outOfStock;
  bool get isLive => listings.isNotEmpty;

  SourcedListing copyWith({
    SupplierStockStatus? supplierStatus,
    DateTime? lastCheckedAt,
    Map<String, String>? listings,
  }) {
    return SourcedListing(
      sku: sku,
      title: title,
      description: description,
      sourceAsin: sourceAsin,
      sourcePrice: sourcePrice,
      destinationFeeRate: destinationFeeRate,
      desiredProfit: desiredProfit,
      shippingCost: shippingCost,
      category: category,
      brand: brand,
      supplierStatus: supplierStatus ?? this.supplierStatus,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      listings: listings ?? this.listings,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'title': title,
        if (description != null) 'description': description,
        'source_asin': sourceAsin,
        'source_price': sourcePrice,
        'destination_fee_rate': destinationFeeRate,
        'desired_profit': desiredProfit,
        if (shippingCost != 0) 'shipping_cost': shippingCost,
        if (category != null) 'category': category,
        if (brand != null) 'brand': brand,
        'supplier_status': supplierStatus.toJson(),
        if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt!.toIso8601String(),
        'listings': listings,
      };
}
