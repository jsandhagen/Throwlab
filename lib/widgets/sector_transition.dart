/// Going from one screen to the next along the sector's own lines.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's page transition: the next screen is opened out of the
/// throwing circle, the way a sector opens out of one.
///
/// Two sector lines leave the bottom of the screen together and swing
/// apart, and the new screen is what is between them. They come to rest a
/// moment at the real sector — 34.92°, the angle every line the app draws
/// on a field is struck at — with a few distance arcs across it, and then
/// carry on out until the new screen is all of it. Going back is the same
/// thing closing.
///
/// Installed once in the theme, like everything else about how the app
/// looks: screens push a [MaterialPageRoute] and get it.
class SectorPageTransitionsBuilder extends PageTransitionsBuilder {
  const SectorPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 520);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      SectorReveal(animation: animation, child: child);
}

/// [child] revealed between two sector lines as [animation] runs 0 to 1.
class SectorReveal extends StatelessWidget {
  const SectorReveal({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  /// Half the sector, which is where the lines pause.
  static const sectorHalf = 34.92 / 2 * math.pi / 180;

  /// How far the lines have swung apart, as a half-angle, at [t]. The
  /// first stretch opens them to the sector and eases into it, so it reads
  /// as a sector rather than as a line passing through one; the rest opens
  /// them past square, which is what covers the bottom corners.
  static double halfAngleAt(double t) {
    const rest = 0.4;
    if (t <= rest) {
      return sectorHalf * Curves.easeOutCubic.transform(t / rest);
    }
    final p = Curves.easeInCubic.transform((t - rest) / (1 - rest));
    return sectorHalf + (math.pi / 2 + 0.05 - sectorHalf) * p;
  }

  @override
  Widget build(BuildContext context) {
    final lines = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        // At rest the page is the page: no clip to pay for on every frame
        // of a scroll, and nothing drawn over it.
        if (t >= 1) return child!;
        final half = halfAngleAt(t);
        return Stack(
          fit: StackFit.passthrough,
          children: [
            ClipPath(clipper: _SectorClipper(half), child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SectorEdgePainter(half: half, t: t, color: lines),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The circle, for the whole transition: the middle of the bottom edge,
/// which is where a phone held at a ring puts it.
Offset _circleOf(Size size) => Offset(size.width / 2, size.height);

/// The wedge between two lines leaving the circle at ±[half] off straight
/// up, long enough to reach past every corner.
Path _wedge(Size size, double half) {
  final circle = _circleOf(size);
  final reach = size.longestSide * 2;
  Offset out(double angle) =>
      circle + Offset(math.sin(angle), -math.cos(angle)) * reach;
  return Path()
    ..moveTo(circle.dx, circle.dy)
    ..lineTo(out(-half).dx, out(-half).dy)
    // Round the far side rather than straight across it: past a quarter
    // turn the two ends are below the circle, and a chord between them
    // would cut the top of the screen off.
    ..arcTo(Rect.fromCircle(center: circle, radius: reach),
        -math.pi / 2 - half, 2 * half, false)
    ..close();
}

class _SectorClipper extends CustomClipper<Path> {
  const _SectorClipper(this.half);

  final double half;

  @override
  Path getClip(Size size) => _wedge(size, half);

  @override
  bool shouldReclip(_SectorClipper old) => old.half != half;
}

/// The two lines, and the distance arcs struck across the sector while it
/// is still one.
class _SectorEdgePainter extends CustomPainter {
  const _SectorEdgePainter({
    required this.half,
    required this.t,
    required this.color,
  });

  final double half;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (half <= 0) return;
    final circle = _circleOf(size);
    // Bright while they are the sector, gone by the time they reach the
    // edges: a line left standing at the side of the screen is a border.
    final fade = (1 - (t - 0.4) / 0.6).clamp(0.0, 1.0);
    final reach = size.longestSide * 2;
    final line = Paint()
      ..strokeWidth = 1.4
      ..color = color.withOpacity(0.9 * fade);
    for (final sign in [-1, 1]) {
      final angle = sign * half;
      canvas.drawLine(circle,
          circle + Offset(math.sin(angle), -math.cos(angle)) * reach, line);
    }

    // Three distance arcs, like the sector backdrop's, struck as the lines
    // come to rest and fading as they open again. Inside the lines only: an
    // arc outside them is a line no throwing field has.
    final arcs = (t < 0.4 ? t / 0.4 : fade).clamp(0.0, 1.0);
    if (arcs == 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withOpacity(0.35 * arcs);
    for (final at in const [0.3, 0.55, 0.8]) {
      canvas.drawArc(
        Rect.fromCircle(center: circle, radius: size.height * at),
        -math.pi / 2 - half,
        2 * half,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_SectorEdgePainter old) =>
      old.half != half || old.t != t || old.color != color;
}
