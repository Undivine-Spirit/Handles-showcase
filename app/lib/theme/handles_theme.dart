import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'handles_colors.dart';

/// Text styles for the two civic-signage faces from the mockup - Big
/// Shoulders Stencil (Chicago signage lineage) for display/numerals, and
/// Barlow / Barlow Condensed (California license-plate lineage) for
/// everything else. Stencil is deliberately reserved for large sizes only
/// - stencil letterforms have gaps that hurt legibility at small sizes.
abstract final class HandlesText {
  static TextStyle stencil({double fontSize = 32, Color? color}) {
    return GoogleFonts.bigShouldersStencilDisplay(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: fontSize * 0.01,
      height: 0.9,
      color: color ?? HandlesColors.ink,
    );
  }

  static TextStyle body({
    double fontSize = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) {
    return GoogleFonts.barlow(
      fontSize: fontSize,
      fontWeight: weight,
      color: color ?? HandlesColors.ink,
    );
  }

  static TextStyle data({
    double fontSize = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.barlowCondensed(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color ?? HandlesColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle eyebrow({double fontSize = 11.5, Color? color}) {
    return data(
      fontSize: fontSize,
      weight: FontWeight.w600,
      color: color ?? HandlesColors.inkFaint,
      letterSpacing: fontSize * 0.1,
    );
  }
}

ThemeData buildHandlesTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HandlesColors.bg,
    colorScheme: ColorScheme.dark(
      surface: HandlesColors.surface,
      primary: HandlesColors.silverBright,
      onPrimary: HandlesColors.flairInk,
      error: HandlesColors.critical,
    ),
    fontFamily: GoogleFonts.barlow().fontFamily,
    textTheme: GoogleFonts.barlowTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: HandlesColors.ink,
      displayColor: HandlesColors.ink,
    ),
    dividerColor: HandlesColors.border,
    focusColor: HandlesColors.silverBright,
  );

  return base.copyWith(
    visualDensity: VisualDensity.standard,
  );
}
