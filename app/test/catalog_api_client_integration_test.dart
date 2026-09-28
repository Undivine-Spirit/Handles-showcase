// Real integration test - starts the actual core/bin/api_server.dart
// binary as a subprocess and exercises CatalogApiClient against it over
// real HTTP, not a mocked transport. This is the piece most worth
// verifying for real: the client and server were written against the
// same handles_core models, but only an actual request/response round
// trip proves the JSON shapes genuinely agree.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handles_app/services/catalog_api_client.dart';
import 'package:handles_app/services/catalog_api_config.dart';
import 'package:handles_core/handles_core.dart';

const _authToken = 'integration-test-token';

class _RunningServer {
  _RunningServer(this.process, this.port);
  final Process process;
  final int port;
}

Future<_RunningServer> _startServer(Directory catalogDir) async {
  final process = await Process.start(
    'dart',
    ['run', 'bin/api_server.dart'],
    workingDirectory: '../core',
    environment: {
      'CATALOG_DIR': catalogDir.path,
      // Port 0 - let the OS assign a free ephemeral port, so back-to-back
      // test runs never race a fixed port that the previous process
      // hasn't fully released yet (a real thing on Windows).
      'API_PORT': '0',
      'API_AUTH_TOKEN': _authToken,
      'API_GIT_PUSH': 'false',
    },
    // Windows resolves `dart` to dart.bat, which Process.start can only
    // find via a shell lookup - without this it fails with "the system
    // cannot find the file specified" even though `dart` is on PATH.
    runInShell: true,
  );

  final portCompleter = Completer<int>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    // Matches "...listening on 0.0.0.0:54321, catalog dir: ..." from
    // api_server.dart's own startup log line.
    final match = RegExp(r'listening on [^:]+:(\d+)').firstMatch(line);
    if (match != null && !portCompleter.isCompleted) {
      portCompleter.complete(int.parse(match.group(1)!));
    }
  });
  process.stderr.transform(utf8.decoder).listen((line) {
    // ignore: avoid_print
    print('[api_server stderr] $line');
  });

  final port = await portCompleter.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw StateError('api_server did not report a listening port within 30s'),
  );
  return _RunningServer(process, port);
}

void main() {
  late Directory catalogDir;
  late _RunningServer server;
  late CatalogApiClient client;

  setUp(() async {
    catalogDir = await Directory.systemTemp.createTemp('handles-api-client-itest-');
    server = await _startServer(catalogDir);
    client = CatalogApiClient(
      config: CatalogApiConfig(baseUrl: 'http://localhost:${server.port}', apiToken: _authToken),
    );
  });

  tearDown(() async {
    server.process.kill();
    await server.process.exitCode;
    await catalogDir.delete(recursive: true);
  });

  test('sync against a fresh server returns empty everything', () async {
    final result = await client.sync();

    expect(result.items, isEmpty);
    expect(result.events, isEmpty);
    expect(result.brandRiskEntries, isEmpty);
  });

  test('saveItem then sync round-trips a real catalog item over HTTP', () async {
    await client.saveItem(CatalogItem(
      sku: 'HND-ITEST-1',
      title: 'Integration Test Item',
      price: 42.5,
      quantity: 3,
      stores: {
        'ebay_test': StoreListingState(
          platform: 'ebay',
          externalListingId: 'l-1',
          syncStatus: SyncStatus.confirmed,
          lastConfirmedQuantity: 3,
        ),
      },
    ));

    final result = await client.sync();

    expect(result.items, hasLength(1));
    final item = result.items.single;
    expect(item.sku, 'HND-ITEST-1');
    expect(item.price, 42.5);
    expect(item.stores['ebay_test']?.lastConfirmedQuantity, 3,
        reason: 'v2 reconciliation fields survive the full JSON round trip too');
  });

  test('brand risk add/check/remove round-trips over HTTP', () async {
    await client.addBrandRiskEntry(
      BrandRiskEntry(brand: 'Nike', reason: 'Known VeRO enforcer', source: BrandRiskSource.curated),
    );

    final afterAdd = await client.sync();
    expect(afterAdd.brandRiskEntries, hasLength(1));
    expect(afterAdd.brandRiskEntries.single.brand, 'Nike');

    await client.removeBrandRiskEntry('Nike');
    final afterRemove = await client.sync();
    expect(afterRemove.brandRiskEntries, isEmpty);
  });

  test('a wrong API token is rejected with a real 401, not silently accepted', () async {
    final wrongClient = CatalogApiClient(
      config: CatalogApiConfig(baseUrl: 'http://localhost:${server.port}', apiToken: 'not-the-real-token'),
    );

    expect(() => wrongClient.sync(), throwsA(isA<CatalogSyncException>()));
  });
}
