import 'dart:io';

import '../brand_risk/brand_risk_checker.dart';
import '../brand_risk/brand_risk_entry.dart';
import '../brand_risk/brand_risk_list.dart';
import '../catalog_item.dart';
import '../catalog_repository.dart';
import '../event_log.dart';
import '../git_sync.dart';

/// The actual data behind the catalog API - one place that knows how to
/// read/write [catalogDir], shared by the HTTP layer (`api_server.dart`)
/// so routing code stays thin and this stays independently testable
/// without spinning up a real server.
///
/// [gitSync], when given, commits and pushes after every write - the
/// audit trail from `docs/PROJECT_PLAN.md` section 2 still applies, it's
/// just this process doing it now instead of every device that touches
/// the catalog. A push failure is logged, not thrown back at the caller:
/// the write already landed on disk (what the API promises), and a
/// transient GitHub outage is this server's problem to retry, not
/// something that should turn a successful save into a failed API call.
class CatalogDataStore {
  CatalogDataStore(this.catalogDir, {this.gitSync});

  final Directory catalogDir;
  final GitSync? gitSync;

  CatalogRepository get _repository => CatalogRepository(catalogDir);
  EventLogStore get _eventLog => EventLogStore(File('${catalogDir.path}/.events.jsonl'));
  BrandRiskList get _brandRiskList => BrandRiskList(File('${catalogDir.path}/brand_risk_list.json'));

  Future<List<CatalogItem>> loadItems() => _repository.loadAll();

  Future<CatalogItem> saveItem(CatalogItem item) async {
    await _repository.save(item);
    await _commitAndPush('${item.sku}: saved via API');
    return item;
  }

  Future<List<HandlesEvent>> recentEvents({int limit = 50}) => _eventLog.readRecent(limit: limit);

  /// Appends a client-authored event (an app action, an app-side crash) to
  /// the same log the daemon's own reconciliation events go into - one
  /// audit trail, not a separate one per source. No git commit here on
  /// purpose: a commit per action/crash would be far noisier than the
  /// catalog-change commits this store already does, and the log file
  /// itself (readable via GET /catalog/events) is the point, not a git
  /// history of it.
  Future<void> recordEvent(HandlesEvent event) => _eventLog.append(event);

  Future<List<BrandRiskEntry>> loadBrandRisk() => _brandRiskList.load();

  Future<BrandRiskEntry> addBrandRiskEntry(BrandRiskEntry entry) async {
    await _brandRiskList.add(entry);
    await _commitAndPush('Add ${entry.brand} to brand risk list via API');
    return entry;
  }

  Future<void> removeBrandRiskEntry(String brand) async {
    await _brandRiskList.removeByBrand(brand);
    await _commitAndPush('Remove $brand from brand risk list via API');
  }

  /// A read-through check, not a stored verdict - `BrandRiskChecker`
  /// itself is stateless and cheap to build fresh from whatever's
  /// currently on disk.
  Future<BrandRiskVerdict> checkBrandRisk(String brand) async {
    final entries = await loadBrandRisk();
    return BrandRiskChecker(entries).check(brand);
  }

  Future<void> _commitAndPush(String message) async {
    final sync = gitSync;
    if (sync == null) return;
    try {
      await sync.commitAndPush(message);
    } on GitSyncException catch (e) {
      // ignore: avoid_print
      print('[CatalogDataStore] commit/push failed (write is still on disk): $e');
    }
  }
}
