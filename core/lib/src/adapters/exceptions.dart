/// Base type for every error a [StoreAdapter] can throw. The reconciliation
/// engine (not yet built - see `docs/PROJECT_PLAN.md` section 5) is where
/// retry/backoff policy around these belongs; adapters only classify the
/// failure, they don't decide what to do about it.
sealed class StoreAdapterException implements Exception {
  StoreAdapterException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The store's API rejected the request outright (bad data, invalid
/// state) - retrying with the same input won't help.
class StoreAdapterRequestException extends StoreAdapterException {
  StoreAdapterRequestException(super.message, {this.statusCode, this.responseBody});

  final int? statusCode;
  final String? responseBody;
}

/// Rate limited - a distinct type (not just a 4xx) so the reconciliation
/// engine can back off specifically, per the per-API token-bucket limits
/// documented in `docs/API_RESEARCH.md`.
class StoreAdapterRateLimitException extends StoreAdapterException {
  StoreAdapterRateLimitException(super.message, {this.retryAfter});

  /// Server-supplied backoff hint, when the API provides one.
  final Duration? retryAfter;
}

/// Credentials are missing, expired, or were rejected, and re-authenticating
/// automatically wasn't possible - e.g. a refresh token was revoked and the
/// account needs the human consent flow run again
/// (see `ebay_oauth_client.dart`).
class StoreAdapterAuthException extends StoreAdapterException {
  StoreAdapterAuthException(super.message);
}

/// The requested listing/SKU doesn't exist on the store's side.
class StoreAdapterNotFoundException extends StoreAdapterException {
  StoreAdapterNotFoundException(super.message);
}
