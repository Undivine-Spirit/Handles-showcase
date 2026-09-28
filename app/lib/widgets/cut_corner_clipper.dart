import 'package:flutter/widgets.dart';

/// Cuts one corner at 45 degrees, `size` logical pixels along each edge -
/// the "tag/ticket-stub" motif from the Handles Console mockup, used
/// instead of rounded corners throughout (a deliberate signage/industrial
/// identity choice, not an oversight).
class CutCornerClipper extends CustomClipper<Path> {
  const CutCornerClipper({this.corner = Corner.bottomLeft, this.size = 14});

  final Corner corner;
  final double size;

  @override
  Path getClip(Size viewport) {
    final w = viewport.width;
    final h = viewport.height;
    final path = Path();

    switch (corner) {
      case Corner.bottomLeft:
        path
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w, h)
          ..lineTo(size, h)
          ..lineTo(0, h - size)
          ..close();
      case Corner.topRight:
        path
          ..moveTo(0, 0)
          ..lineTo(w - size, 0)
          ..lineTo(w, size)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
    }

    return path;
  }

  @override
  bool shouldReclip(covariant CutCornerClipper oldClipper) {
    return oldClipper.corner != corner || oldClipper.size != size;
  }
}

enum Corner { bottomLeft, topRight }
