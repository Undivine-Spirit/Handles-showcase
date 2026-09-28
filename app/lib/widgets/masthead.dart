import 'package:flutter/material.dart';

import '../theme/handles_colors.dart';
import '../theme/handles_theme.dart';

/// The zigzag "spray-stroke" underline from the mockup, done as a CustomPaint
/// (not a hand-authored SVG-style path chain) - a handful of triangle peaks,
/// one silver-bright fill.
class _ZigzagUnderline extends StatelessWidget {
  const _ZigzagUnderline();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(168, 9), painter: _ZigzagPainter());
  }
}

class _ZigzagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = HandlesColors.silverBright;
    final path = Path()..moveTo(0, size.height * 0.4);
    const peaks = 6;
    final step = size.width / peaks;
    for (var i = 0; i < peaks; i++) {
      final x1 = step * i + step * 0.5;
      final x2 = step * (i + 1);
      path.lineTo(x1, i.isEven ? 0 : size.height * 0.7);
      path.lineTo(x2, i.isEven ? size.height * 0.6 : size.height * 0.1);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ZigzagPainter oldDelegate) => false;
}

const List<String> mastheadTabs = ['Catalog', 'Shared Items'];

class Masthead extends StatelessWidget {
  const Masthead({super.key, required this.activeTab, this.onTabSelected, this.onSettingsTap});

  final String activeTab;

  /// Real navigation now, not a decorative label - tapping a tab calls
  /// this. `null` (e.g. a screen with nothing to switch between) just
  /// renders the tabs inert rather than crashing on a missing callback.
  final void Function(String tab)? onTabSelected;

  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 20,
      runSpacing: 16,
      children: [
        Transform.rotate(
          angle: -0.021, // -1.2deg, matches the mockup
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('HANDLES', style: HandlesText.stencil(fontSize: 56)),
              const SizedBox(height: 6),
              const _ZigzagUnderline(),
              const SizedBox(height: 8),
              Text(
                'INVENTORY & LISTING OPS',
                style: HandlesText.data(
                  fontSize: 13,
                  weight: FontWeight.w600,
                  color: HandlesColors.inkMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tab in mastheadTabs)
              _NavItem(
                label: tab,
                active: activeTab == tab,
                onTap: onTabSelected == null ? null : () => onTabSelected!(tab),
              ),
            const _GhostNavItem(label: 'Customer View — Soon'),
            if (onSettingsTap != null) _SettingsButton(onTap: onSettingsTap!),
            const _OpsBadge(),
          ],
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? HandlesColors.silverBright : Colors.transparent,
          border: Border.all(color: active ? HandlesColors.silverBright : Colors.transparent),
        ),
        child: Text(
          label.toUpperCase(),
          style: HandlesText.data(
            fontSize: 14,
            weight: FontWeight.w600,
            letterSpacing: 1,
            color: active ? HandlesColors.flairInk : HandlesColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _GhostNavItem extends StatelessWidget {
  const _GhostNavItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(border: Border.all(color: HandlesColors.borderStrong)),
      child: Text(
        label.toUpperCase(),
        style: HandlesText.data(fontSize: 14, weight: FontWeight.w600, color: HandlesColors.inkFaint),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(border: Border.all(color: Colors.transparent)),
        child: Icon(Icons.settings_outlined, size: 18, color: HandlesColors.inkMuted),
      ),
    );
  }
}

class _OpsBadge extends StatelessWidget {
  const _OpsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(border: Border.all(color: HandlesColors.silver)),
      child: Text(
        'OPS VIEW',
        style: HandlesText.data(
          fontSize: 11,
          weight: FontWeight.w700,
          color: HandlesColors.silverBright,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
