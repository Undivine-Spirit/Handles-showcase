import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('HandlesSettings JSON round-trip', () {
    test('preserves priority categories and custom categories', () {
      const settings = HandlesSettings(
        priorityCategories: ['Sneakers', 'Denim'],
        customCategories: [Category(name: 'Home Goods', keywords: ['candle'])],
      );

      final restored = HandlesSettings.fromJson(settings.toJson());

      expect(restored.priorityCategories, ['Sneakers', 'Denim']);
      expect(restored.customCategories.single.name, 'Home Goods');
      expect(restored.customCategories.single.keywords, ['candle']);
    });

    test('preserves sourcing engine defaults, and falls back sanely when absent', () {
      const settings = HandlesSettings(defaultDesiredProfit: 12, defaultDestinationFeeRate: 0.15);
      final restored = HandlesSettings.fromJson(settings.toJson());
      expect(restored.defaultDesiredProfit, 12);
      expect(restored.defaultDestinationFeeRate, 0.15);

      final fromEmptyJson = HandlesSettings.fromJson({});
      expect(fromEmptyJson.defaultDesiredProfit, 8);
      expect(fromEmptyJson.defaultDestinationFeeRate, 0.13);
    });
  });

  group('HandlesSettings.allCategories', () {
    test('includes the defaults when no custom categories exist', () {
      const settings = HandlesSettings();

      expect(settings.allCategories.map((c) => c.name), contains('Sneakers'));
    });

    test('a custom category with the same name as a default overrides its keywords', () {
      const settings = HandlesSettings(
        customCategories: [Category(name: 'Sneakers', keywords: ['custom-kicks'])],
      );

      final sneakers = settings.allCategories.firstWhere((c) => c.name == 'Sneakers');
      expect(sneakers.keywords, ['custom-kicks']);
    });

    test('a genuinely new custom category is added alongside the defaults', () {
      const settings = HandlesSettings(
        customCategories: [Category(name: 'Home Goods', keywords: ['candle'])],
      );

      expect(settings.allCategories.map((c) => c.name), containsAll(['Sneakers', 'Home Goods']));
    });
  });

  group('InMemorySettingsStore', () {
    test('round-trips through load/save', () async {
      final store = InMemorySettingsStore();
      const settings = HandlesSettings(priorityCategories: ['Sneakers']);

      await store.save(settings);
      final loaded = await store.load();

      expect(loaded.priorityCategories, ['Sneakers']);
    });
  });
}
