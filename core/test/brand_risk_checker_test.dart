import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

BrandRiskEntry _entry(String brand, {BrandRiskSource source = BrandRiskSource.curated}) =>
    BrandRiskEntry(brand: brand, reason: 'Known VeRO enforcer', source: source);

void main() {
  group('BrandRiskChecker.check', () {
    test('flags an exact match', () {
      final checker = BrandRiskChecker([_entry('Nike')]);

      final verdict = checker.check('Nike');

      expect(verdict.isFlagged, isTrue);
      expect(verdict.matchedEntry!.brand, 'Nike');
    });

    test('matches case-insensitively and ignores surrounding whitespace', () {
      final checker = BrandRiskChecker([_entry('Nike')]);

      expect(checker.check(' nike ').isFlagged, isTrue);
      expect(checker.check('NIKE').isFlagged, isTrue);
    });

    test('does not flag an unrelated brand', () {
      final checker = BrandRiskChecker([_entry('Nike')]);

      final verdict = checker.check('Some Generic Brand');

      expect(verdict.isFlagged, isFalse);
      expect(verdict.matchedEntry, isNull);
    });

    test('is not fuzzy - a brand family variant does not match its parent', () {
      final checker = BrandRiskChecker([_entry('Nike')]);

      // Deliberate: see the class doc comment on why this stays simple
      // rather than pretending to catch brand-family variants.
      expect(checker.check('Nike Golf').isFlagged, isFalse);
    });

    test('an empty list flags nothing', () {
      final checker = BrandRiskChecker([]);

      expect(checker.check('Anything').isFlagged, isFalse);
    });
  });
}
