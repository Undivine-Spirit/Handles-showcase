import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogDataStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('handles-catalog-data-store-test-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('loadItems is empty for a fresh catalog dir', () async {
      final store = CatalogDataStore(tempDir);
      expect(await store.loadItems(), isEmpty);
    });

    test('saveItem then loadItems round-trips, no git required', () async {
      final store = CatalogDataStore(tempDir); // gitSync: null
      final item = CatalogItem(sku: 'HND-0001', title: 'Test Item', price: 10, quantity: 3);

      final saved = await store.saveItem(item);

      expect(saved.sku, 'HND-0001');
      final loaded = await store.loadItems();
      expect(loaded, hasLength(1));
      expect(loaded.single.title, 'Test Item');
    });

    test('saving an item with the same sku overwrites rather than duplicating', () async {
      final store = CatalogDataStore(tempDir);
      await store.saveItem(CatalogItem(sku: 'HND-0001', title: 'v1', price: 10, quantity: 5));
      await store.saveItem(CatalogItem(sku: 'HND-0001', title: 'v2', price: 10, quantity: 0));

      final loaded = await store.loadItems();
      expect(loaded, hasLength(1));
      expect(loaded.single.title, 'v2');
      expect(loaded.single.quantity, 0);
    });

    test('recentEvents reads from the same catalog dir\'s .events.jsonl', () async {
      final store = CatalogDataStore(tempDir);
      final eventLog = EventLogStore(File('${tempDir.path}/.events.jsonl'));
      await eventLog.append(HandlesEvent(
        timestamp: DateTime.utc(2026, 8, 29),
        severity: EventSeverity.actionNeeded,
        source: 'reconciliation',
        message: 'test event',
      ));

      final events = await store.recentEvents();

      expect(events, hasLength(1));
      expect(events.single.message, 'test event');
    });

    test('brand risk: add, load, and check round-trip', () async {
      final store = CatalogDataStore(tempDir);

      await store.addBrandRiskEntry(
        BrandRiskEntry(brand: 'Nike', reason: 'Known VeRO enforcer', source: BrandRiskSource.curated),
      );

      final entries = await store.loadBrandRisk();
      expect(entries, hasLength(1));

      final flagged = await store.checkBrandRisk('nike'); // case-insensitive
      expect(flagged.isFlagged, isTrue);

      final clean = await store.checkBrandRisk('Some Generic Brand');
      expect(clean.isFlagged, isFalse);
    });

    test('brand risk: removeBrandRiskEntry removes only the matching brand', () async {
      final store = CatalogDataStore(tempDir);
      await store.addBrandRiskEntry(
        BrandRiskEntry(brand: 'Nike', reason: 'r1', source: BrandRiskSource.curated),
      );
      await store.addBrandRiskEntry(
        BrandRiskEntry(brand: 'Disney', reason: 'r2', source: BrandRiskSource.curated),
      );

      await store.removeBrandRiskEntry('Nike');

      final entries = await store.loadBrandRisk();
      expect(entries, hasLength(1));
      expect(entries.single.brand, 'Disney');
    });

    test('a git push failure is swallowed, not thrown - the write already landed on disk', () async {
      // A GitSync pointed at a directory that was never actually a git
      // repo - every git command it runs will fail.
      final store = CatalogDataStore(tempDir, gitSync: GitSync(tempDir.path));

      // Should not throw despite the doomed git commands underneath.
      final saved = await store.saveItem(CatalogItem(sku: 'HND-0001', title: 'x', price: 1, quantity: 1));

      expect(saved.sku, 'HND-0001');
      final loaded = await store.loadItems();
      expect(loaded, hasLength(1), reason: 'the file write itself still succeeded');
    });
  });
}
