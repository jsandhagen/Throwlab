import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/meet_board.dart';
import '../models/throw_event.dart';
import 'gold.dart';
import 'throw_card.dart';

/// The competition drawn on the sector: a line across it for each mark that
/// matters, the way a televised final paints them on the grass.
///
/// A standings table answers who is winning. This answers the question a
/// coach is actually asking from behind the cage — how far past the leader
/// their athlete has to land, and whether that is a stride or a throw.
///
/// The sector is drawn to its real angle for the event, but the *distances*
/// are not to scale: the board shows only the stretch the competition is
/// being decided in, because a sector drawn honestly from the circle stacks
/// the whole thing into the last few percent of its length, where three
/// marks a meter apart are three marks on top of each other. Every line
/// carries its own distance, so nothing about that is left to be guessed.
class SectorBoard extends StatelessWidget {
  const SectorBoard({
    super.key,
    required this.board,
    required this.event,
    required this.accent,
    this.backdrop,
  });

  final MeetBoard board;
  final ThrowEvent event;

  /// The event's color, which the athlete in the circle is drawn in.
  final Color accent;

  /// What the board is sitting on, used behind the names. The surface when
  /// nobody says.
  final Color? backdrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Takes whatever room it is given — a board is worth the whole screen
    // between attempts, and the caller is the one that knows how much of it
    // there is.
    return CustomPaint(
      size: Size.infinite,
      painter: _SectorBoardPainter(
        board: board,
        halfAngle: event.sectorHalfAngleDeg * math.pi / 180,
        accent: accent,
        grass: theme.colorScheme.primary,
        line: theme.colorScheme.outlineVariant,
        faint: theme.colorScheme.onSurfaceVariant,
        // What a name is set on. The card behind the board is opaque, so a
        // label can be lifted off the lines it crosses without the screen's
        // own sector art showing through the middle of it.
        backdrop: backdrop ?? theme.colorScheme.surface,
        // Off the theme rather than built here: the app names its type
        // once, and a bare TextStyle paints in the platform default.
        text: theme.textTheme.labelSmall ?? const TextStyle(),
      ),
    );
  }
}

class _SectorBoardPainter extends CustomPainter {
  const _SectorBoardPainter({
    required this.board,
    required this.halfAngle,
    required this.accent,
    required this.grass,
    required this.line,
    required this.faint,
    required this.backdrop,
    required this.text,
  });

  final MeetBoard board;

  /// Half the sector, in radians.
  final double halfAngle;

  final Color accent;

  /// What the sector itself is drawn in.
  final Color grass;
  final Color line;
  final Color faint;

  /// What a name is set on, so it reads over whatever it crosses.
  final Color backdrop;

  final TextStyle text;

  /// Room above the furthest line for its label, and below the nearest one
  /// so it doesn't sit on the bottom edge.
  static const _topPad = 30.0;
  static const _bottomPad = 14.0;

  /// How much of the box the sector spans at its far edge. Short of the
  /// full width so a label never runs to the very edge of the card.
  static const _reach = 0.46;

