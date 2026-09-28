import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

const _sampleMeminfo = '''
MemTotal:        8000000 kB
MemFree:         1000000 kB
MemAvailable:    2000000 kB
Buffers:          150000 kB
Cached:          900000 kB
SwapTotal:       2000000 kB
SwapFree:        2000000 kB
''';

void main() {
  group('parseProcOutput', () {
    test('computes memory-used percent from MemTotal/MemAvailable, not MemFree', () {
      final snapshot = parseProcOutput(
        meminfoText: _sampleMeminfo,
        loadavgText: '0.50 0.60 0.55 2/456 12345',
      );

      // (8,000,000 - 2,000,000) / 8,000,000 = 75% used.
      expect(snapshot.memoryUsedPercent, closeTo(75, 0.01));
      expect(snapshot.loadAverage1m, closeTo(0.50, 0.001));
    });

    test('reads only the 1-minute load average, not the 5/15-minute figures', () {
      final snapshot = parseProcOutput(
        meminfoText: _sampleMeminfo,
        loadavgText: '3.21 1.00 0.10 4/500 99999',
      );

      expect(snapshot.loadAverage1m, closeTo(3.21, 0.001));
    });
  });

  group('SystemResourcesSnapshot.isConstrained', () {
    test('is false for a normal, lightly-loaded reading', () {
      const snapshot = SystemResourcesSnapshot(memoryUsedPercent: 40, loadAverage1m: 0.8);
      expect(snapshot.isConstrained, isFalse);
    });

    test('is true when memory usage crosses 90%, even with a light load average', () {
      const snapshot = SystemResourcesSnapshot(memoryUsedPercent: 95, loadAverage1m: 0.2);
      expect(snapshot.isConstrained, isTrue);
    });

    test('is true when the 1-minute load average exceeds 4.0, even with free memory', () {
      const snapshot = SystemResourcesSnapshot(memoryUsedPercent: 20, loadAverage1m: 5.0);
      expect(snapshot.isConstrained, isTrue);
    });
  });

  group('FakeSystemResourcesReader', () {
    test('returns whatever snapshot it was given, for driving tests elsewhere', () async {
      const snapshot = SystemResourcesSnapshot(memoryUsedPercent: 99, loadAverage1m: 10);
      final reader = FakeSystemResourcesReader(snapshot);

      expect(await reader.read(), same(snapshot));
    });
  });
}
