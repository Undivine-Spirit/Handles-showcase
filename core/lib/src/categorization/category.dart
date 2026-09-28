/// One category the catalog can group items under.
///
/// `keywords` power [CategoryRecommender] - lowercase words/phrases that, if
/// found in an item's title/description, count as evidence for this
/// category. Both built-in and user-added (`isCustom`) categories carry
/// keywords, so a user teaching the recommender a new custom category is
/// just adding keywords to it, not touching any algorithm.
class Category {
  const Category({required this.name, this.keywords = const [], this.isCustom = false});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        name: json['name'] as String,
        keywords: (json['keywords'] as List<dynamic>?)?.cast<String>() ?? const [],
        isCustom: json['is_custom'] as bool? ?? true,
      );

  final String name;
  final List<String> keywords;
  final bool isCustom;

  Category copyWith({String? name, List<String>? keywords}) => Category(
        name: name ?? this.name,
        keywords: keywords ?? this.keywords,
        isCustom: isCustom,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'keywords': keywords,
        'is_custom': isCustom,
      };
}

/// A starting set grounded in the sample catalog (`sampleCatalog()` in the
/// app) - not a claim about any real store's taxonomy. Meant to be edited
/// via settings once real inventory shows what categories/keywords
/// actually matter; nothing here is load-bearing for the algorithm itself.
const defaultCategories = [
  Category(
    name: 'Sneakers',
    keywords: [
      'nike', 'jordan', 'air force', 'new balance', 'salomon', 'adidas',
      'yeezy', 'sneaker', 'trainer', 'runner',
    ],
  ),
  Category(
    name: 'Denim',
    keywords: ["levi's", 'levis', 'jean', 'denim'],
  ),
  Category(
    name: 'Outerwear',
    keywords: ['jacket', 'carhartt', 'patagonia', 'coat', 'fleece', 'parka', 'windbreaker'],
  ),
  Category(
    name: 'Streetwear',
    keywords: ['supreme', 'box logo', 'hoodie', 'streetwear', 'graphic tee'],
  ),
  Category(
    name: 'Vintage',
    keywords: ['vintage', 'reverse weave', 'retro', "'9", "'8"], // e.g. '93, '80s
  ),
];
