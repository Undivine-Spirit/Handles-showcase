import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  final recommender = CategoryRecommender(defaultCategories);

  test('recommends Sneakers for a shoe title, showing which keywords matched', () {
    final results = recommender.recommend("Nike Air Force 1 '07 — Triple White");

    expect(results, isNotEmpty);
    expect(results.first.category, 'Sneakers');
    expect(results.first.matchedKeywords, containsAll(['nike', 'air force']));
  });

  test('ranks the category with more keyword matches first', () {
    // Matches both Vintage ("vintage") and Streetwear ("hoodie") - Vintage
    // also matches "reverse weave", so it should out-rank Streetwear.
    final results = recommender.recommend('Vintage Champion Reverse Weave Hoodie');

    expect(results.map((r) => r.category).take(2), ['Vintage', 'Streetwear']);
  });

  test('returns an empty list rather than guessing when nothing matches', () {
    final results = recommender.recommend('Mystery Item With No Keywords At All');

    expect(results, isEmpty);
  });

  test('a user-added custom category with its own keywords gets recommended too', () {
    const custom = Category(name: 'Home Goods', keywords: ['candle', 'mug', 'throw blanket']);
    final withCustom = CategoryRecommender([...defaultCategories, custom]);

    final results = withCustom.recommend('Hand-Poured Soy Candle');

    expect(results.single.category, 'Home Goods');
  });
}
