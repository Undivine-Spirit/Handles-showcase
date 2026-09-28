import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';

import '../services/catalog_api_client.dart';
import '../services/catalog_api_config.dart';
import '../services/ebay_app_config.dart';
import '../services/keepa_config.dart';
import '../services/reminder_service.dart';
import '../services/walmart_app_config.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/handles_colors.dart';
import '../theme/handles_palette.dart';
import '../theme/handles_theme.dart';
import '../widgets/status_pill.dart';
import 'theme_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HandlesColors.bg,
      appBar: AppBar(
        backgroundColor: HandlesColors.bg,
        elevation: 0,
        title: Text('Settings', style: HandlesText.stencil(fontSize: 28)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _EbayAppConfigSection(),
              SizedBox(height: 16),
              _WalmartAppConfigSection(),
              SizedBox(height: 16),
              _ConnectedAccountsSection(),
              SizedBox(height: 16),
              _CatalogServerSection(),
              SizedBox(height: 16),
              _SourcingEngineSection(),
              SizedBox(height: 16),
              _BrandRiskSection(),
              SizedBox(height: 16),
              _DutyRemindersSection(),
              SizedBox(height: 16),
              _ThemeSection(),
              SizedBox(height: 16),
              _PriorityCategoriesSection(),
              SizedBox(height: 16),
              _CustomCategoriesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HandlesColors.surface,
        border: Border.all(color: HandlesColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: HandlesColors.border)),
            ),
            child: Text(title, style: HandlesText.body(fontSize: 17, weight: FontWeight.w700)),
          ),
          Padding(padding: const EdgeInsets.all(18), child: child),
        ],
      ),
    );
  }
}

class _EbayAppConfigSection extends StatefulWidget {
  const _EbayAppConfigSection();

  @override
  State<_EbayAppConfigSection> createState() => _EbayAppConfigSectionState();
}

