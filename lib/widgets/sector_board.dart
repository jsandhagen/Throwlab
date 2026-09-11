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
/// The sector is drawn to its real angle for the event, and inside the band
/// the marks are to scale — a fixed, round number of meters deep
/// ([MeetBoard.span]), with rings under them at [MeetBoard.grid]. What is
/// not to scale is where the band starts: a sector drawn honestly from the
/// circle stacks the whole competition into the last few percent of its
/// length, where three marks a meter apart are three marks on top of each
/// other. So the board is a window on the stretch being thrown in, and a
/// gap across it can be read as a distance because the window's depth only
/// changes when somebody zooms it.
///
/// Labels are the one thing allowed to move: two marks a centimeter apart
/// are a real competition, and their lines land a pixel apart at any
/// sensible zoom. A crowded label slides clear of its neighbour and grows a
/// leader down to the line it belongs to, rather than the lines being
/// spread out to make room for the type.
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

  /// Air between one label and the next, on top of the label's own height.
  /// Enough for two chips not to touch.
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
    const ceilingY = _topPad;
    final apex = Offset(size.width / 2, ceilingY + apexFromTop);
    // How far an arc drops from the middle of the sector to the lines
    // either side. The near edge of the band has to sit that far off the
    // bottom of the box or the closest mark of all is drawn as two stubs
    // with its middle cut off.
    final rise = apexFromTop * (1 - math.cos(halfAngle));
    final floorY = size.height - _bottomPad - rise;
    final plot = floorY - ceilingY;

    // Where a distance lands, to scale across the band. Off the ends for a
    // mark outside it, which is answered at the edge rather than by moving
    // the mark.
    double yOf(double distance) =>
        ceilingY + (1 - board.fractionOf(distance)) * plot;
    double halfWidthAt(double radius) => radius * math.sin(halfAngle);

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

    // The scale, drawn: a ring every [MeetBoard.grid] meters. They are what
    // makes a gap on the board a distance rather than a picture — three
    // rings between two marks is three of whatever the legend says, at any
    // zoom, and the eye does that without being asked to.
    canvas.save();
    canvas.clipPath(wedge);
    for (final ring in board.rings) {
      arc(apex.dy - yOf(ring), stroke(line, 1, 0.32));
    }
    canvas.restore();

    // Past the cut is where a throw has to land, so it is drawn as a place
    // rather than as a line: everything beyond the last qualifying mark is
    // shaded, and an athlete can see whether they are in it.
    final cut = board.marks.indexWhere((mark) => mark.line == BoardLine.cut);
    // Zoomed in past it, the cut can be off the board. Below the near edge
    // everything drawn is past it and the whole wedge shades; above the far
    // edge none of it is, and nothing does.
    if (cut != -1 && board.fractionOf(board.marks[cut].distance) <= 1) {
      canvas.save();
      canvas.clipPath(wedge);
      canvas.drawRect(
        Rect.fromLTRB(0, -2, size.width,
            math.min(yOf(board.marks[cut].distance), floorY)),
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
    // name on it.
    for (final other in board.others) {
      arc(apex.dy - yOf(other), stroke(faint, 1, 0.28));
    }

    // The lines themselves, each exactly where its mark landed. Arcs first
    // and labels after: a line drawn later would otherwise cut through the
    // label of the one above it.
    for (final mark in board.marks) {
      if (!_inBand(mark)) continue;
      final y = yOf(mark.distance);
      final radius = apex.dy - y;
      final color = _colorOf(mark.line);
      final leading =
          mark.line == BoardLine.first || mark.line == BoardLine.upNow;
      // A podium line is struck out of the same metal as the medal, lit
      // from the same corner, so three lines across a sector read as three
      // medals rather than as three colors somebody picked.
      final metal = _metalOf(
        mark.line,
        Rect.fromLTRB(apex.dx - halfWidthAt(radius), y,
            apex.dx + halfWidthAt(radius), y + rise + 2),
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
        canvas.drawCircle(Offset(apex.dx, y), 4, Paint()..color = color);
      }
    }

    // Labels, furthest first, each one kept clear of the one above it. Two
    // marks a centimeter apart are a real thing a competition does, and the
    // board still has to be readable when it happens — so a crowded label
    // slides down past its own line and grows a leader back to it. The
    // lines stay where the throws put them.
    final gap = _labelHeight() + _clearance;
    final rows = <double>[];
    var ceiling = ceilingY;
    for (final mark in board.marks) {
      // A mark the zoom has pushed off the band is labelled against the
      // edge it went out of, with an arrow on it: a leader that vanished
      // because somebody zoomed in is worse than no board at all.
      final anchor = switch (board.fractionOf(mark.distance)) {
        // Room over the chip for the arrow, which is the whole of what an
        // edge marker says.
        > 1 => ceilingY + 5,
        < 0 => floorY,
        _ => yOf(mark.distance),
      };
      final y = math.max(anchor, ceiling);
      rows.add(y);
      ceiling = y + gap;
    }
    // Stacking them can push the last one off the bottom; lifting the whole
    // set keeps the gaps and loses only the padding under it.
    final overflow = rows.last - floorY;
    if (overflow > 0) {
      for (var i = 0; i < rows.length; i++) {
        rows[i] = math.max(ceilingY, rows[i] - overflow);
      }
    }

    // What a ring is worth, in the corner the wedge never reaches. Without
    // it the rings are decoration; with it the gap between two marks can be
    // read off the board without reading either label.
    _legend(canvas, size);

    for (var i = 0; i < board.marks.length; i++) {
      final mark = board.marks[i];
      _label(
        canvas,
        mark,
        _colorOf(mark.line),
        y: rows[i],
        // Against the line it belongs to, not against where the label
        // ended up: the leader is drawn between the two.
        lineY: _inBand(mark) ? yOf(mark.distance) : null,
        beyond: _inBand(mark)
            ? null
            : (board.fractionOf(mark.distance) > 1 ? -1 : 1),
        gap: _inBand(mark)
            ? null
            : math.max(mark.distance - board.far, board.near - mark.distance),
        center: apex.dx,
        half: halfWidthAt(apex.dy - rows[i]),
        // Two thirds of the box, whatever the sector is doing at that
        // depth. The near end of a tall board is a narrow wedge, and the
        // names down there are the ones a coach is reading.
        minHalf: size.width * 0.33,
      );
    }
  }

  /// The scale, in words, in the bottom-left corner: the sector narrows
  /// towards its circle, so the bottom corners of the box are empty at
  /// every zoom and nothing has to move to make room for this.
  void _legend(Canvas canvas, Size size) {
    final legend = TextPainter(
      text: TextSpan(
        // And, on a board somebody has pinched, the way back to the one it
        // picks for itself — which is otherwise a gesture nothing mentions.
        text: '${formatBand(board.grid)} rings'
            '${board.fitted ? '' : '  ·  double-tap to fit'}',
        style: text.copyWith(
          fontSize: 10,
          color: faint.withOpacity(0.7),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    legend.paint(canvas, Offset(8, size.height - legend.height - 5));
  }

  /// Whether a mark falls inside the band, and so has a line on the board
  /// rather than an arrow at the edge of it.
  bool _inBand(MeetBoardMark mark) {
    final at = board.fractionOf(mark.distance);
    return at >= 0 && at <= 1;
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
  ///
  /// [lineY] is where the mark's own line is, when it has one: a label that
  /// had to slide clear of its neighbour is joined back to its line, so a
  /// crowded board is still unambiguous about which number is which. Null
  /// with [beyond] set for a mark the band has broken off — -1 for one past
  /// the far edge, 1 for one short of the near one — which is drawn against
  /// that edge with an arrow and [gap], how far outside the board it
  /// landed.
  void _label(
    Canvas canvas,
    MeetBoardMark mark,
    Color color, {
    required double y,
    required double center,
    required double half,
    required double minHalf,
    double? lineY,
    int? beyond,
    double? gap,
  }) {
    // Inside the sector lines where there is room, and out past them where
    // there isn't: a chip is type, not a mark, and a name cut to 'L. Fis…'
    // to stay between two lines has lost the only thing it was there for.
    final inset = math.max(half - 6, minHalf);
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

    // Two pills rather than one bar across the sector: who, and how far.
    // A bar the width of the wedge blanks out the ground between the name
    // and the mark, which is the ground the line itself is drawn on — the
    // arc runs through the gap between them instead, and the board reads as
    // a sector with names on it rather than as a stack of rows.
    //
    // Set on something rather than straight onto the grass, because a name
    // has arcs and sector lines running under it and the one thing that
    // must stay readable on a board glanced at between attempts is whose
    // mark it is.
    final top = y - distance.height - 4;
    final bottom = top + distance.height + 2;
    // Fully round, so two of them read as two things and not as one bar
    // somebody cut a hole in.
    final radius = Radius.circular((bottom - top + 2) / 2);
    final pill = Paint()..color = backdrop.withOpacity(0.88);
    canvas.drawRRect(
      RRect.fromLTRBR(left - 7, top - 2, left + name.width + 7, bottom, radius),
      pill,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
          right - distance.width - 7, top - 2, right + 7, bottom, radius),
      pill,
    );

    // The leader, in the gap the two pills leave between them. Only when
    // the label has actually been moved — a line drawn from a label sitting
    // where it belongs is noise.
    if (lineY != null && (lineY - y).abs() > 2) {
      canvas.drawLine(
        Offset(center, lineY < y ? top - 2 : bottom),
        Offset(center, lineY),
        Paint()
          ..strokeWidth = 1
          ..color = color.withOpacity(0.55),
      );
    }

    // A mark the band broke off is drawn the way anything off the edge of a
    // screen is: an arrow that way, and how far that way it is. The chip
    // above it still carries the name and the mark itself, so all the edge
    // is saying is 'not on this board, by this much'. Drawn rather than
    // typed — an arrow is not in every font, and a missing glyph is a box.
    if (beyond != null && gap != null) {
      final tip = beyond < 0 ? top - 10 : bottom + 10;
      final base = beyond < 0 ? top - 2 : bottom + 2;
      final out = TextPainter(
        text: TextSpan(
          text: formatDistance(gap, mark.unit),
          style: style.copyWith(fontSize: 10, color: color.withOpacity(0.85)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final arrowX = center - out.width / 2 - 9;
      canvas.drawPath(
        Path()
          ..moveTo(arrowX, tip)
          ..lineTo(arrowX - 4.5, base)
          ..lineTo(arrowX + 4.5, base)
          ..close(),
        Paint()..color = color.withOpacity(0.85),
      );
      out.paint(
        canvas,
        Offset(center - out.width / 2 + 4, (tip + base) / 2 - out.height / 2),
      );
    }

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
