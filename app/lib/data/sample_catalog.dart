import 'package:handles_core/handles_core.dart';

/// Placeholder data for the first screen - the same illustrative items
/// used in the Handles Console mockup, not real inventory. Replace once
/// the GitHub state layer (PROJECT_PLAN.md section 3, component 3) can
/// actually read `catalog/*.json` from the repo at runtime.
List<CatalogItem> sampleCatalog() => [
      CatalogItem(
        sku: 'HND-0142',
        title: "Nike Air Force 1 '07 — Triple White",
        price: 109,
        quantity: 6,
        category: 'Sneakers',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-1',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0158',
        title: 'Carhartt WIP Detroit Jacket — Hamilton Brown',
        price: 164,
        quantity: 2,
        category: 'Outerwear',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-2',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0091',
        title: 'Vintage Champion Reverse Weave Hoodie — Faded Navy',
        price: 58,
        quantity: 1,
        category: 'Vintage',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-3',
            syncStatus: SyncStatus.conflict,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0203',
        title: 'New Balance 550 — White / Grey',
        price: 98,
        quantity: 0,
        category: 'Sneakers',
        stores: {
          'ebay_store_b': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-4',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0177',
        title: "Levi's 501 '93 Straight — Vintage Wash, W32",
        price: 46,
        quantity: 4,
        category: 'Denim',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-5',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0119',
        title: 'Patagonia Retro-X Fleece — Natural Tan, M',
        price: 88,
        quantity: 3,
        category: 'Outerwear',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-6',
            syncStatus: SyncStatus.pending,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0064',
        title: 'Supreme Box Logo Tee SS23 — Black, L',
        price: 210,
        quantity: 1,
        category: 'Streetwear',
        stores: {
          'ebay_store_b': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-7',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
      CatalogItem(
        sku: 'HND-0231',
        title: 'Salomon XT-6 — Magnet / Black',
        price: 132,
        quantity: 5,
        category: 'Sneakers',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-8',
            syncStatus: SyncStatus.confirmed,
          ),
          'walmart': StoreListingState(platform: 'walmart', syncStatus: SyncStatus.manualOnly),
        },
      ),
    ];
