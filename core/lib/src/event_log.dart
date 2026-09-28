import 'dart:convert';
import 'dart:io';

enum EventSeverity {
  info,
  warning,

  /// Needs a human, not just visibility - what the duty-reminder system
  /// (`docs/PROJECT_PLAN.md` section 11) actually watches for. Distinct
  /// from [warning] on purpose: a warning is "worth knowing," this is
  /// "worth interrupting someone."
  actionNeeded,
  error;

  static EventSeverity fromJson(String value) => switch (value) {
        'info' => EventSeverity.info,
        'warning' => EventSeverity.warning,
        'action_needed' => EventSeverity.actionNeeded,
        'error' => EventSeverity.error,
        _ => throw ArgumentError('Unknown event severity: $value'),
      };

  String toJson() => switch (this) {
        EventSeverity.info => 'info',
        EventSeverity.warning => 'warning',
        EventSeverity.actionNeeded => 'action_needed',
        EventSeverity.error => 'error',
      };
}

/// One row in the structured event log - `docs/PROJECT_PLAN.md` section 8.
/// Deliberately flat/simple (a handful of fields, not a generic
/// "attributes" bag) so both the log viewer and the reminder evaluator can
/// read it without knowing about every possible action type in advance.
class HandlesEvent {
  HandlesEvent({
    required this.timestamp,
    required this.severity,
    required this.source,
    required this.message,
    this.sku,
    this.accountKey,
  });

  factory HandlesEvent.fromJson(Map<String, dynamic> json) => HandlesEvent(
        timestamp: DateTime.parse(json['timestamp'] as String),
        severity: EventSeverity.fromJson(json['severity'] as String),
        source: json['source'] as String,
        message: json['message'] as String,
        sku: json['sku'] as String?,
        accountKey: json['account_key'] as String?,
      );

  final DateTime timestamp;
  final EventSeverity severity;

  /// Which subsystem logged this - e.g. `'reconciliation'`,
  /// `'sourcing_monitor'`, `'daemon'` - not a free-for-all string, but not
  /// a closed enum either, since new subsystems will keep showing up.
  final String source;

  final String message;
  final String? sku;
  final String? accountKey;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'severity': severity.toJson(),
        'source': source,
        'message': message,
        if (sku != null) 'sku': sku,
        if (accountKey != null) 'account_key': accountKey,
      };
}

/// Appends to, and reads back, a JSON-lines event log file - one JSON
/// object per line, per section 8's "SQLite table or JSON lines" choice.
/// JSON lines over SQLite: no new dependency, trivially diffable/greppable,
/// and this project already reads/writes plain JSON everywhere else
/// (`CatalogRepository`, `FileCredentialStore`) - consistent, not a new
/// pattern to learn.
class EventLogStore {
  EventLogStore(this.logFile);

  final File logFile;

  Future<void> append(HandlesEvent event) async {
    await logFile.parent.create(recursive: true);
    await logFile.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
    );
  }

  /// Most recent first. [limit] caps how many are returned - a log file
  /// can grow large, and callers (an activity panel, a reminder scan)
  /// rarely need the whole history.
  Future<List<HandlesEvent>> readRecent({int limit = 50}) async {
    if (!await logFile.exists()) return [];

    final lines = await logFile.readAsLines();
    final events = lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => HandlesEvent.fromJson(jsonDecode(line) as Map<String, dynamic>))
        .toList();

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.take(limit).toList();
  }
}
