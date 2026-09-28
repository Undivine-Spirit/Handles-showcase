import 'sourced_listing.dart';

/// Where a [SourcedListing]'s supplier stock status actually comes from.
/// Interface, not a concrete implementation, for the same reason
/// `CredentialStore`/`SettingsStore` are: the real answer (Keepa's paid
/// API, `docs/API_RESEARCH.md`) isn't subscribed to yet (section 9) -
/// this lets the monitor logic get
/// built and tested now against a fake, and the real Keepa-backed
/// implementation slot in later without touching anything that uses it.
abstract interface class SupplierStockChecker {
  Future<SupplierStockStatus> checkStock(String asin);
}
