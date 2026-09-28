import 'dart:convert';
import 'dart:io';

import 'brand_risk_entry.dart';

/// Reads/writes `catalog/brand_risk_list.json` - one JSON array of
/// [BrandRiskEntry], living in the catalog directory on purpose (like
/// `stores.json` and `.events.jsonl`) so it travels via git and is
/// available to the daemon and the app equally, not just whichever one
/// happened to add an entry.
///
/// A missing file means an empty list, not an error - same convention as
/// `CatalogRepository`/the daemon's `stores.json` check: nothing known
/// yet, not "checked and clear."
class BrandRiskList {
  BrandRiskList(this.file);

  final File file;

  Future<List<BrandRiskEntry>> load() async {
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
    return decoded.map((e) => BrandRiskEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<BrandRiskEntry> entries) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(entries.map((e) => e.toJson()).toList())}\n',
    );
  }

  /// Appends one entry - the common case (a human adding a curated brand,
  /// or the app logging a fresh own-history strike) without the caller
  /// needing to load-modify-save by hand every time.
  Future<void> add(BrandRiskEntry entry) async {
    final entries = await load();
    entries.add(entry);
    await save(entries);
  }

  /// Removes every entry with this exact brand name (case-insensitive) -
  /// undoing a typo or a brand added by mistake. Matches on brand name
  /// rather than an id since entries have no id and brand names are
  /// already how `BrandRiskChecker` identifies them.
  Future<void> removeByBrand(String brand) async {
    final normalized = brand.trim().toLowerCase();
    final entries = await load();
    entries.removeWhere((e) => e.brand.trim().toLowerCase() == normalized);
    await save(entries);
  }
}
