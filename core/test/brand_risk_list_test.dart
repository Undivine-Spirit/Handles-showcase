import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('BrandRiskList', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('handles-brand-risk-list-test-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns an empty list when the file does not exist yet', () async {
      final list = BrandRiskList(File('${tempDir.path}/brand_risk_list.json'));

      expect(await list.load(), isEmpty);
    });

    test('save then load round-trips every field', () async {
      final list = BrandRiskList(File('${tempDir.path}/brand_risk_list.json'));
      final entry = BrandRiskEntry(
        brand: 'Nike',
        reason: 'Known eBay VeRO enforcer',
        source: BrandRiskSource.curated,
        addedAt: DateTime.utc(2026, 8, 29),
      );

      await list.save([entry]);
      final loaded = await list.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.brand, 'Nike');
      expect(loaded.single.reason, 'Known eBay VeRO enforcer');
      expect(loaded.single.source, BrandRiskSource.curated);
      expect(loaded.single.addedAt, DateTime.utc(2026, 8, 29));
    });

    test('add appends without clobbering existing entries', () async {
      final list = BrandRiskList(File('${tempDir.path}/brand_risk_list.json'));
      await list.add(BrandRiskEntry(brand: 'Nike', reason: 'r1', source: BrandRiskSource.curated));

      await list.add(BrandRiskEntry(
        brand: 'HND-0091 buyer complaint',
        reason: 'Delisted for IP complaint on eBay, 2026-08-15',
        source: BrandRiskSource.ownHistory,
      ));

      final loaded = await list.load();
      expect(loaded, hasLength(2));
      expect(loaded.map((e) => e.brand), containsAll(['Nike', 'HND-0091 buyer complaint']));
    });

    test('removeByBrand removes only the matching entry, case-insensitively', () async {
      final list = BrandRiskList(File('${tempDir.path}/brand_risk_list.json'));
      await list.add(BrandRiskEntry(brand: 'Nike', reason: 'r1', source: BrandRiskSource.curated));
      await list.add(BrandRiskEntry(brand: 'Disney', reason: 'r2', source: BrandRiskSource.curated));

      await list.removeByBrand(' NIKE ');

      final loaded = await list.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.brand, 'Disney');
    });
  });
}
