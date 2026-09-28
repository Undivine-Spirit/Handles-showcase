import 'dart:convert';
import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// Receives marketplace webhooks and turns a real event into an immediate
/// reconciliation pass instead of waiting for `reconcile_daemon.dart`'s
/// next poll. See docs/DEPLOYMENT.md's webhook entry for the full design
/// and why eBay only gets the mandatory Account Deletion topic here (order
/// webhooks don't reliably fire for ordinary eBay sellers - Walmart's
/// `PO_CREATED` is the one that actually works).
///
/// This is the one part of the deployment meant to be reachable from the
/// public internet (via Tailscale Funnel) - everything else stays
/// tailnet-only. It never touches `API_AUTH_TOKEN`; marketplaces can't send
/// a bearer token, so each route verifies whatever scheme that marketplace
/// actually uses instead.
///
/// Bridges to the daemon (a separate container/process) via a trigger
/// file in the same shared `CATALOG_DIR` mount, rather than a new
/// network/auth surface between internal services - see
/// `reconcile_daemon.dart`'s sleep loop for the other half of this.
Future<void> main() async {
  final env = Platform.environment;
  final catalogDir = env['CATALOG_DIR'] ?? '/app/catalog';
  final port = int.tryParse(env['WEBHOOK_PORT'] ?? '') ?? 8081;

  final ebayVerificationToken = env['EBAY_VERIFICATION_TOKEN'];
  final ebayEndpointUrl = env['EBAY_WEBHOOK_ENDPOINT_URL'];
  final ebayVerifier = (ebayVerificationToken != null && ebayVerificationToken.isNotEmpty &&
          ebayEndpointUrl != null && ebayEndpointUrl.isNotEmpty)
      ? EbayNotificationVerifier(verificationToken: ebayVerificationToken, endpointUrl: ebayEndpointUrl)
      : null;
  if (ebayVerifier == null) {
    stdout.writeln('EBAY_VERIFICATION_TOKEN/EBAY_WEBHOOK_ENDPOINT_URL not set - '
        'the eBay account-deletion route will return 503 until configured.');
  }

  final walmartClientSecret = env['WALMART_CLIENT_SECRET'];
  final walmartVerifier = (walmartClientSecret != null && walmartClientSecret.isNotEmpty)
      ? WalmartWebhookVerifier(clientSecret: walmartClientSecret)
      : null;
  final walmartHeaderName = (env['WALMART_WEBHOOK_HEADER_NAME'] ?? 'X-Handles-Signature').toLowerCase();
  if (walmartVerifier == null) {
    stdout.writeln('WALMART_CLIENT_SECRET not set - the Walmart PO_CREATED route will return 503 '
        'until configured.');
  }

  if (ebayVerifier == null && walmartVerifier == null) {
    stderr.writeln('Neither eBay nor Walmart webhook credentials are configured - '
        'refusing to start a webhook receiver with nothing to serve.');
    exit(1);
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_errorMiddleware())
      .addMiddleware(_rateLimitMiddleware(_RateLimiter()))
      .addHandler(
        _buildRouter(
          catalogDir: catalogDir,
          ebayVerifier: ebayVerifier,
          walmartVerifier: walmartVerifier,
          walmartHeaderName: walmartHeaderName,
        ).call,
      );

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('[${DateTime.now().toUtc().toIso8601String()}] webhook receiver listening on '
      '${server.address.host}:${server.port} (ebay: ${ebayVerifier != null ? 'on' : 'off'}, '
      'walmart: ${walmartVerifier != null ? 'on' : 'off'})');
}

Middleware _errorMiddleware() {
  return createMiddleware(errorHandler: (error, stackTrace) => _errorResponse(error));
}

