/// Which automation level a connected account supports - mirrors the
/// `automation` field in `catalog/stores.json`.
enum AutomationLevel {
  /// Fully automated read/write via an official API (eBay, Walmart).
  full,

  /// No official write API - `get_listing` for visibility only, everything
  /// else needs a human. See `docs/PROJECT_PLAN.md` section 13.
  monitorOnly,

  /// Not wired up yet by choice (Amazon, until there's a storefront to
  /// connect) - not a technical limitation like [monitorOnly].
  deferred;

  static AutomationLevel fromJson(String value) => switch (value) {
        'full' => AutomationLevel.full,
        'monitor_only' => AutomationLevel.monitorOnly,
        'deferred' => AutomationLevel.deferred,
        _ => throw ArgumentError('Unknown automation level: $value'),
      };
}

/// One entry from `catalog/stores.json` - identifies a connected seller
/// account. Does NOT carry credentials; see [CredentialStore] for those.
class StoreAccount {
  StoreAccount({
    required this.accountKey,
    required this.platform,
    this.displayName,
    this.storeUrl,
    required this.automation,
  });

  factory StoreAccount.fromJson(String accountKey, Map<String, dynamic> json) {
    return StoreAccount(
      accountKey: accountKey,
      platform: json['platform'] as String,
      displayName: json['display_name'] as String?,
      storeUrl: json['store_url'] as String?,
      automation: AutomationLevel.fromJson(json['automation'] as String),
    );
  }

  /// e.g. `ebay_store_a` - the key used in a [CatalogItem.stores] map
  /// and in `catalog/stores.json`. Stable identity for this account; never
  /// derive it from [displayName], which can change.
  final String accountKey;

  /// Which adapter handles this account - e.g. `ebay`. Multiple accounts
  /// can share a platform (two eBay stores is exactly why this project's
  /// catalog schema is keyed by account, not platform).
  final String platform;

  final String? displayName;
  final String? storeUrl;
  final AutomationLevel automation;
}

/// Parses a whole `catalog/stores.json` document into account-key ->
/// [StoreAccount]. Skips the `$comment` key that file uses for its own
/// human-readable header - not an account.
Map<String, StoreAccount> parseStoreAccountRegistry(Map<String, dynamic> json) {
  final accounts = <String, StoreAccount>{};
  for (final entry in json.entries) {
    if (entry.key.startsWith(r'$')) continue;
    accounts[entry.key] = StoreAccount.fromJson(entry.key, entry.value as Map<String, dynamic>);
  }
  return accounts;
}
