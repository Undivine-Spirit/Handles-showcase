import 'dart:convert';
import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// The catalog API server - `docs/PROJECT_PLAN.md` section 2's "sources of
/// truth should call the backend from the server" (2026-09-02). Runs
/// alongside the reconciliation daemon on the same host, sharing the same
/// mounted catalog checkout (`CATALOG_DIR`) - not a second independent
/// clone. That's the actual fix for "local saves and server side create
/// conflicts": the daemon and this server see the same files on the same
/// disk in real time, no git round-trip needed between them. The app is
/// the one thing that used to keep its own separate clone
/// (`CatalogSyncService`); this is what replaces that.
///
/// Every request needs `Authorization: Bearer <API_AUTH_TOKEN>` - there is
/// no per-user auth here, one shared secret the app stores the same way
/// it already stores other credentials (`flutter_secure_storage`). This
/// is enough for "one client, one server, reachable from anywhere" but
/// only if the connection itself is HTTPS - see `docs/DEPLOYMENT.md`. A
/// bearer token over plain HTTP is trivially interceptable; this server
/// does not terminate TLS itself, put a reverse proxy in front of it.
Future<void> main() async {
  final env = Platform.environment;
  final catalogDir = Directory(env['CATALOG_DIR'] ?? '/app/catalog');
  final port = int.tryParse(env['API_PORT'] ?? '') ?? 8080;
  final authToken = env['API_AUTH_TOKEN'];

  if (authToken == null || authToken.isEmpty) {
    stderr.writeln(
      'API_AUTH_TOKEN is not set - refusing to start an unauthenticated catalog API.',
    );
    exit(1);
  }

  final gitPushEnabled = (env['API_GIT_PUSH'] ?? 'true').toLowerCase() != 'false';
  final store = CatalogDataStore(
    catalogDir,
    gitSync: gitPushEnabled ? GitSync(catalogDir.path) : null,
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_errorMiddleware())
      .addMiddleware(_authMiddleware(authToken))
      .addHandler(_buildRouter(store).call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('[${DateTime.now().toUtc().toIso8601String()}] catalog API listening on '
      '${server.address.host}:${server.port}, catalog dir: ${catalogDir.path}, '
      'git push: ${gitPushEnabled ? 'on' : 'off'}');
}

/// Turns any exception a route handler doesn't catch itself into a
/// consistent JSON body instead of shelf's plain-text default - every
/// other response this server sends is JSON, an API client shouldn't have
/// to special-case the failure path.
Middleware _errorMiddleware() {
  return createMiddleware(
    errorHandler: (error, stackTrace) => _errorResponse(error),
  );
}

Middleware _authMiddleware(String expectedToken) {
  return createMiddleware(requestHandler: (request) {
    if (request.url.path == 'health') return null; // unauthenticated liveness check
    final header = request.headers['authorization'];
    if (header == 'Bearer $expectedToken') return null; // continue to the real handler
    return Response.unauthorized(jsonEncode({'error': 'missing or invalid bearer token'}),
        headers: {'content-type': 'application/json'});
  });
}

Response _json(Object? body, {int statusCode = 200}) => Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Response _errorResponse(Object error, {int statusCode = 500}) =>
    _json({'error': error.toString()}, statusCode: statusCode);

Router _buildRouter(CatalogDataStore store) {
  final router = Router();

  router.get('/health', (Request request) => _json({'status': 'ok'}));

  router.get('/catalog/items', (Request request) async {
    final items = await store.loadItems();
    return _json(items.map((i) => i.toJson()).toList());
  });

  router.put('/catalog/items/<sku>', (Request request, String sku) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid JSON body: $e'}));
    }

    final CatalogItem item;
    try {
      item = CatalogItem.fromJson({...body, 'sku': sku});
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid catalog item: $e'}));
    }

    final saved = await store.saveItem(item);
    return _json(saved.toJson());
  });

  router.get('/catalog/events', (Request request) async {
    final limitParam = request.url.queryParameters['limit'];
    final limit = int.tryParse(limitParam ?? '') ?? 50;
    final events = await store.recentEvents(limit: limit);
    return _json(events.map((e) => e.toJson()).toList());
  });

  router.post('/catalog/events', (Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid JSON body: $e'}));
    }

    final HandlesEvent event;
    try {
      event = HandlesEvent(
        // Server-stamped, not client-supplied - a client clock can be
        // wrong or, worse, deliberately backdated; this log is meant to
        // be trustworthy audit history, not just a display value.
        timestamp: DateTime.now().toUtc(),
        severity: EventSeverity.fromJson(body['severity'] as String),
        source: body['source'] as String,
        message: body['message'] as String,
        sku: body['sku'] as String?,
        accountKey: body['account_key'] as String?,
      );
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid event: $e'}));
    }

    await store.recordEvent(event);
    return _json(event.toJson(), statusCode: 201);
  });

  router.get('/catalog/brand-risk', (Request request) async {
    final entries = await store.loadBrandRisk();
    return _json(entries.map((e) => e.toJson()).toList());
  });

  router.get('/catalog/brand-risk/check/<brand>', (Request request, String brand) async {
    final verdict = await store.checkBrandRisk(Uri.decodeComponent(brand));
    return _json({
      'is_flagged': verdict.isFlagged,
      if (verdict.matchedEntry != null) 'matched_entry': verdict.matchedEntry!.toJson(),
    });
  });

  router.post('/catalog/brand-risk', (Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid JSON body: $e'}));
    }

    final BrandRiskEntry entry;
    try {
      entry = BrandRiskEntry(
        brand: body['brand'] as String,
        reason: body['reason'] as String,
        source: BrandRiskSource.fromJson(body['source'] as String),
      );
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'invalid brand risk entry: $e'}));
    }

    final saved = await store.addBrandRiskEntry(entry);
    return _json(saved.toJson(), statusCode: 201);
  });

  router.delete('/catalog/brand-risk/<brand>', (Request request, String brand) async {
    await store.removeBrandRiskEntry(Uri.decodeComponent(brand));
    return Response(204);
  });

  router.all('/<ignored|.*>', (Request request) => Response.notFound(
        jsonEncode({'error': 'no route for ${request.method} ${request.url.path}'}),
        headers: {'content-type': 'application/json'},
      ));

  return router;
}
