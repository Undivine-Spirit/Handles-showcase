import 'dart:convert';
import 'dart:io';

import 'package:handles_core/handles_core.dart';

/// Headless reconciliation - the "where does the reconciliation engine
/// actually run" open question from PROJECT_PLAN.md section 10, answered:
/// self-hosted, not tied to the desktop app being open. Reads/writes the
/// same `catalog/` directory the app and adapters already agree on.
///
/// Two deployment shapes share this one binary, chosen by [_DaemonConfig.runOnce]:
/// - **docker-compose** (`RUN_ONCE` unset): loops forever internally,
///   sleeping [_DaemonConfig.interval] between passes. The container
///   itself is the thing that's "always on" (`restart: unless-stopped`).
/// - **Kubernetes `CronJob`** (`RUN_ONCE=true`): runs exactly one pass and
///   exits. Kubernetes' own CronJob controller owns the schedule and
///   creates a fresh Pod each time - a container that loops forever would
///   fight that model rather than fit it. See `k8s/cronjob.yaml`.
Future<void> main() async {
  final config = _DaemonConfig.fromEnvironment();
  _log('Handles reconciliation daemon starting');
  _log('  catalog dir : ${config.catalogDir}');
  _log('  secrets dir : ${config.secretsDir}');
  _log('  git sync    : ${config.gitSyncEnabled ? 'enabled' : 'disabled'}');

  if (config.runOnce) {
    _log('  mode        : run-once (Kubernetes CronJob style)');
    try {
      await _runOnce(config);
    } catch (e, stackTrace) {
      _log('ERROR during reconciliation pass: $e');
      _log(stackTrace.toString());
      exit(1); // a non-zero exit is how a CronJob's Pod reports failure
    }
    return;
  }

  _log('  mode        : loop (docker-compose style), interval ${config.interval}, '
      'trigger check every ${config.triggerCheckInterval}');
  while (true) {
    try {
      await _runOnce(config);
    } catch (e, stackTrace) {
      _log('ERROR during reconciliation pass: $e');
      _log(stackTrace.toString());
    }
    _log('Sleeping up to ${config.interval} until the next pass '
        '(or sooner if webhook_server.dart drops a trigger file)...');
    await _sleepUntilNextPassOrTrigger(config);
  }
}

