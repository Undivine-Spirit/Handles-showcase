import 'dart:convert';
import 'dart:io';

import 'catalog_item.dart';

/// Reads and writes the catalog as one JSON file per SKU under a
/// directory - the "GitHub state layer" from PROJECT_PLAN.md section 3
/// (component 3), not built until now. This is what makes the repo the
/// actual source of truth rather than a design intention: the daemon (or
/// anything else) reads real state from here, not from sample data.
///
/// Deliberately dart:io-based, same as `FileCredentialStore` - `core/`
/// stays plain Dart, but plain Dart still has a real filesystem.
class CatalogRepository {
  CatalogRepository(this.catalogDir);

  final Directory catalogDir;

  static const _reservedFiles = {
    'schema.json',
    'stores.json',
    'example-item.json',
    'brand_risk_list.json',
  };

  /// Every `<sku>.json` file in [catalogDir] - the registry/schema files
  /// that also live there are explicitly excluded, not treated as items.
  Future<List<CatalogItem>> loadAll() async {
    if (!await catalogDir.exists()) return [];

    final items = <CatalogItem>[];
    await for (final entity in catalogDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final filename = entity.uri.pathSegments.last;
      if (_reservedFiles.contains(filename)) continue;

      final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
      items.add(CatalogItem.fromJson(json));
    }
    return items;
  }

  Future<void> save(CatalogItem item) async {
    final file = File('${catalogDir.path}/${item.sku}.json');
    await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(item.toJson())}\n');
  }
}
