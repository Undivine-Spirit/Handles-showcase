import 'category.dart';

/// One candidate suggestion - deliberately exposes *which* keywords matched
/// rather than a single opaque confidence score, so a UI can show the user
/// why a category was suggested ("matched: nike, air force") instead of
/// asking them to trust a number.
class CategoryRecommendation {
  const CategoryRecommendation({required this.category, required this.matchedKeywords});

  final String category;
  final List<String> matchedKeywords;

  /// Raw match count - more matches is a stronger signal, but this is not
  /// a normalized probability and shouldn't be presented as one.
  int get score => matchedKeywords.length;
}

/// v1 category suggestion: keyword matching against each known [Category],
/// not a trained model. Deliberately simple and inspectable - a business
/// can see and edit exactly why a suggestion fires by editing a category's
/// keyword list in settings, rather than needing to retrain anything.
class CategoryRecommender {
  CategoryRecommender(this.categories);

  final List<Category> categories;

  /// Ranked highest-score first. Empty if nothing matched - callers should
  /// treat that as "let the user pick manually," not force a guess.
  List<CategoryRecommendation> recommend(String title, {String? description}) {
    final haystack = '$title ${description ?? ''}'.toLowerCase();

    final results = <CategoryRecommendation>[];
    for (final category in categories) {
      final matched = [
        for (final keyword in category.keywords)
          if (haystack.contains(keyword.toLowerCase())) keyword,
      ];
      if (matched.isNotEmpty) {
        results.add(CategoryRecommendation(category: category.name, matchedKeywords: matched));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}
