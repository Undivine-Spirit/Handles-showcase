import 'package:handles_core/handles_core.dart';

/// Priority categories first (in the order settings define), everything
/// else after in whatever order it already was - PROJECT_PLAN.md's
/// "prioritize looking at certain categories" applied as a stable sort,
/// not a filter (nothing gets hidden, just reordered). An item whose
/// category isn't in the priority list at all sorts after every item that
/// is.
List<CatalogItem> sortByPriorityCategories(
  List<CatalogItem> items,
  List<String> priorityCategories,
) {
  if (priorityCategories.isEmpty) return items;

  int rank(CatalogItem item) {
    final index = priorityCategories.indexOf(item.category ?? '');
    return index == -1 ? priorityCategories.length : index;
  }

  final copy = List<CatalogItem>.from(items);
  copy.sort((a, b) => rank(a).compareTo(rank(b)));
  return copy;
}
