import 'package:handles_app/data/catalog_sort.dart';
import 'package:handles_core/handles_core.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem _item(String sku, String? category) => CatalogItem(
      sku: sku,
      title: sku,
      price: 10,
      quantity: 1,
      category: category,
    );

void main() {
  test('returns items unchanged when there are no priority categories', () {
    final items = [_item('a', 'Denim'), _item('b', 'Sneakers')];

    expect(sortByPriorityCategories(items, []), items);
  });

  test('moves a prioritized category to the front without dropping anything', () {
    final denim = _item('denim-item', 'Denim');
    final sneakers = _item('sneaker-item', 'Sneakers');
    final vintage = _item('vintage-item', 'Vintage');
    final items = [sneakers, vintage, denim];

    final sorted = sortByPriorityCategories(items, ['Denim']);

    expect(sorted.map((i) => i.sku), ['denim-item', 'sneaker-item', 'vintage-item']);
  });

  test('respects the priority order across multiple prioritized categories', () {
    final denim = _item('denim-item', 'Denim');
    final sneakers = _item('sneaker-item', 'Sneakers');
    final vintage = _item('vintage-item', 'Vintage');
    final items = [denim, sneakers, vintage];

    final sorted = sortByPriorityCategories(items, ['Vintage', 'Sneakers']);

    expect(sorted.map((i) => i.sku), ['vintage-item', 'sneaker-item', 'denim-item']);
  });

  test('an item with no category at all sorts after every prioritized item', () {
    final uncategorized = _item('no-category', null);
    final denim = _item('denim-item', 'Denim');

    final sorted = sortByPriorityCategories([uncategorized, denim], ['Denim']);

    expect(sorted.map((i) => i.sku), ['denim-item', 'no-category']);
  });
}
