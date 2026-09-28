import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseStoreAccountRegistry', () {
    test(r'parses each account and skips the $comment header', () {
      final json = {
        r'$comment': 'this is a header, not an account',
        'ebay_store_a': {
          'platform': 'ebay',
          'display_name': 'eBay Store A',
          'store_url': 'https://example.com/store-a',
          'automation': 'full',
        },
        'poshmark': {
          'platform': 'poshmark',
          'display_name': 'Poshmark closet',
          'store_url': null,
          'automation': 'monitor_only',
        },
      };

      final accounts = parseStoreAccountRegistry(json);

      expect(accounts.keys, containsAll(['ebay_store_a', 'poshmark']));
      expect(accounts.keys, isNot(contains(r'$comment')));
      expect(accounts['ebay_store_a']!.automation, AutomationLevel.full);
      expect(accounts['poshmark']!.automation, AutomationLevel.monitorOnly);
    });
  });
}
