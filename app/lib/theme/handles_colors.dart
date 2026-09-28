import 'package:flutter/material.dart';

import 'handles_palette.dart';

/// The active semantic colors for the whole UI - every call site
/// (`HandlesColors.bg`, `HandlesColors.silverBright`, ...) is unchanged
/// from when these were `static const` values baked to the Console Navy
/// mockup; only the backing storage changed, to a mutable [HandlesPalette]
/// that [setActive] can swap at runtime (a built-in preset, or a user's
/// own from the custom theme maker in Settings).
///
/// Because these are no longer compile-time constants, any `const`
/// constructor that used to embed one of these values directly (a `const
/// BoxDecoration(color: HandlesColors.border)`, say) had to drop the
/// `const` - the analyzer finds every one of those for free, which is how
/// this migration was actually done, not by hunting for them by hand.
abstract final class HandlesColors {
  static HandlesPalette _active = HandlesPalette.consoleNavy;

  static HandlesPalette get active => _active;

  static void setActive(HandlesPalette palette) {
    _active = palette;
  }

  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get surfaceRaised => _active.surfaceRaised;

  static Color get ink => _active.ink;
  static Color get inkMuted => _active.inkMuted;
  static Color get inkFaint => _active.inkFaint;

  static Color get silver => _active.silver;
  static Color get silverBright => _active.silverBright;
  static Color get flairInk => _active.flairInk;

  static Color get border => _active.border;
  static Color get borderStrong => _active.borderStrong;

  static Color get good => _active.good;
  static Color get warn => _active.warn;
  static Color get critical => _active.critical;
}
