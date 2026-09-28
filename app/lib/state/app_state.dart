import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:handles_core/handles_core.dart';

import '../data/known_accounts.dart';
import '../data/sample_catalog.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_api_config.dart';
import '../services/connect_result.dart';
import '../services/ebay_app_config.dart';
import '../services/ebay_loopback_auth_flow.dart';
import '../services/keepa_config.dart';
import '../services/reminder_service.dart';
import '../services/walmart_app_config.dart';
import '../theme/handles_colors.dart';
import '../theme/handles_palette.dart';

/// App-wide state: settings, connected-account status, and the actions
/// that change either. Deliberately plain `ChangeNotifier` rather than a
/// state-management package - the app is small enough that Flutter's own
/// primitive is the right amount of machinery.
class AppState extends ChangeNotifier {
  AppState({
    required this.settingsStore,
    required this.credentialStore,
  })  : ebayAppConfigStore = EbayAppConfigStore(credentialStore),
        walmartAppConfigStore = WalmartAppConfigStore(credentialStore),
        keepaConfigStore = KeepaConfigStore(credentialStore),
        catalogApiConfigStore = CatalogApiConfigStore(credentialStore);

  final SettingsStore settingsStore;
  final CredentialStore credentialStore;
  final EbayAppConfigStore ebayAppConfigStore;
  final WalmartAppConfigStore walmartAppConfigStore;
  final KeepaConfigStore keepaConfigStore;
  final CatalogApiConfigStore catalogApiConfigStore;
  final ReminderService _reminders = ReminderService();

  final List<StoreAccount> accounts = knownAccounts();

  HandlesSettings settings = const HandlesSettings();
  EbayAppConfig ebayAppConfig = EbayAppConfig.empty;
  WalmartAppConfig walmartAppConfig = WalmartAppConfig.empty;
  KeepaConfig keepaConfig = KeepaConfig.empty;
  CatalogApiConfig catalogApiConfig = CatalogApiConfig.empty;
  final Map<String, bool> _connected = {};
  bool _loading = true;

  /// Real catalog once a repository is configured and synced at least
  /// once; `sampleCatalog()` placeholder data until then, same as the
  /// Console screen always showed before this existed.
  List<CatalogItem> items = [];
  List<HandlesEvent> events = [];
  List<BrandRiskEntry> brandRiskEntries = [];
  bool isSyncing = false;
  String? syncError;
  DateTime? lastSyncedAt;
  Timer? _autoSyncTimer;

  bool get isLoading => _loading;
  bool isConnected(String accountKey) => _connected[accountKey] ?? false;

  Future<void> init() async {
    settings = await settingsStore.load();
    ebayAppConfig = await ebayAppConfigStore.load();
    walmartAppConfig = await walmartAppConfigStore.load();
    keepaConfig = await keepaConfigStore.load();
    catalogApiConfig = await catalogApiConfigStore.load();
    for (final account in accounts) {
      _connected[account.accountKey] = await credentialStore.read(account.accountKey) != null;
    }

    if (catalogApiConfig.isComplete) {
      // Fire-and-forget - an unreachable server shouldn't hold up the
      // rest of app startup. syncCatalog() reports its own errors.
      unawaited(syncCatalog());
      _logAction('App session started');
    } else {
      items = sampleCatalog();
    }

    _scheduleAutoSync();
    HandlesColors.setActive(HandlesPalette.resolve(settings));
    _loading = false;
    notifyListeners();
  }

