import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';

import '../state/app_state_scope.dart';
import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';

/// Returns the completed [CatalogItem] via `Navigator.pop`, or null if
/// cancelled. Doubles as the edit screen when [existingItem] is given -
/// manual quantity/price adjustment (source-of-truth quantity should
/// normally come from whichever store actually sold the item, via
/// reconciliation engine v2's own read of that store, but a human
/// overriding it directly - a physical recount, correcting a mistake -
/// stays a first-class path, not something only reconciliation can touch).
/// Same caller contract either way: the pushed result is what gets saved,
/// this screen never persists anything itself.
class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key, this.existingItem});

  final CatalogItem? existingItem;

  bool get isEditing => existingItem != null;

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _skuController = TextEditingController();

  String? _selectedCategory;
  List<CategoryRecommendation> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingItem;
    if (existing != null) {
      _skuController.text = existing.sku;
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _priceController.text = existing.price.toString();
      _quantityController.text = existing.quantity.toString();
      _selectedCategory = existing.category;
    }

    _titleController.addListener(_recompute);
    _descriptionController.addListener(_recompute);
    // These three don't feed the recommender, but they DO feed
    // _canSubmit - without a listener here, filling them in wouldn't
    // trigger a rebuild, and the submit button would stay stuck on
    // whatever _canSubmit evaluated to at the last title/description
    // keystroke.
    _skuController.addListener(_refresh);
    _priceController.addListener(_refresh);
    _quantityController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  void _recompute() {
    final settings = AppStateScope.of(context).settings;
    final recommender = CategoryRecommender(settings.allCategories);
    final suggestions = recommender.recommend(
      _titleController.text,
      description: _descriptionController.text,
    );
    setState(() => _suggestions = suggestions);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppStateScope.of(context).settings;

    return Scaffold(
      backgroundColor: HandlesColors.bg,
      appBar: AppBar(
        backgroundColor: HandlesColors.bg,
        elevation: 0,
        title: Text(widget.isEditing ? 'Edit Item' : 'Add Item', style: HandlesText.stencil(fontSize: 28)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('SKU', _skuController, hint: 'HND-0000', enabled: !widget.isEditing),
              const SizedBox(height: 14),
              _field('Title', _titleController),
              const SizedBox(height: 14),
              _field('Description', _descriptionController, maxLines: 3),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _field('Price', _priceController, keyboardType: TextInputType.number)),
                  const SizedBox(width: 14),
                  Expanded(child: _field('Quantity', _quantityController, keyboardType: TextInputType.number)),
                ],
              ),
              if (widget.isEditing) ...[
                const SizedBox(height: 8),
                Text(
                  'Quantity here is a manual override - reconciliation still pulls the real number '
                  'from whichever store actually sells the item and cascades it back on the next '
                  'pass. Use this for a physical recount or correcting a mistake, not routine sales.',
                  style: HandlesText.body(fontSize: 11.5, color: HandlesColors.inkFaint),
                ),
              ],
              const SizedBox(height: 18),
              Text('CATEGORY', style: HandlesText.eyebrow()),
              const SizedBox(height: 8),
              if (_suggestions.isNotEmpty) ...[
                Text(
                  'Suggested from the title/description:',
                  style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in _suggestions)
                      _SuggestionChip(
                        suggestion: suggestion,
                        selected: _selectedCategory == suggestion.category,
                        onTap: () => setState(() => _selectedCategory = suggestion.category),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in settings.allCategories)
                    if (!_suggestions.any((s) => s.category == category.name))
                      _PlainCategoryChip(
                        label: category.name,
                        selected: _selectedCategory == category.name,
                        onTap: () => setState(() => _selectedCategory = category.name),
                      ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HandlesColors.silverBright,
                  foregroundColor: HandlesColors.flairInk,
                  disabledBackgroundColor: HandlesColors.border,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  widget.isEditing ? 'SAVE CHANGES' : 'ADD ITEM',
                  style: HandlesText.data(fontSize: 14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSubmit =>
      _skuController.text.trim().isNotEmpty &&
      _titleController.text.trim().isNotEmpty &&
      double.tryParse(_priceController.text.trim()) != null &&
      int.tryParse(_quantityController.text.trim()) != null;

  void _submit() {
    final description =
        _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
    final price = double.parse(_priceController.text.trim());
    final quantity = int.parse(_quantityController.text.trim());

    final existing = widget.existingItem;
    final item = existing != null
        // copyWith so images/condition/stores - fields this form doesn't
        // touch - survive an edit instead of getting silently wiped.
        // Known limit: copyWith's `field ?? this.field` pattern can't
        // tell "leave unchanged" apart from "clear it" - clearing an
        // already-set description/category back to empty via this form
        // won't take. Not fixed here since it's a pre-existing pattern
        // this codebase uses everywhere, not something specific to this
        // screen, and the actual ask (quantity/price adjustment) isn't
        // affected - a number is never "cleared", just changed.
        ? existing.copyWith(
            title: _titleController.text.trim(),
            description: description,
            price: price,
            quantity: quantity,
            category: _selectedCategory,
          )
        : CatalogItem(
            sku: _skuController.text.trim(),
            title: _titleController.text.trim(),
            description: description,
            price: price,
            quantity: quantity,
            category: _selectedCategory,
          );
    Navigator.of(context).pop(item);
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: HandlesText.eyebrow()),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          enabled: enabled,
          style: HandlesText.body(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: HandlesText.body(fontSize: 13, color: HandlesColors.inkFaint),
            border: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
            focusedBorder:
                OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.silverBright)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.selected, required this.onTap});

  final CategoryRecommendation suggestion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Matched: ${suggestion.matchedKeywords.join(', ')}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? HandlesColors.silverBright : Colors.transparent,
            border: Border.all(color: selected ? HandlesColors.silverBright : HandlesColors.silver),
          ),
          child: Text(
            suggestion.category,
            style: HandlesText.data(
              fontSize: 13,
              weight: FontWeight.w600,
              color: selected ? HandlesColors.flairInk : HandlesColors.silverBright,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainCategoryChip extends StatelessWidget {
  const _PlainCategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? HandlesColors.surfaceRaised : Colors.transparent,
          border: Border.all(color: selected ? HandlesColors.borderStrong : HandlesColors.border),
        ),
        child: Text(
          label,
          style: HandlesText.data(fontSize: 13, color: HandlesColors.inkMuted),
        ),
      ),
    );
  }
}
