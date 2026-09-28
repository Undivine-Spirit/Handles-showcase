import 'package:flutter/material.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';
import 'cut_corner_clipper.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.figure,
    required this.subtitle,
    this.attention = false,
    this.sparkline,
  });

  final String label;
  final String figure;
  final String subtitle;
  final bool attention;
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final figureColor = attention ? HandlesColors.critical : HandlesColors.ink;

    return ClipPath(
      clipper: const CutCornerClipper(size: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: HandlesColors.surface,
          border: Border.all(
            color: attention ? HandlesColors.critical : HandlesColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: HandlesText.eyebrow()),
            const SizedBox(height: 4),
            Text(figure, style: HandlesText.stencil(fontSize: 40, color: figureColor)),
            if (sparkline != null) ...[
              const SizedBox(height: 4),
              SizedBox(height: 22, child: sparkline),
            ],
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: HandlesText.body(fontSize: 12.5, color: HandlesColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin bars, rounded data-ends, one hue (silver-bright) with opacity
/// stepping up toward the most recent value - a sparkline done to the
/// standard this project holds charts to (dataviz skill: thin marks,
/// rounded ends, a single sequential hue), not a decorative afterthought.
class MiniSparkline extends StatelessWidget {
  const MiniSparkline({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == values.length - 1 ? 0 : 3),
            child: Container(
              width: 6,
              height: 22 * values[i].clamp(0.05, 1.0),
              decoration: BoxDecoration(
                color: HandlesColors.silverBright
                    .withValues(alpha: i == values.length - 1 ? 1.0 : 0.7),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
      ],
    );
  }
}
