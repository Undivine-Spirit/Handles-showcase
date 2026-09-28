import 'package:handles_core/handles_core.dart';

/// Mirrors `catalog/stores.json` - stand-in until the app can read that
/// registry file from the repo at runtime (same caveat as
/// `sample_catalog.dart`). Only `ebay_*` accounts have `automation: full`
/// with a working adapter today; the rest are represented so Settings can
/// show accurate status, not just the ones that happen to be automatable.
List<StoreAccount> knownAccounts() => [
      StoreAccount(
        accountKey: 'ebay_store_a',
        platform: 'ebay',
        displayName: 'eBay Store A',
        storeUrl: null,
        automation: AutomationLevel.full,
      ),
      StoreAccount(
        accountKey: 'ebay_store_b',
        platform: 'ebay',
        displayName: 'eBay Store B',
        storeUrl: null,
        automation: AutomationLevel.full,
      ),
      StoreAccount(
        accountKey: 'walmart',
        platform: 'walmart',
        displayName: null,
        storeUrl: null,
        automation: AutomationLevel.full,
      ),
      StoreAccount(
        accountKey: 'poshmark',
        platform: 'poshmark',
        displayName: 'Poshmark closet',
        storeUrl: null,
        automation: AutomationLevel.monitorOnly,
      ),
      StoreAccount(
        accountKey: 'vinted',
        platform: 'vinted',
        displayName: 'Vinted',
        storeUrl: null,
        automation: AutomationLevel.monitorOnly,
      ),
      StoreAccount(
        accountKey: 'mercari',
        platform: 'mercari',
        displayName: 'Mercari',
        storeUrl: null,
        automation: AutomationLevel.monitorOnly,
      ),
      StoreAccount(
        accountKey: 'amazon',
        platform: 'amazon',
        displayName: null,
        storeUrl: null,
        automation: AutomationLevel.deferred,
      ),
    ];