  /// The actual fix for "notifications need to work quick": before this,
  /// the app only ever synced on cold start or a manual "Sync Now" tap, so
  /// an urgent event (a monitor-only platform sale, a conflict) could sit
  /// unseen for as long as the app happened to stay open between restarts.
  /// For Mercari/Poshmark/Vinted specifically, this polling-and-notifying
  /// loop *is* the automation (PROJECT_PLAN.md section 11/14) - there's no
  /// auto-delist to fall back on, so how fast the seller finds out is the
  /// whole value.
  ///
  /// Real desktop-app behavior on Windows: keeps firing as long as the
  /// process is running, minimized or not. On Android this only fires
  /// while the app is alive in the foreground/recently-backgrounded - the
  /// OS suspends a plain Dart `Timer` once it fully backgrounds the app,
  /// same as it would any other app's in-process timer. True
  /// always-running push on Android would need a server-push channel (the
  /// daemon calling something like FCM directly) instead of this
  /// client-side poll - not built, since that's a real backend/Firebase
  /// project this app doesn't have yet, not a small addition.
  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;

    final minutes = settings.autoSyncIntervalMinutes;
    if (!catalogApiConfig.isComplete || minutes <= 0) return;

    _autoSyncTimer = Timer.periodic(Duration(minutes: minutes), (_) => syncCatalog());
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> saveCatalogApiConfig(CatalogApiConfig config) async {
    catalogApiConfig = config;
    await catalogApiConfigStore.save(config);
    _scheduleAutoSync();
    notifyListeners();
  }

