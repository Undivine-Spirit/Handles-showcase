import 'dart:convert';

import 'package:handles_core/handles_core.dart';
import 'package:http/http.dart' as http;

import 'catalog_api_config.dart';

/// What a sync actually produced - the app doesn't distinguish "fetched
/// from the server" from "already had it" for its own state, so all three
/// come back together rather than as three separate calls a caller has
/// to sequence.
class CatalogSyncResult {
  const CatalogSyncResult({required this.items, required this.events, required this.brandRiskEntries});

  final List<CatalogItem> items;
  final List<HandlesEvent> events;
  final List<BrandRiskEntry> brandRiskEntries;
}

/// Wraps whatever actually went wrong (a network failure, a non-2xx
/// response, this client's own "not configured yet") behind one
/// exception type so callers don't need to know `package:http` exists to
/// catch failures sanely. Same name as the git-based version this
/// replaced - still "something went wrong syncing the catalog" from a
/// caller's point of view, the transport underneath changed, not the
/// contract.
class CatalogSyncException implements Exception {
  CatalogSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _requestTimeout = Duration(seconds: 10);

/// The app's half of `docs/PROJECT_PLAN.md` section 2's 2026-09-02
/// update - a thin HTTP client for `core/bin/api_server.dart`, replacing
/// what used to be the app's own independent git clone
/// (`CatalogSyncService`, removed). That clone was also almost certainly
/// broken on Android in the first place - Android has no `git` binary in
/// PATH by default, so `Process.run('git', ...)` had nowhere to actually
/// run there. HTTP works identically on every platform this app targets,
/// which is the more fundamental reason this is the right fix, not just
/// the one that matches what's asked for.
class CatalogApiClient {
  CatalogApiClient({required this.config});

  final CatalogApiConfig config;

  Uri _uri(String path) {
    var base = config.baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.apiToken}',
        'Content-Type': 'application/json',
      };

  void _requireConfigured() {
    if (!config.isComplete) {
      throw CatalogSyncException('Add a catalog server URL and token in Settings first.');
    }
  }

  Future<CatalogSyncResult> sync() async {
    _requireConfigured();
    return _guarded(() async {
      final items = await _getList('/catalog/items', CatalogItem.fromJson);
      final events = await _getList('/catalog/events', HandlesEvent.fromJson);
      final brandRisk = await _getList('/catalog/brand-risk', BrandRiskEntry.fromJson);
      return CatalogSyncResult(items: items, events: events, brandRiskEntries: brandRisk);
    });
  }

  Future<void> saveItem(CatalogItem item) async {
    _requireConfigured();
    await _guarded(() => _put('/catalog/items/${Uri.encodeComponent(item.sku)}', item.toJson()));
  }

  Future<void> addBrandRiskEntry(BrandRiskEntry entry) async {
    _requireConfigured();
    await _guarded(() => _post('/catalog/brand-risk', {
          'brand': entry.brand,
          'reason': entry.reason,
          'source': entry.source.toJson(),
        }));
  }

  Future<void> removeBrandRiskEntry(String brand) async {
    _requireConfigured();
    await _guarded(() => _delete('/catalog/brand-risk/${Uri.encodeComponent(brand)}'));
  }

  /// Appends one entry to the server's audit trail (`GET /catalog/events`
  /// already surfaces these) - callers use this fire-and-forget (see
  /// `AppState._logAction`/`main.dart`'s crash handler) since a failure to
  /// log shouldn't ever block or fail the actual user action or crash
  /// report it's describing. The server stamps its own timestamp; nothing
  /// sent here is trusted for that.
  Future<void> logEvent({
    required EventSeverity severity,
    required String source,
    required String message,
    String? sku,
    String? accountKey,
  }) async {
    _requireConfigured();
    final body = {
      'severity': severity.toJson(),
      'source': source,
      'message': message,
    };
    if (sku != null) body['sku'] = sku;
    if (accountKey != null) body['account_key'] = accountKey;
    await _guarded(() => _post('/catalog/events', body));
  }

  /// Runs [body], turning any exception it doesn't already throw as a
  /// [CatalogSyncException] (a network failure, a timeout, a malformed
  /// response) into one - a caller should never need to know
  /// `package:http`'s own exception types exist.
  Future<T> _guarded<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CatalogSyncException {
      rethrow;
    } catch (e) {
      throw CatalogSyncException('Could not reach the catalog server: $e');
    }
  }

  Future<List<T>> _getList<T>(String path, T Function(Map<String, dynamic>) fromJson) async {
    final response = await http.get(_uri(path), headers: _headers).timeout(_requestTimeout);
    _checkStatus(response);
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final response =
        await http.put(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(_requestTimeout);
    _checkStatus(response);
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final response =
        await http.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(_requestTimeout);
    _checkStatus(response);
  }

  Future<void> _delete(String path) async {
    final response = await http.delete(_uri(path), headers: _headers).timeout(_requestTimeout);
    _checkStatus(response);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var message = 'catalog server returned ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) message = decoded['error'].toString();
    } catch (_) {
      // Body wasn't JSON (or was empty) - the generic message stands.
    }
    throw CatalogSyncException(message);
  }
}