  /// Air between a label and the line above it, on top of the label's own
  /// height and the arc's rise. Enough for the two chips not to touch.
  static const _clearance = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (board.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    // The apex sits below the box, at whatever distance makes the sector
    // span [_reach] of the width at its far edge — so a narrow sector (the
    // javelin's) is drawn narrower, and both are drawn as real wedges with
    // real arcs rather than as a ladder of straight lines.
    final apexFromTop = size.width * _reach / math.tan(halfAngle);
    final apex = Offset(size.width / 2, _topPad + apexFromTop);
    final plot = size.height - _topPad - _bottomPad;

    double yOf(double distance) =>
        _topPad + (1 - board.fractionOf(distance)) * plot;
    double halfWidthAt(double radius) => radius * math.sin(halfAngle);

    // The closest two lines are ever drawn together: a label's height, plus
    // the rise of the arc above it — an arc sits highest in the middle and
    // drops to the sector lines either side, which is exactly where the
    // label under it starts.
    //
    // A competition decided by a centimeter is a real thing, and drawn to
    // scale it is two lines on top of each other under two labels printing
    // over one another. So crowded lines are spread apart and the numbers
    // on them carry the exact distances: the board says where the marks are
    // in relation to each other, not how many pixels a centimeter is.
    final rise = apexFromTop * (1 - math.cos(halfAngle));
    final minGap = _labelHeight() + rise + _clearance;

    // Where each line actually lands, furthest first. Worked out once,
    // because the shading and the labels have to agree with the arcs.
    final rows = <double>[];
    var floor = _topPad;
    for (final mark in board.marks) {
      final y = math.max(yOf(mark.distance), floor);
      rows.add(y);
      floor = y + minGap;
    }
    // Spreading them can push the last one off the bottom; lifting the
    // whole set keeps the gaps and loses only the padding under it. The
    // rise counts here too: an arc sits lowest at the sector lines, not in
    // the middle where its row is measured.
    final overflow = rows.last + rise - (size.height - _bottomPad);
    if (overflow > 0) {
      for (var i = 0; i < rows.length; i++) {
        rows[i] = math.max(_topPad, rows[i] - overflow);
      }
    }

    void arc(double radius, Paint paint) => canvas.drawArc(
          Rect.fromCircle(center: apex, radius: radius),
          -math.pi / 2 - halfAngle,
          2 * halfAngle,
          false,
          paint,
        );

    Paint stroke(Color color, double width, [double alpha = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(alpha);

    // The grass: a wash between the sector lines, lighter the further out,
    // so the wedge has a body under the marks.
    // Out past the top of the box: a wedge that stopped at the furthest
    // line would draw a seam across the card where the grass ran out.
    final brim = halfWidthAt(apex.dy + 2);
    final wedge = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(apex.dx - brim, -2)
      ..lineTo(apex.dx + brim, -2)
      ..close();
    canvas.drawPath(
      wedge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [grass.withOpacity(0.10), grass.withOpacity(0.02)],
        ).createShader(Offset.zero & size),
    );

    // Past the cut is where a throw has to land, so it is drawn as a place
    // rather than as a line: everything beyond the last qualifying mark is
    // shaded, and an athlete can see whether they are in it.
    final cut = board.marks.indexWhere((mark) => mark.line == BoardLine.cut);
    if (cut != -1) {
      canvas.save();
      canvas.clipPath(wedge);
      canvas.drawRect(
        Rect.fromLTRB(0, -2, size.width, rows[cut]),
        Paint()..color = grass.withOpacity(0.07),
      );
      canvas.restore();
    }

    // The sector lines, out past the far edge of the band: they carry on
    // to the back of the field, and stopping them at the top of the box
    // would draw a room rather than a sector.
    for (final sign in [-1, 1]) {
      final angle = -math.pi / 2 + sign * halfAngle;
      canvas.drawLine(
        apex,
        apex + Offset(math.cos(angle), math.sin(angle)) * (size.height * 3),
        stroke(line, 1.2, 0.8),
      );
    }

    // Everybody else in the competition: the spread of the field, with no
    // name on it. Drawn where they landed rather than spread out — they
    // carry no label to keep clear of.
    for (final other in board.others) {
      arc(apex.dy - yOf(other), stroke(faint, 1, 0.28));
    }

    // Arcs first, labels after: a line drawn later would otherwise cut
    // through the label of the one above it.
    for (var i = 0; i < board.marks.length; i++) {
      final mark = board.marks[i];
      final radius = apex.dy - rows[i];
      final color = _colorOf(mark.line);
      final leading =
          mark.line == BoardLine.first || mark.line == BoardLine.upNow;
      // A podium line is struck out of the same metal as the medal, lit
      // from the same corner, so three lines across a sector read as three
      // medals rather than as three colors somebody picked.
      final metal = _metalOf(
        mark.line,
        Rect.fromLTRB(apex.dx - halfWidthAt(radius), rows[i],
            apex.dx + halfWidthAt(radius), rows[i] + rise + 2),
      );
      if (mark.line == BoardLine.cut) {
        _dashedArc(canvas, apex, radius, stroke(color, 1.4, 0.9));
      } else {
        final paint = stroke(color, leading ? 2.6 : 2.0);
        if (metal != null) paint.shader = metal;
        arc(radius, paint);
      }
      // The athlete in the circle gets a marker as well as a line: it is
      // the one line on the board that moves in the next thirty seconds.
      if (mark.line == BoardLine.upNow) {
        canvas.drawCircle(Offset(apex.dx, rows[i]), 4, Paint()..color = color);
      }
    }

    // Labels, furthest first, each one kept clear of the one above it. Two
    // marks a centimeter apart are a real thing a competition does, and the
    // board still has to be readable when it happens — so a crowded label
    // slides down past its own arc rather than printing over its neighbour.
    for (var i = 0; i < board.marks.length; i++) {
      _label(
        canvas,
        board.marks[i],
        _colorOf(board.marks[i].line),
        y: rows[i],
        center: apex.dx,
        half: halfWidthAt(apex.dy - rows[i]),
      );
    }
  }

  /// How tall one label is, measured rather than assumed — the app's type
  /// is whatever the theme says it is.
  double _labelHeight() => (TextPainter(
        text: TextSpan(text: '0', style: text.copyWith(fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout())
          .height;

  /// The ramp a podium line is drawn with, or null for a line that is a
  /// color rather than a metal.
  Shader? _metalOf(BoardLine line, Rect bounds) => switch (line) {
        BoardLine.first => goldShader(bounds),
        BoardLine.second => silverShader(bounds),
        BoardLine.third => bronzeShader(bounds),
        _ => null,
      };

  Color _colorOf(BoardLine line) => switch (line) {
        // The mid tone of each ramp, for the text beside the line — the
        // same reason the app keeps a flat gold next to its gradient one.
        BoardLine.first => personalBestGold,
        BoardLine.second => secondPlaceSilver,
        BoardLine.third => thirdPlaceBronze,
        // Not the app's own accent: an event whose color is close to it —
        // the javelin's is — would draw the cut and the coach's athlete in
        // the same blue, which are the two lines that must not be confused.
        BoardLine.cut => faint,
        // The same color for both: it is the same athlete's line either
        // way, and which of them is in the circle is said by the marker on
        // it and by the weight of the type.
        BoardLine.upNow || BoardLine.mine => accent,
      };

  /// The name to the left, the distance to the right, both inside the
  /// sector lines and both just above the line they belong to.
  ///
  /// The distance is laid out first and keeps its room: a name is worth
  /// cutting short, and a mark never is.
  void _label(
    Canvas canvas,
    MeetBoardMark mark,
    Color color, {
    required double y,
    required double center,
    required double half,
  }) {
    final inset = math.max(half - 6, 26.0);
    final left = center - inset;
    final right = center + inset;
    final style = text.copyWith(
      fontSize: 11,
      color: color,
      fontWeight: mark.line == BoardLine.first || mark.line == BoardLine.upNow
          ? FontWeight.w700
          : FontWeight.w600,
    );

    final distance = TextPainter(
      text: TextSpan(
          text: formatDistance(mark.distance, mark.unit), style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final who = [
      mark.label,
      if (mark.name.isNotEmpty) mark.name,
    ].join('  ');
    final name = TextPainter(
      text: TextSpan(text: who, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(right - left - distance.width - 10, 24));

    // Set on a chip rather than straight onto the grass: a name has arcs
    // and sector lines running under it, and the one thing that must stay
    // readable on a board glanced at between attempts is whose mark it is.
    final top = y - distance.height - 4;
    final chip = RRect.fromLTRBR(
      left - 6,
      top - 2,
      right + 6,
      top + distance.height + 2,
      const Radius.circular(4),
    );
    canvas.drawRRect(chip, Paint()..color = backdrop.withOpacity(0.88));
    name.paint(canvas, Offset(left, top));
    distance.paint(canvas, Offset(right - distance.width, top));
  }

  /// The cut, drawn the way a provisional line should be: it moves every
  /// time somebody throws.
  void _dashedArc(Canvas canvas, Offset apex, double radius, Paint paint) {
    // A dash length in radians, so the dashes stay the same size on screen
    // however far out the arc is.
    final step = radius <= 0 ? halfAngle : 7 / radius;
    for (var a = -halfAngle; a < halfAngle; a += step * 2) {
      canvas.drawArc(
        Rect.fromCircle(center: apex, radius: radius),
        -math.pi / 2 + a,
        math.min(step, halfAngle - a),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SectorBoardPainter old) =>
      old.board != board ||
      old.accent != accent ||
      old.halfAngle != halfAngle ||
      old.backdrop != backdrop ||
      old.text != text;
}
