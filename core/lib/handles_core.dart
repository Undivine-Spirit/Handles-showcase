/// Platform-agnostic business logic for Handles - catalog model, the
/// shared store-adapter interface, and per-marketplace implementations.
library;

export 'src/api/catalog_data_store.dart';
export 'src/brand_risk/brand_risk_checker.dart';
export 'src/brand_risk/brand_risk_entry.dart';
export 'src/brand_risk/brand_risk_list.dart';
export 'src/catalog_item.dart';
export 'src/catalog_repository.dart';
export 'src/categorization/category.dart';
export 'src/categorization/category_recommender.dart';
export 'src/credential_store.dart';
export 'src/event_log.dart';
export 'src/git_sync.dart';
export 'src/settings/handles_settings.dart';
export 'src/store_account.dart';
export 'src/system_resources.dart';

export 'src/adapters/exceptions.dart';
export 'src/adapters/store_adapter.dart';

export 'src/adapters/ebay/ebay_adapter.dart';
export 'src/adapters/ebay/ebay_oauth_client.dart';

export 'src/adapters/walmart/walmart_adapter.dart';
export 'src/adapters/walmart/walmart_oauth_client.dart';

export 'src/profitability/amazon_fee_model.dart';
export 'src/profitability/amazon_profitability_calculator.dart';
export 'src/reconciliation/reconciliation_engine.dart';

export 'src/sourcing/sourced_listing.dart';
export 'src/sourcing/sourcing_listing_generator.dart';
export 'src/sourcing/sourcing_monitor.dart';
export 'src/sourcing/sourcing_price_calculator.dart';
export 'src/sourcing/supplier_stock_checker.dart';

export 'src/webhooks/ebay_notification_verifier.dart';
export 'src/webhooks/walmart_webhook_verifier.dart';
