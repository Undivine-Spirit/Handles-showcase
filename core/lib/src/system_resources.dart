import 'dart:convert';
import 'dart:io';

/// A single point-in-time reading - deliberately minimal (two numbers),
/// not a full metrics system. `docs/PROJECT_PLAN.md` section 7's revised
/// note: this exists for the self-hosted daemon, which may genuinely run
/// on constrained hardware (a Raspberry Pi), not for the desktop app.
class SystemResourcesSnapshot {
  const SystemResourcesSnapshot({required this.memoryUsedPercent, required this.loadAverage1m});

  final double memoryUsedPercent;
  final double loadAverage1m;

  /// A simple, conservative signal - not a full scheduler. 90% memory
  /// used or a 1-minute load average above 4.0 (a reasonable "fully busy"
  /// line for a small quad-core board like a Raspberry Pi 4 - adjust if
  /// running on materially different hardware) means "skip this pass
  /// rather than push an already-strained device further."
  bool get isConstrained => memoryUsedPercent > 90 || loadAverage1m > 4.0;

  @override
  String toString() =>
      'memory=${memoryUsedPercent.toStringAsFixed(1)}% load1m=${loadAverage1m.toStringAsFixed(2)}';
}

abstract interface class SystemResourcesReader {
  Future<SystemResourcesSnapshot> read();
}

/// Parses Linux's `/proc/meminfo` and `/proc/loadavg` - always available
/// since the daemon runs inside a Linux container (`core/Dockerfile`)
/// regardless of the host OS. Not usable outside Linux (there's no
/// `/proc` on Windows/macOS) - that's fine, this reader is only ever
/// constructed by the daemon entrypoint, never by the Flutter app.
class ProcSystemResourcesReader implements SystemResourcesReader {
  @override
  Future<SystemResourcesSnapshot> read() async {
    final meminfoText = await File('/proc/meminfo').readAsString();
    final loadavgText = await File('/proc/loadavg').readAsString();
    return parseProcOutput(meminfoText: meminfoText, loadavgText: loadavgText);
  }
}

/// The actual parsing, pulled out as a plain function specifically so it's
/// testable on any platform (including this project's Windows dev
/// machine, which has no real `/proc` to read) by passing sample content
/// directly rather than needing real Linux files.
SystemResourcesSnapshot parseProcOutput({
  required String meminfoText,
  required String loadavgText,
}) {
  final values = <String, int>{};
  for (final line in const LineSplitter().convert(meminfoText)) {
    final match = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line);
    if (match != null) {
      values[match.group(1)!] = int.parse(match.group(2)!);
    }
  }

  final total = values['MemTotal'] ?? 1;
  final available = values['MemAvailable'] ?? total;
  final usedPercent = ((total - available) / total) * 100;

  final load1m = double.parse(loadavgText.trim().split(RegExp(r'\s+')).first);

  return SystemResourcesSnapshot(memoryUsedPercent: usedPercent, loadAverage1m: load1m);
}

/// For tests, or before a real reader is wired up - a fixed reading that
/// never blocks a pass unless told to.
class FakeSystemResourcesReader implements SystemResourcesReader {
  FakeSystemResourcesReader(this.snapshot);

  SystemResourcesSnapshot snapshot;

  @override
  Future<SystemResourcesSnapshot> read() async => snapshot;
}
