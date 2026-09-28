import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Handles eBay's Notification API "destination" handshake for the
/// **Marketplace Account Deletion** topic - the only eBay notification
/// that reliably fires for ordinary sellers (order/sale topics don't; see
/// docs/PROJECT_PLAN.md's webhook entry). This is a compliance
/// requirement, not part of the reconciliation data path.
class EbayNotificationVerifier {
  EbayNotificationVerifier({required this.verificationToken, required this.endpointUrl});

  /// The token registered with eBay's `createDestination` call - 32-80
  /// chars, alphanumeric/underscore/hyphen only, per eBay's requirement.
  final String verificationToken;

  /// Must exactly match the URL registered with eBay - it's part of the
  /// hash input below, not just a label.
  final String endpointUrl;

  /// eBay's documented handshake: `SHA256(challengeCode + verificationToken
  /// + endpoint)`, hex-encoded, returned as `{"challengeResponse": "..."}`.
  String computeChallengeResponse(String challengeCode) {
    final hash = sha256.convert(utf8.encode('$challengeCode$verificationToken$endpointUrl'));
    return hash.toString();
  }

  /// eBay signs each real notification with `X-EBAY-SIGNATURE` (an
  /// ECDSA/P-256 signature over the body, key fetched per-`kid` from
  /// `commerce/notification/v1/public_key/{kid}`). `package:crypto` only
  /// does hashing/HMAC, not asymmetric signature verification, and adding
  /// an EC-capable dependency (e.g. `pointycastle`) to verify a
  /// compliance-only, no-sensitive-data topic against a scheme this
  /// environment has no live eBay credentials to test against wasn't worth
  /// the risk of a subtle, untested crypto bug shipping as if it were
  /// solid. This checks the header is present and well-formed (so a
  /// completely unsigned request is rejected) without verifying the
  /// signature itself - treat a deletion request as "flag for manual
  /// review," not "auto-delete unattended," until real ECDSA verification
  /// is added and tested against eBay's sandbox.
  bool hasWellFormedSignatureHeader(String? signatureHeader) {
    if (signatureHeader == null || signatureHeader.isEmpty) return false;
    try {
      final decoded = jsonDecode(utf8.decode(base64.decode(signatureHeader))) as Map<String, dynamic>;
      return decoded['kid'] is String && decoded['signature'] is String;
    } catch (_) {
      return false;
    }
  }
}