class _EbayAppConfigSectionState extends State<_EbayAppConfigSection> {
  late final TextEditingController _clientId;
  late final TextEditingController _clientSecret;
  late final TextEditingController _redirectUri;
  bool _initialized = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController();
    _clientSecret = TextEditingController();
    _redirectUri = TextEditingController();
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _redirectUri.dispose();
    super.dispose();
  }

  void _syncFrom(EbayAppConfig config) {
    if (_initialized) return;
    _clientId.text = config.clientId;
    _clientSecret.text = config.clientSecret;
    _redirectUri.text = config.redirectUri;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    _syncFrom(appState.ebayAppConfig);

    return _SectionCard(
      title: 'eBay Developer App',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'One registered app can service both eBay accounts below. Entered once here, '
            'not per-connect. Stored the same way account tokens are, not in plain text.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          _LabeledField(label: 'Client ID', controller: _clientId),
          const SizedBox(height: 10),
          _LabeledField(label: 'Client Secret', controller: _clientSecret, obscure: true),
          const SizedBox(height: 10),
          _LabeledField(
            label: 'Redirect URI (RuName)',
            controller: _redirectUri,
            hint: 'The RuName eBay generated, not a raw URL',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrimaryButton(
                label: 'Save',
                onPressed: () async {
                  await appState.saveEbayAppConfig(EbayAppConfig(
                    clientId: _clientId.text.trim(),
                    clientSecret: _clientSecret.text.trim(),
                    redirectUri: _redirectUri.text.trim(),
                  ));
                  setState(() => _savedMessage = 'Saved.');
                },
              ),
              if (_savedMessage != null) ...[
                const SizedBox(width: 12),
                Text(_savedMessage!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.good)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WalmartAppConfigSection extends StatefulWidget {
  const _WalmartAppConfigSection();

  @override
  State<_WalmartAppConfigSection> createState() => _WalmartAppConfigSectionState();
}

class _WalmartAppConfigSectionState extends State<_WalmartAppConfigSection> {
  late final TextEditingController _clientId;
  late final TextEditingController _clientSecret;
  bool _initialized = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController();
    _clientSecret = TextEditingController();
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  void _syncFrom(WalmartAppConfig config) {
    if (_initialized) return;
    _clientId.text = config.clientId;
    _clientSecret.text = config.clientSecret;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    _syncFrom(appState.walmartAppConfig);

    return _SectionCard(
      title: 'Walmart Seller Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Walmart ties these credentials directly to your seller account - no separate '
            'browser login step like eBay\'s. Connecting below checks them immediately.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          _LabeledField(label: 'Client ID', controller: _clientId),
          const SizedBox(height: 10),
          _LabeledField(label: 'Client Secret', controller: _clientSecret, obscure: true),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrimaryButton(
                label: 'Save',
                onPressed: () async {
                  await appState.saveWalmartAppConfig(WalmartAppConfig(
                    clientId: _clientId.text.trim(),
                    clientSecret: _clientSecret.text.trim(),
                  ));
                  setState(() => _savedMessage = 'Saved.');
                },
              ),
              if (_savedMessage != null) ...[
                const SizedBox(width: 12),
                Text(_savedMessage!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.good)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectedAccountsSection extends StatefulWidget {
  const _ConnectedAccountsSection();

  @override
  State<_ConnectedAccountsSection> createState() => _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  String? _accountBusy;
  String? _lastError;

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);

    return _SectionCard(
      title: 'Connected Accounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_lastError != null) ...[
            Text(_lastError!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.critical)),
            const SizedBox(height: 10),
          ],
          for (final account in appState.accounts) ...[
            _AccountRow(
              account: account,
              connected: appState.isConnected(account.accountKey),
              busy: _accountBusy == account.accountKey,
              onConnect: account.automation == AutomationLevel.full
                  ? () async {
                      setState(() {
                        _accountBusy = account.accountKey;
                        _lastError = null;
                      });
                      // Platform decides the flow, not a per-account
                      // setting - eBay needs a browser/consent step,
                      // Walmart's client-credentials grant doesn't.
                      final result = account.platform == 'walmart'
                          ? await appState.connectWalmartAccount(account.accountKey)
                          : await appState.connectEbayAccount(account.accountKey);
                      setState(() {
                        _accountBusy = null;
                        _lastError = result.success ? null : result.error;
                      });
                    }
                  : null,
              onDisconnect: () => appState.disconnectAccount(account.accountKey),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.connected,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });

  final StoreAccount account;
  final bool connected;
  final bool busy;
  final VoidCallback? onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final label = account.displayName ?? account.platform;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: HandlesText.body(fontSize: 14, weight: FontWeight.w600)),
              Text(
                account.platform,
                style: HandlesText.data(fontSize: 12, color: HandlesColors.inkFaint),
              ),
            ],
          ),
        ),
        switch (account.automation) {
          AutomationLevel.full => connected
              ? const StatusPill(label: 'Connected', tone: PillTone.confirmed)
              : const StatusPill(label: 'Not connected', tone: PillTone.pending),
          AutomationLevel.monitorOnly => const StatusPill(label: 'Monitor only', tone: PillTone.approval),
          AutomationLevel.deferred => const StatusPill(label: 'Deferred', tone: PillTone.delisted),
        },
        const SizedBox(width: 10),
        if (account.automation == AutomationLevel.full)
          _PrimaryButton(
            label: busy ? 'Connecting…' : (connected ? 'Reconnect' : 'Connect'),
            onPressed: busy ? null : onConnect,
            small: true,
          ),
        if (connected) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: onDisconnect,
            child: Text(
              'Disconnect',
              style: HandlesText.data(fontSize: 12.5, color: HandlesColors.critical),
            ),
          ),
        ],
      ],
    );
  }
}

class _CatalogServerSection extends StatefulWidget {
  const _CatalogServerSection();

  @override
  State<_CatalogServerSection> createState() => _CatalogServerSectionState();
}

