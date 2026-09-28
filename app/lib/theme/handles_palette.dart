import 'package:flutter/material.dart';
import 'package:handles_core/handles_core.dart';

/// One full set of the semantic colors the whole UI is built from - what
/// used to be `HandlesColors`'s hardcoded values, now a real value type so
/// it can be swapped at runtime (built-in preset, or a user's own from the
/// custom theme maker) instead of being "one committed world" forever.
///
/// Every built-in preset keeps the same *structure* the original Console
/// Navy mockup established - a dark instrument-panel field, a silver
/// accent, three status colors - just with different hues. None of the
/// presets go light: that was a deliberate call in the original mockup
/// ("a control panel doesn't have a daytime mode"), not an oversight, and
/// still holds. A user who wants something lighter can build it themselves
/// in the custom maker - that's what it's for.
@immutable
class HandlesPalette {
  const HandlesPalette({
    required this.id,
    required this.displayName,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.silver,
    required this.silverBright,
    required this.flairInk,
    required this.border,
    required this.borderStrong,
    required this.good,
    required this.warn,
    required this.critical,
  });

  final String id;
  final String displayName;

  final Color bg;
  final Color surface;
  final Color surfaceRaised;

  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  final Color silver;
  final Color silverBright;
  final Color flairInk;

  final Color border;
  final Color borderStrong;

  final Color good;
  final Color warn;
  final Color critical;

  /// The original mockup palette, unchanged - still the default for
  /// anyone who never opens the theme settings at all.
  static const consoleNavy = HandlesPalette(
    id: 'console_navy',
    displayName: 'Console Navy',
    bg: Color(0xFF0A1420),
    surface: Color(0xFF101D2E),
    surfaceRaised: Color(0xFF17273B),
    ink: Color(0xFFECF1F5),
    inkMuted: Color(0xFFA6B4C0),
    inkFaint: Color(0xFF71818E),
    silver: Color(0xFFB7C3CC),
    silverBright: Color(0xFFE4EAEF),
    flairInk: Color(0xFF0A1420),
    border: Color(0x47B7C3CC),
    borderStrong: Color(0x8CE4EAEF),
    good: Color(0xFF4FCB85),
    warn: Color(0xFFF0B23E),
    critical: Color(0xFFF0685F),
  );

  /// Neutral graphite/steel - same structure, hue pulled toward gray
  /// instead of navy for a cooler, less "screen glow" field.
  static const slateGraphite = HandlesPalette(
    id: 'slate_graphite',
    displayName: 'Slate Graphite',
    bg: Color(0xFF14171A),
    surface: Color(0xFF1D2226),
    surfaceRaised: Color(0xFF272E33),
    ink: Color(0xFFEDEFF1),
    inkMuted: Color(0xFFA9B0B6),
    inkFaint: Color(0xFF757D84),
    silver: Color(0xFFBCC4CA),
    silverBright: Color(0xFFE7EBEE),
    flairInk: Color(0xFF14171A),
    border: Color(0x47BCC4CA),
    borderStrong: Color(0x8CE7EBEE),
    good: Color(0xFF4FCB85),
    warn: Color(0xFFF0B23E),
    critical: Color(0xFFF0685F),
  );

  /// Dark green-tinted field - same instrument-panel structure, warmer/
  /// more organic accent than navy without abandoning the dark-only rule.
  static const deepForest = HandlesPalette(
    id: 'deep_forest',
    displayName: 'Deep Forest',
    bg: Color(0xFF0D1712),
    surface: Color(0xFF14231C),
    surfaceRaised: Color(0xFF1C3026),
    ink: Color(0xFFECF2ED),
    inkMuted: Color(0xFFA3B8AB),
    inkFaint: Color(0xFF6E8478),
    silver: Color(0xFFA9C4B2),
    silverBright: Color(0xFFDCEDE2),
    flairInk: Color(0xFF0D1712),
    border: Color(0x47A9C4B2),
    borderStrong: Color(0x8CDCEDE2),
    good: Color(0xFF4FCB85),
    warn: Color(0xFFF0B23E),
    critical: Color(0xFFF0685F),
  );

