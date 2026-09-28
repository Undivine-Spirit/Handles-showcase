import 'package:flutter/material.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';
import 'cut_corner_clipper.dart';

/// Placeholder product thumbnail - initials on a brushed-silver gradient,
/// standing in for real product photography until the catalog schema
/// carries actual images end-to-end into the app.
class ItemSwatch extends StatelessWidget {
  const ItemSwatch({super.key, required this.title});

  final String title;

  String get _initials {
    final words = title.trim().split(RegExp(r'\s+'));
    final letters = words.take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const CutCornerClipper(size: 6),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [HandlesColors.silverBright, HandlesColors.silver],
          ),
        ),
        child: Text(
          _initials,
          style: HandlesText.data(
            fontSize: 12,
            weight: FontWeight.w700,
            color: HandlesColors.flairInk,
          ),
        ),
      ),
    );
  }
}
