import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:handles_core/handles_core.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native OS notifications for anything the event log marks as needing a
/// human - `docs/PROJECT_PLAN.md` section 11's duty reminders, the actual
/// "interrupt someone" half of the event log (section 8) rather than a
/// row that only shows up if someone happens to check the dashboard.
///
/// Two backends behind one interface, not one package covering both
/// platforms - `flutter_local_notifications` (checked against the
/// resolved 18.0.1 source) only ships Android/iOS/macOS/Linux channels,
/// no Windows one, so Windows goes through `local_notifier` instead
/// (a thin wrapper over the real Windows toast/shortcut APIs). Callers
/// still only ever see [notify]/[notifyForEvent] - which backend runs
/// is this class's problem, not theirs.
class ReminderService {
  ReminderService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      // Android 13+ requires this at runtime, not just the manifest
      // declaration - a no-op on older versions.
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isWindows) {
      await localNotifier.setup(
        appName: 'Handles',
        // Require a Start Menu shortcut with a matching AUMI, creating
        // one if it's missing - Windows won't show toasts without it.
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    }

    _initialized = true;
  }

  Future<void> notify({required String title, required String body}) async {
    await init();

    if (Platform.isAndroid) {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'handles_duty_reminders',
            'Duty reminders',
            channelDescription: 'Things Handles found that need your attention',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } else if (Platform.isWindows) {
      final notification = LocalNotification(title: title, body: body);
      await notification.show();
    }
    // Any other platform: silently a no-op, see [remindersSupportedOnThisPlatform].
  }

  /// Turns one [HandlesEvent] into a notification, if its severity
  /// actually warrants interrupting someone - not every event does, see
  /// [EventSeverity.actionNeeded]'s own doc comment.
  Future<void> notifyForEvent(HandlesEvent event) async {
    if (event.severity != EventSeverity.actionNeeded && event.severity != EventSeverity.error) {
      return;
    }
    final subject = event.sku ?? event.accountKey ?? event.source;
    await notify(title: 'Handles: $subject needs attention', body: event.message);
  }

  final ReminderCursor _cursor = ReminderCursor();

  /// The real trigger path: called after every catalog sync with whatever
  /// the event log currently holds. Only fires for events newer than the
  /// last one this device already turned into a notification - a fresh
  /// device's very first sync catches up on the cursor silently instead
  /// of firing a notification storm for everything that happened before
  /// it started watching.
  Future<void> notifyForNewEvents(List<HandlesEvent> events) async {
    if (events.isEmpty) return;

    final sorted = [...events]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final since = await _cursor.read();

    if (since == null) {
      await _cursor.advance(sorted.last.timestamp);
      return;
    }

    final fresh = sorted.where((e) => e.timestamp.isAfter(since)).toList();
    for (final event in fresh) {
      await notifyForEvent(event);
    }
    if (fresh.isNotEmpty) {
      await _cursor.advance(fresh.last.timestamp);
    }
  }
}

/// Bookmarks the newest event timestamp already turned into a
/// notification. Backed directly by `shared_preferences`, not
/// `CredentialStore` - this isn't a secret, just a cursor, same reasoning
/// as `SharedPrefsSettingsStore`.
class ReminderCursor {
  static const _key = 'handles.reminders.last_notified_at';

  Future<DateTime?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> advance(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, timestamp.toIso8601String());
  }
}

/// Whether this platform is one [ReminderService] actually has a working
/// backend for - guards callers that might run on a target this project
/// doesn't otherwise build for.
bool get remindersSupportedOnThisPlatform => Platform.isWindows || Platform.isAndroid;