class _CatalogServerSectionState extends State<_CatalogServerSection> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiToken;
  late final TextEditingController _autoSyncMinutes;
  bool _initialized = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _apiToken = TextEditingController();
    _autoSyncMinutes = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiToken.dispose();
    _autoSyncMinutes.dispose();
    super.dispose();
  }

  void _syncFrom(CatalogApiConfig config, HandlesSettings settings) {
    if (_initialized) return;
    _baseUrl.text = config.baseUrl;
    _apiToken.text = config.apiToken;
    _autoSyncMinutes.text = '${settings.autoSyncIntervalMinutes}';
    _initialized = true;
  }

  String _syncStatusText(AppState appState) {
    if (appState.isSyncing) return 'Syncing…';
    if (appState.syncError != null) return appState.syncError!;
    final lastSyncedAt = appState.lastSyncedAt;
    if (lastSyncedAt == null) return 'Not synced yet.';
    final hh = lastSyncedAt.toLocal().hour.toString().padLeft(2, '0');
    final mm = lastSyncedAt.toLocal().minute.toString().padLeft(2, '0');
    return 'Last synced $hh:$mm.';
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    _syncFrom(appState.catalogApiConfig, appState.settings);
    final statusIsError = appState.syncError != null && !appState.isSyncing;

    return _SectionCard(
      title: 'Catalog Server',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The catalog API running on your server (core/bin/api_server.dart) - the daemon and '
            'this app both read/write through it now, so there\'s one source of truth instead of '
            'each device keeping its own copy. Must be HTTPS if reachable from outside your own '
            'network - the token below is a bearer token, not encrypted in transit over plain HTTP.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Server URL',
            controller: _baseUrl,
            hint: 'https://handles.example.com',
          ),
          const SizedBox(height: 10),
          _LabeledField(label: 'API Token', controller: _apiToken, obscure: true),
          const SizedBox(height: 10),
          _LabeledField(
            label: 'Auto-Sync Every (minutes, 0 = off)',
            controller: _autoSyncMinutes,
            hint: '3',
          ),
          const SizedBox(height: 6),
          Text(
            'This is the actual speed of your duty-reminder notifications for Mercari/Poshmark/'
            'Vinted - the app polls the server on its own at this interval and notifies the moment '
            'a new conflict or sale shows up. Runs while the app is open on Windows; on Android '
            'only while it\'s in the foreground - the OS suspends timers once it\'s fully backgrounded.',
            style: HandlesText.body(fontSize: 11.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrimaryButton(
                label: 'Save',
                onPressed: () async {
                  await appState.saveCatalogApiConfig(CatalogApiConfig(
                    baseUrl: _baseUrl.text.trim(),
                    apiToken: _apiToken.text.trim(),
                  ));
                  final parsedMinutes = int.tryParse(_autoSyncMinutes.text.trim());
                  await appState.updateSettings(appState.settings.copyWith(
                    autoSyncIntervalMinutes: parsedMinutes ?? appState.settings.autoSyncIntervalMinutes,
                  ));
                  setState(() => _savedMessage = 'Saved.');
                },
              ),
              const SizedBox(width: 10),
              _PrimaryButton(
                label: 'Sync Now',
                onPressed: appState.catalogApiConfig.isComplete && !appState.isSyncing
                    ? () => appState.syncCatalog()
                    : null,
              ),
              if (_savedMessage != null) ...[
                const SizedBox(width: 12),
                Text(_savedMessage!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.good)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _syncStatusText(appState),
            style: HandlesText.body(
              fontSize: 12.5,
              color: statusIsError ? HandlesColors.critical : HandlesColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcingEngineSection extends StatefulWidget {
  const _SourcingEngineSection();

  @override
  State<_SourcingEngineSection> createState() => _SourcingEngineSectionState();
}

class _SourcingEngineSectionState extends State<_SourcingEngineSection> {
  late final TextEditingController _keepaApiKey;
  late final TextEditingController _desiredProfit;
  late final TextEditingController _destinationFeeRate;
  bool _initialized = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _keepaApiKey = TextEditingController();
    _desiredProfit = TextEditingController();
    _destinationFeeRate = TextEditingController();
  }

  @override
  void dispose() {
    _keepaApiKey.dispose();
    _desiredProfit.dispose();
    _destinationFeeRate.dispose();
    super.dispose();
  }

  void _syncFrom(KeepaConfig keepa, HandlesSettings settings) {
    if (_initialized) return;
    _keepaApiKey.text = keepa.apiKey;
    _desiredProfit.text = settings.defaultDesiredProfit.toStringAsFixed(2);
    _destinationFeeRate.text = (settings.defaultDestinationFeeRate * 100).toStringAsFixed(1);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    _syncFrom(appState.keepaConfig, appState.settings);

    return _SectionCard(
      title: 'Sourcing Engine',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Powers the automated sourcing/listing engine (bulk Amazon scanning + '
            'auto-listing isn\'t wired up yet - see docs/PROJECT_PLAN.md section 10). '
            'The Keepa key below isn\'t used anywhere yet either; it has a home ready '
            'for whenever that subscription is actually activated.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          _LabeledField(label: 'Keepa API Key', controller: _keepaApiKey, obscure: true),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Default Desired Profit (\$)',
                  controller: _desiredProfit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Default Destination Fee (%)',
                  controller: _destinationFeeRate,
                  hint: 'e.g. 13 for 13% - verify per category, not a fixed rate',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrimaryButton(
                label: 'Save',
                onPressed: () async {
                  await appState.saveKeepaConfig(KeepaConfig(apiKey: _keepaApiKey.text.trim()));
                  final profit = double.tryParse(_desiredProfit.text.trim());
                  final feePercent = double.tryParse(_destinationFeeRate.text.trim());
                  await appState.updateSettings(appState.settings.copyWith(
                    defaultDesiredProfit: profit,
                    defaultDestinationFeeRate: feePercent == null ? null : feePercent / 100,
                  ));
                  setState(() => _savedMessage = 'Saved.');
                },
              ),
              if (_savedMessage != null) ...[
                const SizedBox(width: 12),
                Text(_savedMessage!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.good)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DutyRemindersSection extends StatefulWidget {
  const _DutyRemindersSection();

  @override
  State<_DutyRemindersSection> createState() => _DutyRemindersSectionState();
}

class _DutyRemindersSectionState extends State<_DutyRemindersSection> {
  final _reminders = ReminderService();
  String? _status;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Duty Reminders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Native notifications for anything that needs a human - an unresolved conflict, '
            'a monitor-only platform that\'s fallen out of sync, a sourced item that just sold '
            'and needs fulfilling. Not yet wired to real events (that needs the app reading the '
            'live catalog - see project notes) - this button proves the notification pipeline '
            'itself actually works.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrimaryButton(
                label: 'Send Test Reminder',
                onPressed: () async {
                  await _reminders.notify(
                    title: 'Handles: test reminder',
                    body: 'If you can see this, duty reminders are working.',
                  );
                  setState(() => _status = 'Sent.');
                },
              ),
              if (_status != null) ...[
                const SizedBox(width: 12),
                Text(_status!, style: HandlesText.body(fontSize: 12.5, color: HandlesColors.good)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final active = HandlesPalette.resolve(appState.settings);

    return _SectionCard(
      title: 'Theme',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Built-in presets, or build your own from scratch - every instrument-panel dark, no '
            'daytime mode, by design. Applies everywhere immediately, no restart needed.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: active.bg, border: Border.all(color: HandlesColors.border)),
                child: Center(
                  child: Container(width: 18, height: 18, color: active.silverBright),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(active.displayName, style: HandlesText.body(fontSize: 14, weight: FontWeight.w600)),
              ),
              _PrimaryButton(
                label: 'Change Theme…',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriorityCategoriesSection extends StatelessWidget {
  const _PriorityCategoriesSection();

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final settings = appState.settings;
    final all = settings.allCategories.map((c) => c.name).toList();

    return _SectionCard(
      title: 'Priority Categories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prioritized categories are surfaced first in the catalog view. Order matters - '
            'move a category up to rank it higher.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < settings.priorityCategories.length; i++)
            _PriorityRow(
              name: settings.priorityCategories[i],
              index: i,
              count: settings.priorityCategories.length,
              onMoveUp: i == 0
                  ? null
                  : () {
                      final next = List<String>.from(settings.priorityCategories);
                      final item = next.removeAt(i);
                      next.insert(i - 1, item);
                      appState.updateSettings(settings.copyWith(priorityCategories: next));
                    },
              onMoveDown: i == settings.priorityCategories.length - 1
                  ? null
                  : () {
                      final next = List<String>.from(settings.priorityCategories);
                      final item = next.removeAt(i);
                      next.insert(i + 1, item);
                      appState.updateSettings(settings.copyWith(priorityCategories: next));
                    },
              onRemove: () {
                final next = List<String>.from(settings.priorityCategories)..remove(settings.priorityCategories[i]);
                appState.updateSettings(settings.copyWith(priorityCategories: next));
              },
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in all)
                if (!settings.priorityCategories.contains(name))
                  _AddChip(
                    label: name,
                    onTap: () => appState.updateSettings(
                      settings.copyWith(priorityCategories: [...settings.priorityCategories, name]),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.name,
    required this.index,
    required this.count,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final String name;
  final int index;
  final int count;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: HandlesText.data(fontSize: 13, color: HandlesColors.inkFaint),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: HandlesText.body(fontSize: 14))),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: 18, color: HandlesColors.inkMuted),
            onPressed: onMoveUp,
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: 18, color: HandlesColors.inkMuted),
            onPressed: onMoveDown,
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: HandlesColors.critical),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CustomCategoriesSection extends StatelessWidget {
  const _CustomCategoriesSection();

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final settings = appState.settings;

    return _SectionCard(
      title: 'Custom Categories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a category the recommender should learn, with keywords it looks for in a '
            "title/description (e.g. \"Home Goods\" → candle, mug, throw blanket).",
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          for (final category in settings.customCategories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name, style: HandlesText.body(fontSize: 14, weight: FontWeight.w600)),
                        Text(
                          category.keywords.join(', '),
                          style: HandlesText.data(fontSize: 12, color: HandlesColors.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: HandlesColors.critical),
                    onPressed: () {
                      final next = settings.customCategories.where((c) => c.name != category.name).toList();
                      appState.updateSettings(settings.copyWith(customCategories: next));
                    },
                  ),
                ],
              ),
            ),
          _PrimaryButton(
            label: '+ Add Category',
            onPressed: () => _showAddCategoryDialog(context, appState, settings),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog(
    BuildContext context,
    dynamic appState,
    HandlesSettings settings,
  ) async {
    final nameController = TextEditingController();
    final keywordsController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HandlesColors.surfaceRaised,
        title: Text('Add category', style: HandlesText.body(fontSize: 16, weight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(label: 'Name', controller: nameController),
            const SizedBox(height: 10),
            _LabeledField(
              label: 'Keywords (comma-separated)',
              controller: keywordsController,
              hint: 'candle, mug, throw blanket',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          _PrimaryButton(
            label: 'Add',
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final keywords = keywordsController.text
                  .split(',')
                  .map((k) => k.trim().toLowerCase())
                  .where((k) => k.isNotEmpty)
                  .toList();
              appState.updateSettings(settings.copyWith(
                customCategories: [
                  ...settings.customCategories.where((c) => c.name != name),
                  Category(name: name, keywords: keywords),
                ],
              ));
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _BrandRiskSection extends StatefulWidget {
  const _BrandRiskSection();

  @override
  State<_BrandRiskSection> createState() => _BrandRiskSectionState();
}

class _BrandRiskSectionState extends State<_BrandRiskSection> {
  bool _busy = false;

  Future<void> _remove(AppState appState, String brand) async {
    setState(() => _busy = true);
    try {
      await appState.removeBrandRiskEntry(brand);
    } on CatalogSyncException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAddDialog(BuildContext context, AppState appState) async {
    final brandController = TextEditingController();
    final reasonController = TextEditingController();
    var source = BrandRiskSource.ownHistory;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: HandlesColors.surfaceRaised,
          title: Text('Add brand risk entry', style: HandlesText.body(fontSize: 16, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(label: 'Brand', controller: brandController, hint: 'Nike'),
              const SizedBox(height: 10),
              _LabeledField(
                label: 'Reason',
                controller: reasonController,
                hint: 'Delisted for IP complaint on eBay, 2026-08-29',
              ),
              const SizedBox(height: 10),
              Text('SOURCE', style: HandlesText.eyebrow()),
              const SizedBox(height: 6),
              SegmentedButton<BrandRiskSource>(
                segments: const [
                  ButtonSegment(value: BrandRiskSource.ownHistory, label: Text('Happened to us')),
                  ButtonSegment(value: BrandRiskSource.curated, label: Text('Heard about it')),
                ],
                selected: {source},
                onSelectionChanged: (next) => setDialogState(() => source = next.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: HandlesText.data(fontSize: 13, color: HandlesColors.inkMuted)),
            ),
            _PrimaryButton(
              label: 'Add',
              onPressed: () {
                final brand = brandController.text.trim();
                final reason = reasonController.text.trim();
                if (brand.isEmpty || reason.isEmpty) return;
                appState.addBrandRiskEntry(BrandRiskEntry(brand: brand, reason: reason, source: source));
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final entries = appState.brandRiskEntries;

    return _SectionCard(
      title: 'Brand Risk List',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A blocklist the sourcing engine checks before publishing a listing - not a legal '
            'clearance check. A brand missing from this list means "not flagged," never "safe." '
            'See PROJECT_PLAN.md section 10 for the research behind why nothing does better than '
            'this today.',
            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text('No entries yet.', style: HandlesText.body(fontSize: 13, color: HandlesColors.inkFaint))
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(entry.brand, style: HandlesText.body(fontSize: 14, weight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                color: entry.source == BrandRiskSource.ownHistory
                                    ? HandlesColors.critical.withValues(alpha: 0.18)
                                    : HandlesColors.border,
                                child: Text(
                                  entry.source == BrandRiskSource.ownHistory ? 'OWN HISTORY' : 'CURATED',
                                  style: HandlesText.data(fontSize: 10, weight: FontWeight.w700, color: HandlesColors.inkMuted),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            entry.reason,
                            style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: HandlesColors.critical),
                      onPressed: _busy ? null : () => _remove(appState, entry.brand),
                    ),
                  ],
                ),
              ),
          _PrimaryButton(
            label: '+ Add Entry',
            onPressed: () => _showAddDialog(context, appState),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: HandlesText.eyebrow()),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: HandlesText.body(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: HandlesText.body(fontSize: 13, color: HandlesColors.inkFaint),
            border: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
            focusedBorder:
                OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.silverBright)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed, this.small = false});

  final String label;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: HandlesColors.silverBright,
        foregroundColor: HandlesColors.flairInk,
        disabledBackgroundColor: HandlesColors.border,
        shape: const RoundedRectangleBorder(),
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 8 : 12),
      ),
      child: Text(label, style: HandlesText.data(fontSize: small ? 12.5 : 14, weight: FontWeight.w700)),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: HandlesColors.borderStrong)),
        child: Text('+ $label', style: HandlesText.data(fontSize: 12.5, color: HandlesColors.inkMuted)),
      ),
    );
  }
}
