import 'package:handles_core/handles_core.dart';

class CatalogStats {
  const CatalogStats({
    required this.totalSkus,
    required this.activeListings,
    required this.confirmedToday,
    required this.needsAttention,
  });

  final int totalSkus;
  final int activeListings;
  final int confirmedToday;
  final int needsAttention;
}

/// Derived straight from whatever catalog is passed in - sample data today,
/// the real repo-backed catalog once the GitHub state layer exists - rather
/// than hardcoded figures that could drift out of sync with what the
/// catalog table actually shows below them.
CatalogStats computeCatalogStats(List<CatalogItem> items) {
  var active = 0;
  var confirmed = 0;
  var attention = 0;

  for (final item in items) {
    for (final state in item.stores.values) {
      if (state.syncStatus == SyncStatus.manualOnly) continue;
      active++;
      switch (state.syncStatus) {
        case SyncStatus.confirmed:
          confirmed++;
        case SyncStatus.conflict:
        case SyncStatus.error:
          attention++;
        case SyncStatus.pending:
        case SyncStatus.manualOnly:
          break;
      }
    }
  }

  return CatalogStats(
    totalSkus: items.length,
    activeListings: active,
    confirmedToday: confirmed,
    needsAttention: attention,
  );
}