/// Sleeps for [_DaemonConfig.interval], but wakes early - and consumes the
/// file - if `webhook_server.dart` (a separate container sharing this same
/// `CATALOG_DIR` mount) drops a trigger file after a real marketplace
/// webhook fires. Polling a file every few seconds rather than exposing a
/// network endpoint here keeps this daemon exactly as it was: headless, no
/// port, no new auth surface between internal services.
Future<void> _sleepUntilNextPassOrTrigger(_DaemonConfig config) async {
  final triggerFile = File('${config.catalogDir}/.trigger-now');
  final deadline = DateTime.now().add(config.interval);

  while (DateTime.now().isBefore(deadline)) {
    if (await triggerFile.exists()) {
      _log('Trigger file found - running an immediate pass instead of waiting out the interval.');
      await triggerFile.delete();
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    await Future.delayed(remaining < config.triggerCheckInterval ? remaining : config.triggerCheckInterval);
  }
}

Future<void> _runOnce(_DaemonConfig config) async {
  if (config.resourceCheckEnabled) {
    try {
      final snapshot = await ProcSystemResourcesReader().read();
      _log('System resources: $snapshot');
      if (snapshot.isConstrained) {
        _log('Skipping this pass - device is under real load, deferring rather than adding to it.');
        return;
      }
    } catch (e) {
      // Fail open: a broken resource check (missing /proc, permissions,
      // unexpected format on a host this wasn't tested against) should
      // not block the actual reconciliation work. Log it and proceed.
      _log('Resource check failed ($e) - proceeding without it this pass.');
    }
  }

  final storesFile = File('${config.catalogDir}/stores.json');
  if (!await storesFile.exists()) {
    _log('No catalog/stores.json at ${storesFile.path} - nothing to reconcile against.');
    return;
  }

  final registry = parseStoreAccountRegistry(
    jsonDecode(await storesFile.readAsString()) as Map<String, dynamic>,
  );
  final credentialStore = FileCredentialStore(config.secretsDir);
  final adapters = await _buildAdapters(registry, credentialStore);

  final repository = CatalogRepository(Directory(config.catalogDir));
  // Lives inside the catalog directory on purpose - GitSync below commits
  // the whole directory, so the event log travels with the catalog it
  // describes rather than being stranded on whichever machine ran this
  // pass. That's what lets the app show real history later even though
  // it and the daemon don't share a filesystem (self-hosted, possibly on
  // different hardware entirely - a Raspberry Pi cluster vs. a desktop).
  final eventLog = EventLogStore(File('${config.catalogDir}/.events.jsonl'));
  final items = await repository.loadAll();
  _log('Loaded ${items.length} catalog item(s); ${adapters.length} account(s) ready to reconcile against.');

  final engine = ReconciliationEngine(adapters: adapters);
  var changed = false;

  for (final item in items) {
    final result = await engine.reconcile(item);
    if (result.actions.isEmpty) continue;

    for (final action in result.actions) {
      _log('  ${item.sku}: $action');
      await eventLog.append(HandlesEvent(
        timestamp: DateTime.now().toUtc(),
        severity: _severityFor(action.outcome),
        source: 'reconciliation',
        message: action.toString(),
        sku: item.sku,
        accountKey: action.accountKey,
      ));
    }
    await repository.save(result.item);
    changed = true;
  }

  if (!changed) {
    _log('No changes this pass.');
    return;
  }

  if (!config.gitSyncEnabled) {
    _log('Catalog changed but GIT_SYNC_ENABLED is not "true" - not committing.');
    return;
  }

  await GitSync(config.catalogDir).commitAndPush(
    'Reconciliation pass ${DateTime.now().toUtc().toIso8601String()}',
  );
  _log('Committed and pushed catalog changes.');
}

/// One [StoreAdapter] per account whose secrets file has everything its
/// platform needs. Dispatches by [StoreAccount.platform] - eBay and
/// Walmart need genuinely different fields (see each helper below), not
/// just different classes.
Future<Map<String, StoreAdapter>> _buildAdapters(
  Map<String, StoreAccount> registry,
  CredentialStore credentialStore,
) async {
  final adapters = <String, StoreAdapter>{};

  for (final account in registry.values) {
    if (account.automation != AutomationLevel.full) continue;

    final adapter = switch (account.platform) {
      'ebay' => await _buildEbayAdapter(account, credentialStore),
      'walmart' => await _buildWalmartAdapter(account, credentialStore),
      _ => null,
    };

    if (adapter == null) continue;
    adapters[account.accountKey] = adapter;
    _log('  ${account.accountKey}: adapter ready.');
  }

  return adapters;
}

/// Client credentials AND the account's Business Policy IDs (Seller Hub,
/// not something to guess) - both live in the same secrets file
/// `EbayOAuthClient` already writes tokens into; pre-seed those extra
/// fields by hand before the first run, see `core/README.md`.
Future<StoreAdapter?> _buildEbayAdapter(
  StoreAccount account,
  CredentialStore credentialStore,
) async {
  const requiredFields = [
    'client_id',
    'client_secret',
    'redirect_uri',
    'fulfillment_policy_id',
    'payment_policy_id',
    'return_policy_id',
  ];

  final stored = await credentialStore.read(account.accountKey);
  if (stored == null) {
    _log('  ${account.accountKey}: no secrets file yet, skipping.');
    return null;
  }

  final missing = requiredFields.where((f) => (stored[f] ?? '').isEmpty).toList();
  if (missing.isNotEmpty) {
    _log('  ${account.accountKey}: secrets file is missing ${missing.join(', ')}, skipping.');
    return null;
  }

  if ((stored['refresh_token'] ?? '').isEmpty) {
    _log('  ${account.accountKey}: no refresh token yet - run the one-time consent flow '
        '(desktop app\'s Settings screen) before this account can be automated here.');
    return null;
  }

  final oauth = EbayOAuthClient(
    accountKey: account.accountKey,
    clientId: stored['client_id']!,
    clientSecret: stored['client_secret']!,
    redirectUri: stored['redirect_uri']!,
    credentialStore: credentialStore,
  );

  return EbayAdapter(
    oauth: oauth,
    accountConfig: EbayAccountConfig(
      fulfillmentPolicyId: stored['fulfillment_policy_id']!,
      paymentPolicyId: stored['payment_policy_id']!,
      returnPolicyId: stored['return_policy_id']!,
      merchantLocationKey: stored['merchant_location_key'],
    ),
    // Placeholder mapping until a real eBay-category lookup exists - same
    // caveat as EbayCategoryResolver's own doc comment.
    categoryResolver: (item) => item.category ?? 'Uncategorized',
  );
}

/// Simpler than eBay's: client-credentials grant needs no consent flow
/// and no refresh token check - `WalmartOAuthClient.getValidAccessToken`
/// mints one on first use.
Future<StoreAdapter?> _buildWalmartAdapter(
  StoreAccount account,
  CredentialStore credentialStore,
) async {
  final stored = await credentialStore.read(account.accountKey);
  if (stored == null) {
    _log('  ${account.accountKey}: no secrets file yet, skipping.');
    return null;
  }

  final missing = ['client_id', 'client_secret'].where((f) => (stored[f] ?? '').isEmpty).toList();
  if (missing.isNotEmpty) {
    _log('  ${account.accountKey}: secrets file is missing ${missing.join(', ')}, skipping.');
    return null;
  }

  final oauth = WalmartOAuthClient(
    accountKey: account.accountKey,
    clientId: stored['client_id']!,
    clientSecret: stored['client_secret']!,
    credentialStore: credentialStore,
  );

  return WalmartAdapter(
    oauth: oauth,
    accountConfig: WalmartAccountConfig(shipNode: stored['ship_node']),
  );
}

void _log(String message) {
  stdout.writeln('[${DateTime.now().toUtc().toIso8601String()}] $message');
}

/// What the duty-reminder system (section 11) actually watches for - an
/// oversell needs a human right away (an order has to be cancelled or
/// refunded, which this engine can never do itself), errors need a look,
/// a reconciled external sale is worth knowing but not urgent (v2 already
/// handled it), everything else is just history.
EventSeverity _severityFor(ReconciliationOutcome outcome) => switch (outcome) {
      ReconciliationOutcome.oversold => EventSeverity.actionNeeded,
      ReconciliationOutcome.error => EventSeverity.error,
      ReconciliationOutcome.externalSaleReconciled ||
      ReconciliationOutcome.created ||
      ReconciliationOutcome.updated ||
      ReconciliationOutcome.delisted ||
      ReconciliationOutcome.alreadyInSync =>
        EventSeverity.info,
    };

class _DaemonConfig {
  _DaemonConfig({
    required this.catalogDir,
    required this.secretsDir,
    required this.interval,
    required this.triggerCheckInterval,
    required this.gitSyncEnabled,
    required this.runOnce,
    required this.resourceCheckEnabled,
  });

  factory _DaemonConfig.fromEnvironment() {
    final env = Platform.environment;
    return _DaemonConfig(
      catalogDir: env['CATALOG_DIR'] ?? '/app/catalog',
      secretsDir: env['SECRETS_DIR'] ?? '/app/secrets',
      interval: Duration(minutes: int.tryParse(env['RECONCILE_INTERVAL_MINUTES'] ?? '') ?? 15),
      // How often the loop wakes up just to check for webhook_server.dart's
      // trigger file - unrelated to RUN_ONCE/Kubernetes, which never sleeps
      // at all.
      triggerCheckInterval:
          Duration(seconds: int.tryParse(env['TRIGGER_CHECK_INTERVAL_SECONDS'] ?? '') ?? 5),
      gitSyncEnabled: (env['GIT_SYNC_ENABLED'] ?? 'false').toLowerCase() == 'true',
      // "true" means a Kubernetes CronJob is scheduling this - see the
      // doc comment on main() for why that changes the run shape.
      runOnce: (env['RUN_ONCE'] ?? 'false').toLowerCase() == 'true',
      // On by default - PROJECT_PLAN.md section 7's revised note: this is
      // where resource-awareness actually matters now (a Raspberry Pi
      // cluster, not a desktop). Reading /proc costs nothing; skipping a
      // pass under real load costs nothing either. Escape hatch exists
      // for a host where /proc doesn't behave as expected, not because
      // the check itself is expensive.
      resourceCheckEnabled: (env['RESOURCE_CHECK_ENABLED'] ?? 'true').toLowerCase() == 'true',
    );
  }

  final String catalogDir;
  final String secretsDir;
  final Duration interval;
  final Duration triggerCheckInterval;
  final bool gitSyncEnabled;
  final bool runOnce;
  final bool resourceCheckEnabled;
}