  /// Dark warm brown/amber-tinted field - the "different accent warmth"
  /// option, still civic-signage-dark, closer to aged brass than chrome.
  static const warmSignal = HandlesPalette(
    id: 'warm_signal',
    displayName: 'Warm Signal',
    bg: Color(0xFF1A1410),
    surface: Color(0xFF261D16),
    surfaceRaised: Color(0xFF332720),
    ink: Color(0xFFF2ECE5),
    inkMuted: Color(0xFFBBA98F),
    inkFaint: Color(0xFF8A7862),
    silver: Color(0xFFD8BE94),
    silverBright: Color(0xFFF0DFC0),
    flairInk: Color(0xFF1A1410),
    border: Color(0x47D8BE94),
    borderStrong: Color(0x8CF0DFC0),
    good: Color(0xFF4FCB85),
    warn: Color(0xFFF0B23E),
    critical: Color(0xFFF0685F),
  );

  static const builtIns = [consoleNavy, slateGraphite, deepForest, warmSignal];

  static HandlesPalette builtInById(String id) =>
      builtIns.firstWhere((p) => p.id == id, orElse: () => consoleNavy);

  /// Raw-ARGB-int map form for `HandlesSettings.customPaletteColors` - that
  /// model is pure Dart (no `dart:ui`), so this is the bridge in both
  /// directions.
  Map<String, int> toColorMap() => {
        'bg': bg.toARGB32(),
        'surface': surface.toARGB32(),
        'surfaceRaised': surfaceRaised.toARGB32(),
        'ink': ink.toARGB32(),
        'inkMuted': inkMuted.toARGB32(),
        'inkFaint': inkFaint.toARGB32(),
        'silver': silver.toARGB32(),
        'silverBright': silverBright.toARGB32(),
        'flairInk': flairInk.toARGB32(),
        'border': border.toARGB32(),
        'borderStrong': borderStrong.toARGB32(),
        'good': good.toARGB32(),
        'warn': warn.toARGB32(),
        'critical': critical.toARGB32(),
      };

  /// Builds from a raw color map, falling back to [consoleNavy]'s values
  /// for any role the map is missing - keeps a partially-built custom
  /// palette (e.g. mid-edit) from ever producing a transparent/invalid
  /// color instead of just looking temporarily unfinished.
  factory HandlesPalette.fromColorMap(Map<String, int> colors, {String displayName = 'Custom'}) {
    Color read(String key, Color fallback) =>
        colors.containsKey(key) ? Color(colors[key]!) : fallback;
    const base = consoleNavy;
    return HandlesPalette(
      id: 'custom',
      displayName: displayName,
      bg: read('bg', base.bg),
      surface: read('surface', base.surface),
      surfaceRaised: read('surfaceRaised', base.surfaceRaised),
      ink: read('ink', base.ink),
      inkMuted: read('inkMuted', base.inkMuted),
      inkFaint: read('inkFaint', base.inkFaint),
      silver: read('silver', base.silver),
      silverBright: read('silverBright', base.silverBright),
      flairInk: read('flairInk', base.flairInk),
      border: read('border', base.border),
      borderStrong: read('borderStrong', base.borderStrong),
      good: read('good', base.good),
      warn: read('warn', base.warn),
      critical: read('critical', base.critical),
    );
  }

  /// Resolves whichever palette [settings] currently selects - a built-in
  /// preset by [HandlesSettings.themeId], or the user's own custom one if
  /// `themeId == 'custom'` (falling back to Console Navy if "Custom" was
  /// selected but nothing's actually been built yet).
  static HandlesPalette resolve(HandlesSettings settings) {
    if (settings.themeId == 'custom') {
      final colors = settings.customPaletteColors;
      if (colors == null) return consoleNavy;
      return HandlesPalette.fromColorMap(colors);
    }
    return builtInById(settings.themeId);
  }

  HandlesPalette copyWith({
    String? id,
    String? displayName,
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? silver,
    Color? silverBright,
    Color? flairInk,
    Color? border,
    Color? borderStrong,
    Color? good,
    Color? warn,
    Color? critical,
  }) {
    return HandlesPalette(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      silver: silver ?? this.silver,
      silverBright: silverBright ?? this.silverBright,
      flairInk: flairInk ?? this.flairInk,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      critical: critical ?? this.critical,
    );
  }
}
