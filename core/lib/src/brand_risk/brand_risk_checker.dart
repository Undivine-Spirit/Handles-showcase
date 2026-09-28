import 'brand_risk_entry.dart';

/// The result of checking one brand name - deliberately not a bool. A
/// caller (or a human reading an event log entry) should never be able to
/// mistake "not flagged" for "cleared to sell" - see [BrandRiskChecker]'s
/// own doc comment.
class BrandRiskVerdict {
  const BrandRiskVerdict({required this.isFlagged, this.matchedEntry});

  final bool isFlagged;
  final BrandRiskEntry? matchedEntry;
}

/// Matches a brand name against a known-risk list - this is a blocklist
/// lookup, not a clearance check, and not predictive. `docs/PROJECT_PLAN.md`
/// section 10's 2026-08-29 research note is the reason this is built this
/// way and not some smarter-sounding alternative: nothing, anywhere
/// (official or third-party, Amazon or eBay), does real predictive
/// brand-risk scoring today. A miss here means "this brand isn't in our
/// admittedly-incomplete list," never "safe to sell" - callers that treat
/// [BrandRiskVerdict.isFlagged] as "sell with confidence" are misusing it.
///
/// Matching is exact-after-normalization (trim + lowercase) - no fuzzy
/// matching, no brand-family grouping ("Nike" won't catch "Nike Golf").
/// Deliberately simple and honest about that limit rather than a
/// confidence-inspiring fuzzy matcher that's still fundamentally a
/// blocklist underneath.
class BrandRiskChecker {
  BrandRiskChecker(this._entries);

  final List<BrandRiskEntry> _entries;

  static String _normalize(String brand) => brand.trim().toLowerCase();

  BrandRiskVerdict check(String brand) {
    final normalized = _normalize(brand);
    for (final entry in _entries) {
      if (_normalize(entry.brand) == normalized) {
        return BrandRiskVerdict(isFlagged: true, matchedEntry: entry);
      }
    }
    return const BrandRiskVerdict(isFlagged: false);
  }
}
