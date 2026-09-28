import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Verifies Walmart Marketplace's `PO_CREATED` webhook using the `HMAC`
/// `authMethod` documented at developer.walmart.com/us-marketplace/docs/
/// subscribe-to-an-event-notification: the header (whatever name you chose
/// as `authHeaderName` when creating the subscription) carries
/// `HMACSHA256(body)`, keyed with the app's client secret.
///
/// Walmart's docs don't spell out hex vs. base64 for the digest - this
/// defaults to hex (the more common convention for this pattern) but
/// verify against Walmart's own Test Notification API response before
/// relying on it; see docs/DEPLOYMENT.md's webhook entry.
class WalmartWebhookVerifier {
  WalmartWebhookVerifier({required this.clientSecret});

  final String clientSecret;

  bool verify({required String signatureHeader, required List<int> bodyBytes}) {
    final expected = Hmac(sha256, utf8.encode(clientSecret)).convert(bodyBytes).toString();
    return _constantTimeEquals(expected, signatureHeader.trim().toLowerCase());
  }

  /// Ordinary `==` short-circuits on the first differing character, which
  /// leaks timing information an attacker could use to guess the correct
  /// signature one byte at a time. Not a large risk for this app, but a
  /// signature check is exactly the kind of comparison worth doing right.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
