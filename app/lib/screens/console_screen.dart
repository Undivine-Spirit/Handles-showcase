import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';

import '../data/catalog_sort.dart';
import '../data/catalog_stats.dart';
import '../data/known_accounts.dart';
import '../services/catalog_api_client.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';
import '../widgets/catalog_table.dart';
import '../widgets/masthead.dart';
import '../widgets/side_rail.dart';
import '../widgets/stat_tile.dart';
import 'add_item_screen.dart';
import 'settings_screen.dart';

/// The main dashboard - direct translation of the Handles Console visual
/// direction artifact into real, running widgets. Reads `AppState.items`/
/// `.events`, which is the real repo-backed catalog once a catalog
/// repository is configured in Settings, or `sampleCatalog()` as a
/// placeholder until then - see `AppState.init()`.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  String _activeTab = 'Catalog';

  /// `null` means "All stores" - an account key otherwise. Kept across a
  /// tab switch on purpose: "show me eBay items" then "...now just the
  /// shared ones" is a real, useful combination, not two unrelated asks.
  String? _storeFilter;

  Future<void> _openAddItem() async {
    final newItem = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(builder: (_) => const AddItemScreen()),
    );
    if (newItem == null || !mounted) return;

    final appState = AppStateScope.of(context);
    try {
      await appState.addItem(newItem);
    } on CatalogSyncException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openEditItem(CatalogItem item) async {
    final edited = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(builder: (_) => AddItemScreen(existingItem: item)),
    );
    if (edited == null || !mounted) return;

    final appState = AppStateScope.of(context);
    try {
      await appState.updateItem(edited);
    } on CatalogSyncException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _saveListingUrl(String sku, String accountKey, String url) async {
    final appState = AppStateScope.of(context);
    final index = appState.items.indexWhere((i) => i.sku == sku);
    if (index == -1) return;

    final item = appState.items[index];
    final existing = item.stores[accountKey];
    if (existing == null) return;

    final updated = item.copyWith(stores: {
      ...item.stores,
      accountKey: existing.copyWith(listingUrl: url),
    });

    try {
      await appState.updateItem(updated);
    } on CatalogSyncException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final settings = appState.settings;
    var items = sortByPriorityCategories(appState.items, settings.priorityCategories);

    // Stats always describe the whole catalog, not whatever tab/filter
    // happens to be selected - a filtered "Needs Attention" count reading
    // 0 just because Shared Items is active would be actively misleading.
    final stats = computeCatalogStats(items);

    if (_activeTab == 'Shared Items') {
      items = items.where((i) => i.stores.length > 1).toList();
    }
    if (_storeFilter != null) {
      items = items.where((i) => i.stores.containsKey(_storeFilter)).toList();
    }

    return Scaffold(
      backgroundColor: HandlesColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 860;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Masthead(
                    activeTab: _activeTab,
                    onTabSelected: (tab) => setState(() => _activeTab = tab),
                    onSettingsTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (_SyncStatusBanner.hasSomethingToSay(appState)) ...[
                    _SyncStatusBanner(appState: appState),
                    const SizedBox(height: 16),
                  ],
                  _StatRow(stats: stats, narrow: narrow),
                  const SizedBox(height: 16),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CatalogPanel(
                          title: _activeTab,
                          items: items,
                          showAddButton: _activeTab == 'Catalog',
                          storeFilter: _storeFilter,
                          onStoreFilterChanged: (key) => setState(() => _storeFilter = key),
                          onAddItem: _openAddItem,
                          onEditItem: _openEditItem,
                          onSaveListingUrl: _saveListingUrl,
                        ),
                        const SizedBox(height: 16),
                        ActivityLogPanel(events: appState.events),
                        const SizedBox(height: 16),
                        const HardwarePanel(),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _CatalogPanel(
                            title: _activeTab,
                            items: items,
                            showAddButton: _activeTab == 'Catalog',
                            storeFilter: _storeFilter,
                            onStoreFilterChanged: (key) => setState(() => _storeFilter = key),
                            onAddItem: _openAddItem,
                            onEditItem: _openEditItem,
                            onSaveListingUrl: _saveListingUrl,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              ActivityLogPanel(events: appState.events),
                              const SizedBox(height: 16),
                              const HardwarePanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  const _Footer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The only visible sign, outside Settings, of whether the catalog above
/// is the real synced thing or still `sampleCatalog()` - the "feel good,
/// not just look good" principle means this can't stay quiet about it.
class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({required this.appState});

  final AppState appState;

  static bool hasSomethingToSay(AppState appState) =>
      !appState.catalogApiConfig.isComplete || appState.isSyncing || appState.syncError != null;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    final bool showRetry;

    if (!appState.catalogApiConfig.isComplete) {
      text = 'Showing sample data — connect a catalog server in Settings to sync the real catalog.';
      color = HandlesColors.inkFaint;
      showRetry = false;
    } else if (appState.isSyncing) {
      text = 'Syncing catalog…';
      color = HandlesColors.inkMuted;
      showRetry = false;
    } else {
      text = 'Sync failed: ${appState.syncError}';
      color = HandlesColors.critical;
      showRetry = true;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HandlesColors.surface,
        border: Border.all(color: HandlesColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text, style: HandlesText.body(fontSize: 12.5, color: color))),
          if (showRetry)
            TextButton(
              onPressed: appState.syncCatalog,
              child: Text(
                'RETRY',
                style: HandlesText.data(fontSize: 12, weight: FontWeight.w700, color: HandlesColors.silverBright),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats, required this.narrow});

  final CatalogStats stats;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      StatTile(
        label: 'Total SKUs',
        figure: '${stats.totalSkus}',
        subtitle: 'across connected stores',
      ),
      StatTile(
        label: 'Active Listings',
        figure: '${stats.activeListings}',
        subtitle: 'automated, excludes manual-only',
      ),
      StatTile(
        label: 'Confirmed In Sync',
        figure: '${stats.confirmedToday}',
        subtitle: 'auto-reconciled',
        sparkline: const MiniSparkline(values: [0.35, 0.52, 0.4, 0.68, 0.58, 0.8, 1.0]),
      ),
      StatTile(
        label: 'Needs Attention',
        figure: '${stats.needsAttention}',
        subtitle: 'conflicts + errors',
        attention: stats.needsAttention > 0,
      ),
    ];

    return GridView.count(
      crossAxisCount: narrow ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: narrow ? 1.5 : 1.7,
      children: tiles,
    );
  }
}

class _CatalogPanel extends StatelessWidget {
  const _CatalogPanel({
    required this.title,
    required this.items,
    required this.showAddButton,
    required this.storeFilter,
    required this.onStoreFilterChanged,
    required this.onAddItem,
    this.onEditItem,
    required this.onSaveListingUrl,
  });

  final String title;
  final List<CatalogItem> items;
  final bool showAddButton;
  final String? storeFilter;
  final void Function(String? accountKey) onStoreFilterChanged;
  final VoidCallback onAddItem;
  final void Function(CatalogItem item)? onEditItem;
  final void Function(String sku, String accountKey, String url) onSaveListingUrl;

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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: HandlesColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: HandlesText.body(fontSize: 17, weight: FontWeight.w700)),
                    if (showAddButton)
                      TextButton(
                        onPressed: onAddItem,
                        child: Text(
                          '+ ADD ITEM',
                          style: HandlesText.data(
                            fontSize: 12.5,
                            weight: FontWeight.w700,
                            color: HandlesColors.silverBright,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _StoreFilterRow(selected: storeFilter, onChanged: onStoreFilterChanged),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                title == 'Shared Items'
                    ? 'Nothing is listed on more than one store right now.'
                    : 'Nothing matches this filter.',
                style: HandlesText.body(fontSize: 13, color: HandlesColors.inkFaint),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 640,
                child: CatalogTable(
                  items: items,
                  onSaveListingUrl: onSaveListingUrl,
                  onEditItem: onEditItem,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Easy to navigate between stores" - a chip per known account (skipping
/// [AutomationLevel.deferred] ones like Amazon, which was never a listing
/// destination) that filters the catalog table above to just that store,
/// on either tab. "All" clears it.
class _StoreFilterRow extends StatelessWidget {
  const _StoreFilterRow({required this.selected, required this.onChanged});

  final String? selected;
  final void Function(String? accountKey) onChanged;

  @override
  Widget build(BuildContext context) {
    final accounts = knownAccounts().where((a) => a.automation != AutomationLevel.deferred);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(label: 'All', active: selected == null, onTap: () => onChanged(null)),
        for (final account in accounts)
          _FilterChip(
            label: storeAccountLabel(account.accountKey),
            active: selected == account.accountKey,
            onTap: () => onChanged(account.accountKey),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? HandlesColors.silverBright : Colors.transparent,
          border: Border.all(color: active ? HandlesColors.silverBright : HandlesColors.border),
        ),
        child: Text(
          label,
          style: HandlesText.data(
            fontSize: 11.5,
            weight: FontWeight.w600,
            color: active ? HandlesColors.flairInk : HandlesColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: HandlesColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        children: [
          Text('WHY THIS EXISTS', style: HandlesText.eyebrow()),
          Text(
            'Reconciliation reclaims the hours that used to go into checking every listing by hand.',
            style: HandlesText.body(fontSize: 13, color: HandlesColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
