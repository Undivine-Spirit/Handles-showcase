import 'dart:async';
import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'connect_result.dart';

/// **Read before wiring up a real account.** eBay's OAuth `redirect_uri`
/// parameter is not a literal URL - it's a "RuName", an identifier you
/// generate in the eBay developer portal, which is itself configured with
/// a real "your auth accepted URL". For this loopback flow to work:
///
/// 1. In the developer portal, create a RuName whose accepted URL is
///    `http://127.0.0.1:$loopbackPort/callback` (same port as below).
/// 2. Pass that RuName **string** (not the raw URL) as `EbayOAuthClient`'s
///    `redirectUri`.
///
/// Not re-verified against eBay's current developer-portal UI at the time
/// this was written (`core/docs` already flags that auth flows drift) -
/// confirm the RuName setup steps still work this way before relying on it.
const loopbackPort = 53682;

/// Runs eBay's authorization-code OAuth flow using the system browser and a
/// temporary local HTTP listener to catch the redirect - the standard
/// pattern for a desktop/mobile app doing OAuth (see e.g. Google's own
/// desktop-app OAuth guidance), and specifically what makes it possible for
/// this app to never see the user's eBay password: the login page is
/// eBay's own, in the user's own browser, not embedded in this app.
class EbayLoopbackAuthFlow {
  EbayLoopbackAuthFlow({required this.oauth, this.port = loopbackPort});

  final EbayOAuthClient oauth;
  final int port;

  /// Opens the system browser to eBay's consent page and waits for the
  /// redirect. Resolves once the user has approved (or denied, or the
  /// wait times out) - never throws for an expected outcome, so the caller
  /// can just check `.success`.
  Future<ConnectResult> connect({Duration timeout = const Duration(minutes: 5)}) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException catch (e) {
      return ConnectResult.failure(
        'Could not start the local listener on port $port (already in use?): ${e.message}',
      );
    }

    try {
      final consentUrl = oauth.buildConsentUrl();
      final opened = await url_launcher.launchUrl(
        consentUrl,
        mode: url_launcher.LaunchMode.externalApplication,
      );
      if (!opened) {
        return ConnectResult.failure('Could not open the system browser to eBay\'s login page.');
      }

      final request = await server.first.timeout(timeout);
      final code = request.uri.queryParameters['code'];
      final errorParam = request.uri.queryParameters['error'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_responseHtml(success: code != null));
      await request.response.close();

      if (code == null) {
        return ConnectResult.failure(errorParam ?? 'eBay did not return an authorization code.');
      }

      await oauth.exchangeAuthorizationCode(code);
      return ConnectResult.success();
    } on TimeoutException {
      return ConnectResult.failure('Timed out waiting for eBay to redirect back.');
    } on StoreAdapterAuthException catch (e) {
      return ConnectResult.failure(e.message);
    } finally {
      await server.close(force: true);
    }
  }

  String _responseHtml({required bool success}) {
    final message = success ? 'Connected — you can close this tab.' : 'Something went wrong — you can close this tab and try again in Handles.';
    return '<html><body style="font-family: sans-serif; padding: 40px; text-align: center;">'
        '<h2>$message</h2></body></html>';
  }
}
