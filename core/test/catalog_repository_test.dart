import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogRepository', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('handles-catalog-repo-test-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns an empty list for a directory that does not exist yet', () async {
      final repo = CatalogRepository(Directory('${tempDir.path}/does-not-exist'));

      expect(await repo.loadAll(), isEmpty);
    });

    test('loads every <sku>.json file and skips the registry files', () async {
      await File('${tempDir.path}/schema.json').writeAsString('{}');
      await File('${tempDir.path}/stores.json').writeAsString('{}');
      await File('${tempDir.path}/example-item.json').writeAsString('{}');
      final repo = CatalogRepository(tempDir);
      final item = CatalogItem(sku: 'HND-0001', title: 'Test Item', price: 10, quantity: 1);
      await repo.save(item);

      final loaded = await repo.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.single.sku, 'HND-0001');
    });

    test('save then loadAll round-trips a full item, stores map included', () async {
      final repo = CatalogRepository(tempDir);
      final item = CatalogItem(
        sku: 'HND-0142',
        title: "Nike Air Force 1 '07",
        price: 109,
        quantity: 6,
        category: 'Sneakers',
        stores: {
          'ebay_store_a': StoreListingState(
            platform: 'ebay',
            externalListingId: 'l-1',
            syncStatus: SyncStatus.confirmed,
          ),
        },
      );

      await repo.save(item);
      final loaded = (await repo.loadAll()).single;

      expect(loaded.title, item.title);
      expect(loaded.category, 'Sneakers');
      expect(loaded.stores['ebay_store_a']?.externalListingId, 'l-1');
    });

    test('saving an updated item overwrites the same file rather than duplicating it', () async {
      final repo = CatalogRepository(tempDir);
      await repo.save(CatalogItem(sku: 'HND-0001', title: 'v1', price: 10, quantity: 5));
      await repo.save(CatalogItem(sku: 'HND-0001', title: 'v1', price: 10, quantity: 0));

      final loaded = await repo.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.single.quantity, 0);
    });
  });
}
