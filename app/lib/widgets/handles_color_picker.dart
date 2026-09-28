import 'package:flutter/material.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';

/// A real color picker - hue/saturation/lightness/opacity sliders plus a
/// hex field, bidirectionally synced, with a live swatch - for the custom
/// theme maker (Settings → Theme → Customize). Returns the picked [Color]
/// on "Use This Color", or `null` if cancelled.
Future<Color?> showHandlesColorPicker({
  required BuildContext context,
  required String title,
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorPickerDialog(title: title, initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSLColor _hsl;
  late double _alpha;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsl = HSLColor.fromColor(widget.initial.withValues(alpha: 1));
    _alpha = widget.initial.a;
    _hex = TextEditingController(text: _hexOf(_current));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _current => _hsl.toColor().withValues(alpha: _alpha);

  static String _hexOf(Color c) {
    String byte(double component) => (component * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${byte(c.a)}${byte(c.r)}${byte(c.g)}${byte(c.b)}'.toUpperCase();
  }

  void _applyHsl(HSLColor next) {
    setState(() {
      _hsl = next;
      _hex.text = _hexOf(_current);
    });
  }

  void _applyAlpha(double next) {
    setState(() {
      _alpha = next;
      _hex.text = _hexOf(_current);
    });
  }

  void _onHexSubmitted(String text) {
    var t = text.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length == 6) t = 'FF$t'; // no alpha given - assume fully opaque
    if (t.length != 8) return;
    final value = int.tryParse(t, radix: 16);
    if (value == null) return;

    final color = Color(value);
    setState(() {
      _hsl = HSLColor.fromColor(color.withValues(alpha: 1));
      _alpha = color.a;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: HandlesColors.surfaceRaised,
      title: Text(widget.title, style: HandlesText.body(fontSize: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Checkerboard-free live swatch - a plain filled box is enough
            // to judge hue/lightness; opacity is legible from the hex/alpha
            // slider instead of needing a transparency backdrop here.
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _current,
                border: Border.all(color: HandlesColors.border),
              ),
            ),
            const SizedBox(height: 14),
            _SliderRow(
              label: 'Hue',
              value: _hsl.hue,
              max: 360,
              display: _hsl.hue.round().toString(),
              onChanged: (v) => _applyHsl(_hsl.withHue(v)),
            ),
            _SliderRow(
              label: 'Saturation',
              value: _hsl.saturation,
              max: 1,
              display: '${(_hsl.saturation * 100).round()}%',
              onChanged: (v) => _applyHsl(_hsl.withSaturation(v)),
            ),
            _SliderRow(
              label: 'Lightness',
              value: _hsl.lightness,
              max: 1,
              display: '${(_hsl.lightness * 100).round()}%',
              onChanged: (v) => _applyHsl(_hsl.withLightness(v)),
            ),
            _SliderRow(
              label: 'Opacity',
              value: _alpha,
              max: 1,
              display: '${(_alpha * 100).round()}%',
              onChanged: _applyAlpha,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('HEX', style: HandlesText.eyebrow()),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    style: HandlesText.data(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(borderSide: BorderSide(color: HandlesColors.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: _onHexSubmitted,
                    onEditingComplete: () => _onHexSubmitted(_hex.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: HandlesText.data(fontSize: 13, color: HandlesColors.inkMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: Text(
            'USE THIS COLOR',
            style: HandlesText.data(fontSize: 13, weight: FontWeight.w700, color: HandlesColors.silverBright),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: HandlesText.data(fontSize: 12.5, color: HandlesColors.inkMuted)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            activeColor: HandlesColors.silverBright,
            inactiveColor: HandlesColors.border,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: HandlesText.data(fontSize: 12, color: HandlesColors.inkFaint),
          ),
        ),
      ],
    );
  }
}
