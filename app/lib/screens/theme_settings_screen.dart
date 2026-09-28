import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/handles_colors.dart';
import '../theme/handles_palette.dart';
import '../theme/handles_theme.dart';
import '../widgets/handles_color_picker.dart';

/// The custom color theme maker, plus built-in preset switching - reached
/// from Settings → Theme. Every edit here applies and persists immediately
/// (through `AppState.updateSettings`, which is also what keeps
/// `HandlesColors`'s active palette in sync) rather than needing a
/// separate "Save" step, so this screen always shows exactly what's live.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  /// WCAG relative luminance - the standard formula, not an approximation.
  static double _relativeLuminance(Color c) {
    double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final r = channel(c.r);
    final g = channel(c.g);
    final b = channel(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white). 4.5 is
  /// the standard "normal text" AA threshold - used here rather than the
  /// 3.0 "large text" one since button labels in this app are ~14px, below
  /// WCAG's large-text cutoff even at bold weight.
  static double _contrastRatio(Color a, Color b) {
    final lA = _relativeLuminance(a);
    final lB = _relativeLuminance(b);
    final lighter = lA > lB ? lA : lB;
    final darker = lA > lB ? lB : lA;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static const _minContrast = 4.5;

  static const _roleGroups = [
    (
      title: 'Field & Surfaces',
      roles: [
        (key: 'bg', label: 'Background'),
        (key: 'surface', label: 'Panel Surface'),
        (key: 'surfaceRaised', label: 'Raised Panel'),
      ],
    ),
    (
      title: 'Text',
      roles: [
        (key: 'ink', label: 'Text'),
        (key: 'inkMuted', label: 'Muted Text'),
        (key: 'inkFaint', label: 'Faint Text'),
      ],
    ),
    (
      title: 'Accent',
      roles: [
        (key: 'silver', label: 'Accent'),
        (key: 'silverBright', label: 'Bright Accent'),
        (key: 'flairInk', label: 'Text on Accent'),
      ],
    ),
    (
      title: 'Borders',
      roles: [
        (key: 'border', label: 'Border'),
        (key: 'borderStrong', label: 'Strong Border'),
      ],
    ),
    (
      title: 'Status',
      roles: [
        (key: 'good', label: 'Success'),
        (key: 'warn', label: 'Warning'),
        (key: 'critical', label: 'Critical'),
      ],
    ),
  ];

  Color _colorForRole(HandlesPalette palette, String key) => switch (key) {
        'bg' => palette.bg,
        'surface' => palette.surface,
        'surfaceRaised' => palette.surfaceRaised,
        'ink' => palette.ink,
        'inkMuted' => palette.inkMuted,
        'inkFaint' => palette.inkFaint,
        'silver' => palette.silver,
        'silverBright' => palette.silverBright,
        'flairInk' => palette.flairInk,
        'border' => palette.border,
        'borderStrong' => palette.borderStrong,
        'good' => palette.good,
        'warn' => palette.warn,
        'critical' => palette.critical,
        _ => palette.ink,
      };

  Future<void> _selectBuiltIn(AppState appState, HandlesPalette preset) {
    return appState.updateSettings(appState.settings.copyWith(themeId: preset.id));
  }

  /// Seeds a brand-new custom palette from [source]'s colors and switches
  /// to it - the easy on-ramp so "customize" never means starting from 14
  /// blank swatches.
  Future<void> _startCustomFrom(AppState appState, HandlesPalette source) {
    return appState.updateSettings(appState.settings.copyWith(
      themeId: 'custom',
      customPaletteColors: source.toColorMap(),
    ));
  }

  Future<void> _editRole(BuildContext context, AppState appState, HandlesPalette custom, String roleKey, String roleLabel) async {
    final picked = await showHandlesColorPicker(
      context: context,
      title: roleLabel,
      initial: _colorForRole(custom, roleKey),
    );
    if (picked == null) return;

    final nextColors = {...custom.toColorMap(), roleKey: picked.toARGB32()};
    await appState.updateSettings(appState.settings.copyWith(
      themeId: 'custom',
      customPaletteColors: nextColors,
    ));
  }

  /// One-tap fix for the "Bright Accent"/"Text on Accent" pair - flips
  /// [roleKey] to pure black or white, whichever contrasts better against
  /// [against]. A real bug report drove this: those two roles are edited
  /// as independent swatches with no relationship enforced, so a user can
  /// (and one did) pick two similarly-bright values and end up with
  /// unreadable button text - see `_contrastWarning` below.
  Future<void> _fixContrast(
    BuildContext context,
    AppState appState,
    HandlesPalette custom,
    String roleKey,
    Color against,
  ) async {
    final fixed = _contrastRatio(against, Colors.black) >= _contrastRatio(against, Colors.white)
        ? Colors.black
        : Colors.white;
    final nextColors = {...custom.toColorMap(), roleKey: fixed.toARGB32()};
    await appState.updateSettings(appState.settings.copyWith(
      themeId: 'custom',
      customPaletteColors: nextColors,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final settings = appState.settings;
    final isCustomActive = settings.themeId == 'custom';
    // The palette the Custom section edits - the user's saved custom
    // colors if they have any, else whichever built-in is currently
    // active (so "Customize" always starts from something real on screen,
    // never an arbitrary default).
    final customBase = settings.customPaletteColors != null
        ? HandlesPalette.fromColorMap(settings.customPaletteColors!)
        : HandlesPalette.resolve(settings);

    return Scaffold(
      backgroundColor: HandlesColors.bg,
      appBar: AppBar(
        backgroundColor: HandlesColors.bg,
        elevation: 0,
        title: Text('Theme', style: HandlesText.stencil(fontSize: 28)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('PRESETS', style: HandlesText.eyebrow()),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final preset in HandlesPalette.builtIns)
                    _PresetCard(
                      palette: preset,
                      selected: !isCustomActive && settings.themeId == preset.id,
                      onTap: () => _selectBuiltIn(appState, preset),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('CUSTOM', style: HandlesText.eyebrow()),
                  const SizedBox(width: 10),
                  if (isCustomActive)
                    Text('· active', style: HandlesText.data(fontSize: 11.5, color: HandlesColors.good)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tap any swatch below to open the picker - every change applies immediately and '
                'switches the active theme to Custom.',
                style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in HandlesPalette.builtIns)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: HandlesColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => _startCustomFrom(appState, preset),
                      child: Text(
                        'Start from ${preset.displayName}',
                        style: HandlesText.data(fontSize: 11.5, color: HandlesColors.inkMuted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final group in _roleGroups) ...[
                Container(
                  decoration: BoxDecoration(
                    color: HandlesColors.surface,
                    border: Border.all(color: HandlesColors.border),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: HandlesColors.border)),
                        ),
                        child: Text(
                          group.title,
                          style: HandlesText.body(fontSize: 13.5, weight: FontWeight.w700),
                        ),
                      ),
                      for (final role in group.roles) ...[
                        _RoleRow(
                          label: role.label,
                          color: _colorForRole(customBase, role.key),
                          onTap: () => _editRole(context, appState, customBase, role.key, role.label),
                        ),
                        // "Text on Accent" and "Bright Accent" are edited as
                        // two independent swatches (see class doc) but are
                        // always used together on buttons - warn here
                        // rather than let it silently ship unreadable.
                        if (role.key == 'flairInk' &&
                            _contrastRatio(customBase.silverBright, customBase.flairInk) < _minContrast)
                          _ContrastWarning(
                            onFix: () =>
                                _fixContrast(context, appState, customBase, 'flairInk', customBase.silverBright),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.palette, required this.selected, required this.onTap});

  final HandlesPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: selected ? palette.silverBright : HandlesColors.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 32, color: palette.bg),
            const SizedBox(height: 8),
            Row(
              children: [
                _Swatch(color: palette.silverBright),
                const SizedBox(width: 4),
                _Swatch(color: palette.good),
                const SizedBox(width: 4),
                _Swatch(color: palette.warn),
                const SizedBox(width: 4),
                _Swatch(color: palette.critical),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              palette.displayName,
              style: HandlesText.data(fontSize: 12.5, weight: FontWeight.w700, color: palette.ink),
            ),
            if (selected)
              Text('ACTIVE', style: HandlesText.eyebrow(fontSize: 10, color: palette.silverBright)),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 14, height: 14, color: color);
  }
}

class _ContrastWarning extends StatelessWidget {
  const _ContrastWarning({required this.onFix});
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: HandlesColors.warn)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: HandlesColors.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Low contrast against Bright Accent - button text may be hard to read.',
              style: HandlesText.body(fontSize: 12, color: HandlesColors.warn),
            ),
          ),
          TextButton(
            onPressed: onFix,
            child: Text('FIX', style: HandlesText.data(fontSize: 12, weight: FontWeight.w700, color: HandlesColors.warn)),
          ),
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: HandlesText.body(fontSize: 13.5))),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: color, border: Border.all(color: HandlesColors.border)),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, size: 18, color: HandlesColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
