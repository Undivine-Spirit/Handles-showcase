import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';

enum LogTone { good, warn, crit, info }

class LogEntry {
  const LogEntry({required this.time, required this.tone, required this.text});

  final String time;
  final LogTone tone;
  final String text;
}

/// The real event log (PROJECT_PLAN.md section 8) - `.events.jsonl`
/// inside the synced catalog repo, written by the reconciliation daemon.
/// Empty rather than sample data when there's nothing to show yet: a
/// fabricated "confirmed in sync" row here would look exactly like a real
/// automated action that never happened, which cuts against this app's
/// own "feel good, not just look good" standard.
class ActivityLogPanel extends StatelessWidget {
  const ActivityLogPanel({super.key, required this.events});

  final List<HandlesEvent> events;

  LogTone _toneFor(EventSeverity severity) => switch (severity) {
        EventSeverity.info => LogTone.info,
        EventSeverity.warning => LogTone.warn,
        EventSeverity.actionNeeded => LogTone.crit,
        EventSeverity.error => LogTone.crit,
      };

  String _timeFor(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Color _dotColor(LogTone tone) => switch (tone) {
        LogTone.good => HandlesColors.good,
        LogTone.warn => HandlesColors.warn,
        LogTone.crit => HandlesColors.critical,
        LogTone.info => HandlesColors.silver,
      };

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final event in events)
        LogEntry(
          time: _timeFor(event.timestamp),
          tone: _toneFor(event.severity),
          text: event.sku != null ? '${event.sku} — ${event.message}' : event.message,
        ),
    ];

    return _RailPanel(
      title: 'Activity',
      child: entries.isEmpty
          ? Text(
              'No activity yet - connect a catalog repository in Settings and sync to see '
              'reconciliation history here.',
              style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries) _LogRow(entry: entry, dotColor: _dotColor(entry.tone)),
              ],
            ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.dotColor});

  final LogEntry entry;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              entry.time,
              style: HandlesText.data(
                fontSize: 12,
                weight: FontWeight.w600,
                color: HandlesColors.inkFaint,
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 8, top: 5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          Expanded(
            child: Text(
              entry.text,
              style: HandlesText.body(fontSize: 13, color: HandlesColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Real battery/power state via `battery_plus` (Windows + Android both
/// supported). CPU/RAM stay unimplemented on purpose rather than faked -
/// no cross-platform Flutter package for that was settled on yet; a
/// caption says so instead of a meter showing a number that isn't real.
/// This app doesn't run its own background sync loop (that's the
/// self-hosted daemon's job, `docs/PROJECT_PLAN.md` section 10), so this
/// panel is informational for now, not yet driving any scheduling
/// decision the way section 7 originally envisioned for the app itself.
class HardwarePanel extends StatefulWidget {
  const HardwarePanel({super.key});

  @override
  State<HardwarePanel> createState() => _HardwarePanelState();
}

class _HardwarePanelState extends State<HardwarePanel> {
  final Battery _battery = Battery();
  int? _batteryLevel;
  BatteryState? _batteryState;
  StreamSubscription<BatteryState>? _subscription;

  @override
  void initState() {
    super.initState();
    _refreshLevel();
    _subscription = _battery.onBatteryStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _batteryState = state);
      _refreshLevel();
    });
  }

  Future<void> _refreshLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _batteryLevel = level);
    } catch (_) {
      // Some hosts (a desktop with no battery at all) may not support
      // this - leave it null rather than crash the panel over it.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCharging =
        _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    final powerLabel = _batteryState == null || _batteryState == BatteryState.unknown
        ? 'Reading power state…'
        : isCharging
            ? 'Plugged in · syncing aggressively'
            : 'On battery · syncing conservatively';

    return _RailPanel(
      title: 'Hardware',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MeterRow(
            label: 'Battery',
            percent: _batteryLevel ?? 0,
            color: HandlesColors.silverBright,
          ),
          const SizedBox(height: 10),
          Text(
            'CPU/RAM monitoring not wired up yet.',
            style: HandlesText.body(fontSize: 11.5, color: HandlesColors.inkFaint),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: HandlesColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Power state',
                  style: HandlesText.data(fontSize: 12.5, color: HandlesColors.inkMuted),
                ),
                Text(
                  powerLabel,
                  style: HandlesText.data(
                    fontSize: 12.5,
                    weight: FontWeight.w700,
                    color: isCharging ? HandlesColors.good : HandlesColors.warn,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.label, required this.percent, required this.color});

  final String label;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: HandlesText.data(fontSize: 12.5, color: HandlesColors.inkMuted, letterSpacing: 0.5),
            ),
            Text(
              '$percent%',
              style: HandlesText.data(fontSize: 12.5, color: HandlesColors.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          child: Row(
            children: List.generate(10, (i) {
              final filled = i < (percent / 10).round();
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 9 ? 0 : 2),
                  color: filled ? color : HandlesColors.border,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _RailPanel extends StatelessWidget {
  const _RailPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HandlesColors.surface,
        border: Border.all(color: HandlesColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: HandlesColors.border)),
            ),
            child: Text(
              title,
              style: HandlesText.body(fontSize: 17, weight: FontWeight.w700),
            ),
          ),
          Padding(padding: const EdgeInsets.all(18), child: child),
        ],
      ),
    );
  }
}