/// A global (not per-IP) rate limit - this server sits behind Tailscale
/// Funnel's relay, which may not preserve the original client address the
/// way a normal reverse proxy's X-Forwarded-For would, so a per-IP limit
/// could be trivially wrong. A single shared budget across both webhook
/// routes still bounds the real risk (log growth, CPU on a flood of
/// forged/retried calls) without depending on an address this process
/// can't reliably trust.
Middleware _rateLimitMiddleware(_RateLimiter limiter) {
  return createMiddleware(requestHandler: (request) {
    if (request.url.path == 'health') return null;
    if (!limiter.allow()) {
      return _json({'error': 'rate limit exceeded, try again shortly'}, statusCode: 429);
    }
    return null;
  });
}

class _RateLimiter {
  static const _maxRequests = 30;
  static const _window = Duration(minutes: 1);

  final List<DateTime> _hits = [];

  bool allow() {
    final now = DateTime.now();
    _hits.removeWhere((t) => now.difference(t) > _window);
    if (_hits.length >= _maxRequests) return false;
    _hits.add(now);
    return true;
  }
}

Response _json(Object? body, {int statusCode = 200}) => Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Response _errorResponse(Object error, {int statusCode = 500}) =>
    _json({'error': error.toString()}, statusCode: statusCode);

/// Drops the file `reconcile_daemon.dart`'s sleep loop watches for. Kept
/// deliberately synchronous and trivial - Walmart requires a response
/// within 3 seconds, and Tailscale Funnel adds a relay hop on top of that.
Future<void> _triggerReconciliationPass(String catalogDir) async {
  final file = File('$catalogDir/.trigger-now');
  await file.writeAsString(DateTime.now().toUtc().toIso8601String());
}

Router _buildRouter({
  required String catalogDir,
  required EbayNotificationVerifier? ebayVerifier,
  required WalmartWebhookVerifier? walmartVerifier,
  required String walmartHeaderName,
}) {
  final router = Router();

  router.get('/health', (Request request) => _json({'status': 'ok'}));

  router.get('/webhooks/ebay/account-deletion', (Request request) {
    if (ebayVerifier == null) {
      return _json({'error': 'eBay webhook not configured'}, statusCode: 503);
    }
    final challengeCode = request.url.queryParameters['challenge_code'];
    if (challengeCode == null || challengeCode.isEmpty) {
      return Response.badRequest(body: jsonEncode({'error': 'missing challenge_code'}));
    }
    return _json({'challengeResponse': ebayVerifier.computeChallengeResponse(challengeCode)});
  });

  router.post('/webhooks/ebay/account-deletion', (Request request) async {
    if (ebayVerifier == null) {
      return _json({'error': 'eBay webhook not configured'}, statusCode: 503);
    }
    final signatureHeader = request.headers['x-ebay-signature'];
    if (!ebayVerifier.hasWellFormedSignatureHeader(signatureHeader)) {
      return Response.forbidden(jsonEncode({'error': 'missing or malformed X-EBAY-SIGNATURE'}));
    }

    final body = await request.readAsString();
    // Signature isn't cryptographically verified yet (see
    // EbayNotificationVerifier's doc comment) - logged for manual review
    // rather than acted on automatically.
    stdout.writeln('[${DateTime.now().toUtc().toIso8601String()}] eBay account-deletion '
        'notification received - not auto-processed, needs manual review: $body');
    return _json({'status': 'received'});
  });

  router.post('/webhooks/walmart/po-created', (Request request) async {
    if (walmartVerifier == null) {
      return _json({'error': 'Walmart webhook not configured'}, statusCode: 503);
    }
    final signatureHeader = request.headers[walmartHeaderName];
    if (signatureHeader == null) {
      return Response.forbidden(jsonEncode({'error': 'missing signature header'}));
    }

    final bodyBytes = await request.read().expand((chunk) => chunk).toList();
    if (!walmartVerifier.verify(signatureHeader: signatureHeader, bodyBytes: bodyBytes)) {
      return Response.forbidden(jsonEncode({'error': 'signature verification failed'}));
    }

    await _triggerReconciliationPass(catalogDir);
    return _json({'status': 'received'});
  });

  router.all('/<ignored|.*>', (Request request) => Response.notFound(
        jsonEncode({'error': 'no route for ${request.method} ${request.url.path}'}),
        headers: {'content-type': 'application/json'},
      ));

  return router;
}
