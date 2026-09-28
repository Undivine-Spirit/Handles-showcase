import 'package:flutter/material.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';

enum PillTone { confirmed, pending, conflict, delisted, approval }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone});

  final String label;
  final PillTone tone;

  Color get _dotColor => switch (tone) {
        PillTone.confirmed => HandlesColors.good,
        PillTone.pending => HandlesColors.warn,
        PillTone.conflict => HandlesColors.critical,
        PillTone.delisted => HandlesColors.inkFaint,
        PillTone.approval => HandlesColors.silver,
      };

  Color get _borderColor =>
      tone == PillTone.conflict ? HandlesColors.critical : HandlesColors.border;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
        decoration: BoxDecoration(border: Border.all(color: _borderColor)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(shape: BoxShape.circle, color: _dotColor),
            ),
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: HandlesText.data(fontSize: 11.5, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
