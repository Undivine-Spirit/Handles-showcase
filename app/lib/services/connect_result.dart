/// Outcome of a "connect this account" attempt - shared across every
/// platform's connect flow (eBay's browser-based OAuth, Walmart's direct
/// credential check) since the UI only ever needs to know success/error,
/// not how each platform got there.
class ConnectResult {
  const ConnectResult._({required this.success, this.error});

  factory ConnectResult.success() => const ConnectResult._(success: true);
  factory ConnectResult.failure(String error) => ConnectResult._(success: false, error: error);

  final bool success;
  final String? error;
}
