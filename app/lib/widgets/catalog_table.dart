import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';
import 'item_swatch.dart';
import 'status_pill.dart';

/// Short, human-facing name for a store account key - stand-in for reading
/// `catalog/stores.json`'s `display_name` field once the app can load it at
/// runtime. Falls back to a title-cased guess for anything unrecognized
/// rather than showing a raw account key to the user.
String storeAccountLabel(String accountKey) => switch (accountKey) {
      'ebay_store_a' => 'eBay A',
      'ebay_store_b' => 'eBay B',
      'walmart' => 'Walmart',
      'poshmark' => 'Poshmark',
      'vinted' => 'Vinted',
      'mercari' => 'Mercari',
      'amazon' => 'Amazon',
      _ => accountKey,
    };

/// These three have no write API at all (confirmed - see
/// `docs/API_RESEARCH.md`), not a temporary gap - a human always
/// delists/updates them by hand. [_StorePill] leans into that instead of
/// pretending otherwise: a saved listing URL makes the manual trip to
/// that platform one tap away instead of a search.
const monitorOnlyPlatforms = {'poshmark', 'vinted', 'mercari'};

(PillTone, String) _pillFor(CatalogItem item, StoreListingState state) {
  if (state.syncStatus == SyncStatus.manualOnly) {
    return (PillTone.approval, 'Manual');
  }
  if (state.syncStatus == SyncStatus.conflict) {
    return (PillTone.conflict, 'Conflict');
  }
  if (state.syncStatus == SyncStatus.error) {
    return (PillTone.conflict, 'Error');
  }
  if (state.syncStatus == SyncStatus.pending) {
    return (PillTone.pending, 'Publishing');
  }
  if (item.isSoldOut) {
    return (PillTone.delisted, 'Auto-Delisted');
  }
  return (PillTone.confirmed, 'Confirmed');
}

class CatalogTable extends StatelessWidget {
  const CatalogTable({super.key, required this.items, required this.onSaveListingUrl, this.onEditItem});

  final List<CatalogItem> items;

  /// Called when a user pastes in (or replaces) a monitor-only platform's
  /// listing URL for one item.
  final void Function(String sku, String accountKey, String url) onSaveListingUrl;

  /// Tapping an item's title/swatch opens it for manual editing (price,
  /// quantity, etc.) - `null` disables that (e.g. a read-only context).
  final void Function(CatalogItem item)? onEditItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderRow(),
        for (final item in items)
          _ItemRow(item: item, onSaveListingUrl: onSaveListingUrl, onEditItem: onEditItem),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = HandlesText.eyebrow();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: HandlesColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('ITEM', style: style)),
          SizedBox(width: 70, child: Text('PRICE', style: style)),
          SizedBox(width: 50, child: Text('QTY', style: style)),
          Expanded(flex: 5, child: Text('STORES', style: style)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onSaveListingUrl, this.onEditItem});

  final CatalogItem item;
  final void Function(String sku, String accountKey, String url) onSaveListingUrl;
  final void Function(CatalogItem item)? onEditItem;

  @override
  Widget build(BuildContext context) {
    final zeroed = item.isSoldOut;

    return Opacity(
      opacity: zeroed ? 0.62 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: HandlesColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: InkWell(
                onTap: onEditItem == null ? null : () => onEditItem!(item),
                child: Row(
                  children: [
                    ItemSwatch(title: item.title),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            style: HandlesText.body(fontSize: 13.5, weight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            item.sku,
                            style: HandlesText.data(
                              fontSize: 11.5,
                              weight: FontWeight.w500,
                              color: HandlesColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                '\$${item.price.toStringAsFixed(2)}',
                style: HandlesText.data(fontSize: 14.5),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${item.quantity}',
                style: HandlesText.data(
                  fontSize: 14.5,
                  color: item.quantity == 0 ? HandlesColors.critical : HandlesColors.ink,
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in item.stores.entries)
                    _StorePill(
                      item: item,
                      accountKey: entry.key,
                      state: entry.value,
                      onSaveListingUrl: onSaveListingUrl,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorePill extends StatelessWidget {
  const _StorePill({
    required this.item,
    required this.accountKey,
    required this.state,
    required this.onSaveListingUrl,
  });

  final CatalogItem item;
  final String accountKey;
  final StoreListingState state;
  final void Function(String sku, String accountKey, String url) onSaveListingUrl;

  bool get _isMonitorOnly => monitorOnlyPlatforms.contains(state.platform);
  String? get _savedUrl => state.listingUrl;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = _pillFor(item, state);
    final pill = StatusPill(label: '${storeAccountLabel(accountKey)}: $label', tone: tone);

    if (!_isMonitorOnly) return pill;

    // Monitor-only platforms have no write API at all (confirmed, not a
    // gap) - the tap target here IS the feature: a saved listing opens
    // directly, an unsaved one prompts for the URL once so every future
    // tap is instant. "What's interactive should look interactive" - the
    // link icon says so without needing a caption.
    return InkWell(
      onTap: () => _savedUrl != null ? _openListing(context) : _promptForUrl(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill,
          const SizedBox(width: 3),
          Icon(
            _savedUrl != null ? Icons.open_in_new : Icons.add_link,
            size: 13,
            color: HandlesColors.inkFaint,
          ),
        ],
      ),
    );
  }

  Future<void> _openListing(BuildContext context) async {
    final uri = Uri.tryParse(_savedUrl!);
    if (uri == null || !await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')),
        );
      }
    }
  }

  Future<void> _promptForUrl(BuildContext context) async {
    final controller = TextEditingController(text: _savedUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HandlesColors.surfaceRaised,
        title: Text(
          '${storeAccountLabel(accountKey)} listing URL',
          style: HandlesText.body(fontSize: 16, weight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No write API exists for ${storeAccountLabel(accountKey)} - paste the listing\'s '
              'URL once so delisting it later is a tap instead of a search.',
              style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: HandlesText.body(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'https://…',
                border: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HandlesColors.silverBright,
              foregroundColor: HandlesColors.flairInk,
              shape: const RoundedRectangleBorder(),
            ),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      onSaveListingUrl(item.sku, accountKey, result);
    }
  }
}