  /// Pulls the current catalog/events/brand-risk list from the server and
  /// reloads [items]/[events]/[brandRiskEntries], then lets
  /// [ReminderService] fire for whatever in there is new.
  Future<void> syncCatalog() async {
    if (!catalogApiConfig.isComplete) return;

    isSyncing = true;
    syncError = null;
    notifyListeners();

    try {
      final result = await CatalogApiClient(config: catalogApiConfig).sync();
      items = result.items;
      events = result.events;
      brandRiskEntries = result.brandRiskEntries;
      lastSyncedAt = DateTime.now();
      await _reminders.notifyForNewEvents(events);
    } on CatalogSyncException catch (e) {
      syncError = e.message;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  /// Adds [item] locally right away (so the UI reflects it immediately),
  /// then saves it to the server if one is configured. Rethrows on a save
  /// failure so the caller can tell the user their edit is only local so
  /// far - the in-memory list already has it either way.
  Future<void> addItem(CatalogItem item) async {
    items = [...items, item];
    notifyListeners();
    if (catalogApiConfig.isComplete) {
      await CatalogApiClient(config: catalogApiConfig).saveItem(item);
      _logAction('Item added: ${item.title}', sku: item.sku);
    }
  }

  /// Same contract as [addItem], for a new brand-risk entry - useful even
  /// before the sourcing engine has a UI of its own, since this is the
  /// same list `SourcingListingGenerator` will check once it does.
  Future<void> addBrandRiskEntry(BrandRiskEntry entry) async {
    brandRiskEntries = [...brandRiskEntries, entry];
    notifyListeners();
    if (catalogApiConfig.isComplete) {
      await CatalogApiClient(config: catalogApiConfig).addBrandRiskEntry(entry);
      _logAction('Brand risk entry added: ${entry.brand}');
    }
  }

  /// Same contract as [addBrandRiskEntry], for undoing one.
  Future<void> removeBrandRiskEntry(String brand) async {
    final normalized = brand.trim().toLowerCase();
    brandRiskEntries = brandRiskEntries.where((e) => e.brand.trim().toLowerCase() != normalized).toList();
    notifyListeners();
    if (catalogApiConfig.isComplete) {
      await CatalogApiClient(config: catalogApiConfig).removeBrandRiskEntry(brand);
      _logAction('Brand risk entry removed: $brand');
    }
  }

  /// Same contract as [addItem], for an edit to an existing SKU.
  Future<void> updateItem(CatalogItem item) async {
    items = [for (final existing in items) if (existing.sku == item.sku) item else existing];
    notifyListeners();
    if (catalogApiConfig.isComplete) {
      await CatalogApiClient(config: catalogApiConfig).saveItem(item);
      _logAction('Item updated: ${item.title}', sku: item.sku);
    }
  }

  /// The one path every settings change goes through - including theme
  /// changes (built-in preset or custom maker), so picking a new palette
  /// never needs a separate method callers have to remember to use
  /// instead of this one.
  Future<void> updateSettings(HandlesSettings next) async {
    settings = next;
    await settingsStore.save(next);
    _scheduleAutoSync();
    HandlesColors.setActive(HandlesPalette.resolve(next));
    notifyListeners();
  }

  Future<void> saveEbayAppConfig(EbayAppConfig config) async {
    ebayAppConfig = config;
    await ebayAppConfigStore.save(config);
    notifyListeners();
  }

  /// Opens the system browser to eBay's own login page - this app never
  /// sees the account's eBay password, only the resulting token.
  Future<ConnectResult> connectEbayAccount(String accountKey) async {
    if (!ebayAppConfig.isComplete) {
      return ConnectResult.failure(
        'Add the eBay developer app credentials (Client ID/Secret/Redirect URI) in Settings first.',
      );
    }

    final oauth = EbayOAuthClient(
      accountKey: accountKey,
      clientId: ebayAppConfig.clientId,
      clientSecret: ebayAppConfig.clientSecret,
      redirectUri: ebayAppConfig.redirectUri,
      credentialStore: credentialStore,
    );

    final result = await EbayLoopbackAuthFlow(oauth: oauth).connect();
    if (result.success) {
      _connected[accountKey] = true;
      notifyListeners();
      _logAction('eBay account connected', accountKey: accountKey);
    } else {
      _logAction('eBay account connect failed: ${result.error}',
          accountKey: accountKey, severity: EventSeverity.warning);
    }
    return result;
  }

  Future<void> saveWalmartAppConfig(WalmartAppConfig config) async {
    walmartAppConfig = config;
    await walmartAppConfigStore.save(config);
    notifyListeners();
  }

  /// No browser step - Walmart's client-credentials grant IS the account
  /// login, so "connecting" just means checking the credentials actually
  /// work by fetching a real token, and telling the user immediately if
  /// they don't rather than only finding out on the first real API call.
  Future<ConnectResult> connectWalmartAccount(String accountKey) async {
    if (!walmartAppConfig.isComplete) {
      return ConnectResult.failure('Add the Walmart Client ID/Secret in Settings first.');
    }

    final oauth = WalmartOAuthClient(
      accountKey: accountKey,
      clientId: walmartAppConfig.clientId,
      clientSecret: walmartAppConfig.clientSecret,
      credentialStore: credentialStore,
    );

    try {
      await oauth.getValidAccessToken();
    } on StoreAdapterAuthException catch (e) {
      _logAction('Walmart account connect failed: ${e.message}',
          accountKey: accountKey, severity: EventSeverity.warning);
      return ConnectResult.failure(e.message);
    }

    _connected[accountKey] = true;
    notifyListeners();
    _logAction('Walmart account connected', accountKey: accountKey);
    return ConnectResult.success();
  }

  Future<void> saveKeepaConfig(KeepaConfig config) async {
    keepaConfig = config;
    await keepaConfigStore.save(config);
    notifyListeners();
  }

  Future<void> disconnectAccount(String accountKey) async {
    await credentialStore.delete(accountKey);
    _connected[accountKey] = false;
    notifyListeners();
    _logAction('Account disconnected', accountKey: accountKey);
  }

  /// Fire-and-forget audit logging to the server (`GET /catalog/events`
  /// already surfaces these) - deliberately never awaited by callers and
  /// never lets a logging failure surface as a user-facing error. An
  /// unreachable/unconfigured server just means this particular action
  /// goes unlogged, not that the action itself should fail.
  void _logAction(
    String message, {
    String? sku,
    String? accountKey,
    EventSeverity severity = EventSeverity.info,
  }) {
    if (!catalogApiConfig.isComplete) return;
    unawaited(
      CatalogApiClient(config: catalogApiConfig)
          .logEvent(severity: severity, source: 'app_action', message: message, sku: sku, accountKey: accountKey)
          .catchError((_) {}),
    );
  }
}
