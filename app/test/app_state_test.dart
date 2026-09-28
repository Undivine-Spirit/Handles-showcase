import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/services/ebay_app_config.dart';
import 'package:handles_app/services/keepa_config.dart';
import 'package:handles_app/services/walmart_app_config.dart';

import 'test_helpers.dart';

void main() {
  group('AppState - connect validation (no network involved)', () {
    test('connectWalmartAccount fails cleanly when app config is incomplete', () async {
      final appState = await testAppState();

      final result = await appState.connectWalmartAccount('walmart');

      expect(result.success, isFalse);
      expect(result.error, contains('Walmart Client ID/Secret'));
      expect(appState.isConnected('walmart'), isFalse);
    });

    test('connectEbayAccount fails cleanly when app config is incomplete', () async {
      final appState = await testAppState();

      final result = await appState.connectEbayAccount('ebay_store_a');

      expect(result.success, isFalse);
      expect(result.error, contains('eBay developer app credentials'));
      expect(appState.isConnected('ebay_store_a'), isFalse);
    });
  });

  group('AppState - config persistence', () {
    test('saveWalmartAppConfig persists through the credential store and notifies', () async {
      final appState = await testAppState();
      var notified = false;
      appState.addListener(() => notified = true);

      await appState.saveWalmartAppConfig(
        const WalmartAppConfig(clientId: 'wm-id', clientSecret: 'wm-secret'),
      );

      expect(notified, isTrue);
      expect(appState.walmartAppConfig.clientId, 'wm-id');
      final stored = await appState.credentialStore.read('walmart_app_config');
      expect(stored?['client_id'], 'wm-id');
    });

    test('saveEbayAppConfig persists through the credential store', () async {
      final appState = await testAppState();

      await appState.saveEbayAppConfig(
        const EbayAppConfig(clientId: 'eb-id', clientSecret: 'eb-secret', redirectUri: 'RuName-1'),
      );

      expect(appState.ebayAppConfig.redirectUri, 'RuName-1');
      final stored = await appState.credentialStore.read('ebay_app_config');
      expect(stored?['redirect_uri'], 'RuName-1');
    });

    test('saveKeepaConfig persists the API key through the credential store', () async {
      final appState = await testAppState();

      await appState.saveKeepaConfig(const KeepaConfig(apiKey: 'keepa-key-123'));

      expect(appState.keepaConfig.apiKey, 'keepa-key-123');
      final stored = await appState.credentialStore.read('keepa_config');
      expect(stored?['api_key'], 'keepa-key-123');
    });
  });

  group('AppState - sourcing engine defaults', () {
    test('updateSettings persists a changed destination fee rate and desired profit', () async {
      final appState = await testAppState();

      await appState.updateSettings(
        appState.settings.copyWith(defaultDesiredProfit: 15, defaultDestinationFeeRate: 0.10),
      );

      expect(appState.settings.defaultDesiredProfit, 15);
      final reloaded = await appState.settingsStore.load();
      expect(reloaded.defaultDestinationFeeRate, 0.10);
    });
  });

  group('AppState - disconnect', () {
    test('disconnectAccount removes stored credentials and flips connection status', () async {
      final appState = await testAppState();
      await appState.credentialStore.write('walmart', {'access_token': 'x'});
      await appState.init(); // re-derive _connected from the credential store

      expect(appState.isConnected('walmart'), isTrue);

      await appState.disconnectAccount('walmart');

      expect(appState.isConnected('walmart'), isFalse);
      expect(await appState.credentialStore.read('walmart'), isNull);
    });
  });
}
