import 'dart:math' as math;

import 'meet.dart';
import 'throw_video.dart';

/// What one line drawn across the sector stands for.
enum BoardLine {
  first,
  second,
  third,

  /// The mark holding the last qualifying place — what a throw has to beat
  /// to make the final.
  cut,

  /// The athlete in the circle, when they are not already on the podium.
  upNow,

  /// One of the coach's own, when they are not already on the board for
  /// some other reason. A coach opens this to see their athlete against the
  /// cut, and an athlete who is neither winning it nor in the circle is
  /// exactly the one that question is about.
  mine,
}

/// One line across the sector: a mark, and who is standing on it.
class MeetBoardMark {
  const MeetBoardMark({
    required this.line,
    required this.distance,
    required this.unit,
    required this.name,
    required this.tracked,
    this.place,
  });

  final BoardLine line;

  /// Meters, like every distance in the app.
  final double distance;

  /// What it was measured in, and what it reads back in.
  final DistanceUnit unit;

  /// Whose mark it is; empty for the cut, which belongs to a place rather
  /// than to a person.
  final String name;

  /// Where the mark stands, for a line that is not one of the first three;
  /// null for the cut, which is a place rather than a person in one.
  final int? place;

  /// Whether they are one of the coach's own athletes.
  final bool tracked;

  /// The name as a board says it: the surname, and the school if the entry
  /// carries one.
  ///
  /// A program prints 'N. Achebe (Croydon)' because a program is a list of
  /// strangers. A board is read at a glance by somebody who is watching the
  /// competition, and the initial is the part they already know — it is
  /// also the part that makes every label on the sector a third wider than
  /// it needs to be. The school stays: it is how two throwers with the same
  /// surname are told apart, and it is what a coach shouts.
  String get boardName => boardNameOf(name);

  /// '1st', '2nd', '3rd', 'the cut', '5th'.
  ///
  /// A line further down the field says which place it is rather than
  /// whose it is — the name is beside it, and a coach reading the board
  /// wants the number they have to climb.
  String get label => switch (line) {
        BoardLine.first => '1st',
        BoardLine.second => '2nd',
        BoardLine.third => '3rd',
        BoardLine.cut => 'the cut',
        BoardLine.upNow ||
        BoardLine.mine =>
          place == null ? '' : ordinalPlace(place!),
      };
}

/// A competition as it would be drawn on the infield: the marks that matter
/// as lines across the sector, and the band of it worth looking at.
///
/// A table of places answers who is winning. It does not answer the thing a
/// coach is actually squinting at from behind the cage — how far past the
/// leader's mark their athlete has to land, and whether that is a stride or
/// a throw. Lines on a sector answer that at a glance, which is why every
/// televised final has them painted on the grass.
///
/// The band is the point. A sector drawn from the circle would stack the
/// whole competition into the last few percent of its length, where three
/// marks a meter apart are three marks on top of each other. So the board
/// holds only the stretch the competition is being decided in, and the
/// drawing says which stretch that is by labelling every line on it.
///
/// Inside that band the marks are to scale, and the scale is a round number
/// off [boardSpans] rather than whatever the field happens to span: a gap of
/// half the box is a gap of half the box's worth of meters, and the number
/// of meters is the same after the next throw as it was before it. A band
/// cut to fit the marks is a scale that changes every time somebody throws,
/// which makes the one thing the board is for — is that a stride or a throw
/// — unreadable. Zooming changes it, and nothing else does.
class MeetBoard {
  /// [span] is how deep the band is, in meters — the zoom. Null picks the
  /// shallowest one off [boardSpans] that holds every line, which is what
  /// the board opens at; a coach who has zoomed passes the span they chose
  /// and it is kept whatever the next throw does.
  factory MeetBoard(
    MeetStandings standings, {
    MeetEntry? inTheCircle,
    double? span,
  }) {
    final placed = [
      for (final place in standings.places)
        if (place.best != null) place,
    ];
    if (placed.isEmpty) {
      return MeetBoard._(
        marks: const [],
        others: const [],
        near: 0,
        far: span ?? defaultBoardSpan,
        grid: gridFor(span ?? defaultBoardSpan),
        fitted: span == null,
        hasCut: false,
      );
    }

    DistanceUnit unitOf(MeetPlace place) =>
        place.series.unitAt(place.series.bestRound!);

    const podium = [BoardLine.first, BoardLine.second, BoardLine.third];
    final marks = <MeetBoardMark>[
      for (var i = 0; i < placed.length && i < podium.length; i++)
        MeetBoardMark(
          line: podium[i],
          distance: placed[i].best!,
          unit: unitOf(placed[i]),
          name: placed[i].entry.athlete,
          tracked: placed[i].entry.tracked,
        ),
    ];
    final drawn = {for (final mark in marks) mark.distance};

    // The cut, when there is one and it isn't already a line — a final of
    // two is drawn by the lines for first and second, and saying 'the cut'
    // over one of them twice helps nobody.
    final cutMark = standings.cutMark;
    if (standings.hasCut && cutMark != null && !drawn.contains(cutMark)) {
      marks.add(MeetBoardMark(
        line: BoardLine.cut,
        distance: cutMark,
        unit: unitOf(placed.first),
        name: '',
        tracked: false,
      ));
      drawn.add(cutMark);
    }

    void add(BoardLine line, MeetPlace place) {
      marks.add(MeetBoardMark(
        line: line,
        distance: place.best!,
        unit: unitOf(place),
        name: place.entry.athlete,
        tracked: place.entry.tracked,
        place: place.place,
      ));
      drawn.add(place.best!);
    }

    // The athlete in the circle. On the podium already, they are drawn by
    // their place — the board says where the throw has to land, and their
    // line is where it is landing from.
    final mine = inTheCircle == null ? null : standings.placeOf(inTheCircle.id);
    if (mine != null && mine.best != null && !drawn.contains(mine.best)) {
      add(BoardLine.upNow, mine);
    }

    // Then the coach's own, wherever they are standing. This is the line
    // the board is usually being opened for: a rival leading it is context,
    // and an athlete of theirs a centimeter outside the cut is the whole
    // question.
    for (final place in placed) {
      if (!place.entry.tracked || place.best == null) continue;
      if (drawn.contains(place.best)) continue;
      add(BoardLine.mine, place);
    }

    marks.sort((a, b) => b.distance.compareTo(a.distance));

    // The band is set by the lines, not by the field. A competition with a
    // straggler in it would otherwise be drawn with the three marks that
    // decide it squeezed into the top inch, which is the thing this board
    // exists to stop.
    // What the band is hung on when it can't hold every line: the athlete
    // in the circle, else the coach's own best-placed. Nobody, at a board
    // with neither, and it hangs on whichever stretch of the competition
    // has the most of it in it.
    final focus = marks
        .where((mark) => mark.line == BoardLine.upNow)
        .followedBy(marks.where((mark) => mark.tracked))
        .firstOrNull
        ?.distance;

    final at = [for (final mark in marks) mark.distance]..sort();
    final band = span == null
        ? fitBand(at, focus)
        : (span: span, near: placeBand(at, focus, span).near);
    final grid = gridFor(band.span);
    final lowest = band.near;
    final highest = _round(lowest + band.span);

    // Everybody else who landed inside the band, drawn as a mark with no
    // name on it: the spread of the field is worth seeing even when the
    // names behind it are not. A throw short of the band is off the board,
    // which is what the standings table is for.
    final others = [
      for (final place in placed)
        if (!drawn.contains(place.best) &&
            place.best! >= lowest &&
            place.best! <= highest)
          place.best!,
    ]..sort((a, b) => b.compareTo(a));

    return MeetBoard._(
      marks: marks,
      others: others,
      near: lowest,
      far: highest,
      grid: grid,
      fitted: span == null,
      hasCut: standings.hasCut,
    );
  }

  const MeetBoard._({
    required this.marks,
    required this.others,
    required this.near,
    required this.far,
    required this.grid,
    required this.fitted,
    required this.hasCut,
  });

  /// The lines to draw, furthest first.
  final List<MeetBoardMark> marks;

  /// Every other mark in the competition, furthest first.
  final List<double> others;

  /// The stretch of the sector the board covers, in meters.
  final double near;
  final double far;

  /// How far apart the marker lines under the marks are, in meters — the
  /// scale, drawn, so a gap on the board can be read as a distance without
  /// doing arithmetic off the labels.
  final double grid;

  /// Whether the band was picked to hold the marks rather than asked for.
  /// A fitted board follows the competition; a zoomed one stays put.
  final bool fitted;

  /// Whether anybody is going to be left out, which is what makes the cut
  /// line worth drawing at all.
  final bool hasCut;

  /// Nobody has a mark on the board yet.
  bool get isEmpty => marks.isEmpty;

  /// How deep the band is, in meters. The zoom, and the whole of what a
  /// gap on the board means.
  double get span => far - near;

  /// Whether every line drawn is inside the band. False once a coach has
  /// zoomed past the spread of the competition, which the board says at its
  /// edges rather than by quietly dropping a mark.
  bool get holdsEveryMark =>
      marks.every((mark) => mark.distance >= near && mark.distance <= far);

  /// Where [distance] falls across the band, 0 at the near edge and 1 at
  /// the far one. Outside that for a mark off the board, which the drawing
  /// pins to the edge rather than pretends about.
  double fractionOf(double distance) =>
      far == near ? 0.5 : (distance - near) / (far - near);

  /// Every marker line inside the band, near edge first — the scale made
  /// visible.
  ///
  /// The lines painted across a sector at a round number of meters, which
  /// a field is measured against and a coach counts a gap off. Never
  /// 'rings': in throwing, the ring is the circle the throw is made from,
  /// and there is one of those on the board already.
  List<double> get markerLines {
    final out = <double>[];
    for (var at = (near / grid).ceilToDouble() * grid;
        at <= far + 1e-9;
        at += grid) {
      out.add(_round(at));
    }
    return out;
  }
}

/// The depths the band can be drawn at, in meters — what zooming steps
/// through, shallowest first.
///
/// Round numbers, because the point of a fixed scale is that a coach knows
/// what one is without measuring: at 5 m a quarter of the box is a meter
/// and a bit. Down at half a meter two marks a centimeter apart are finally
/// apart on screen, which is the competition a board is least use in and
/// most wanted for.
const List<double> boardSpans = [0.5, 1, 2, 5, 10, 20, 50];

/// What a board opens at with nothing on it yet.
const double defaultBoardSpan = 5;

/// The shallowest band [MeetBoard] will fit by itself. A first throw with
/// nothing to measure it against would otherwise open at half a meter and
/// leap to ten the moment somebody else landed one — a scale that has to be
/// relearned twice in a round is no scale at all.
const double minFittedSpan = 2;

/// The deepest band [MeetBoard] will fit by itself. Past it a competition
/// is drawn as a smear — ten meters across a phone is a centimeter to the
/// third of a pixel — so a board that would have to go deeper breaks
/// instead, and whatever is outside it is drawn as an arrow off the edge
/// with its mark on it. Zooming out by hand still goes the whole way: that
/// is a coach asking for the smear, which is different.
const double maxFittedSpan = 10;

/// How far apart the marker lines are at [span]: four or five of them
/// across the band, on a number worth reading.
double gridFor(double span) => switch (span) {
      <= 0.5 => 0.1,
      <= 1 => 0.2,
      <= 2 => 0.5,
      <= 5 => 1,
      <= 10 => 2,
      <= 20 => 5,
      _ => 10,
    };

/// The near edge of a band [span] deep hung on [center], snapped down onto
/// the marker lines.
///
/// Snapped, because a band that centered itself exactly would slide by a
/// few centimeters every time anybody threw, and every line on it would
/// creep even though the mark under it hadn't moved. On the marker grid it
/// only ever moves a line at a time, so most throws leave the board where
/// it was and the one that moves it is obvious. To the nearest line rather
/// than down onto one: it is a band either side of the marks, and rounding
/// one way would hang half a step of empty sector under every board.
double nearEdge(double center, double span, double grid) {
  final near = (center - span / 2) / grid;
  return _round(math.max(0, near.roundToDouble() * grid));
}

/// The band an auto-scaled board draws: how deep, and where it starts.
///
/// The shallowest rung that holds every line, which is what a competition
/// mostly wants. When no rung holds them all, the board goes deeper only
/// while the next rung down actually picks up another mark — and when one
/// doesn't, it breaks: it keeps the run of the competition around the
/// athlete the board belongs to, drawn at a scale that run can be read at,
/// and whatever is outside becomes an arrow off the edge carrying its mark
/// and how far out it landed. A leader five meters clear of the fight for
/// second is worth an arrow; he is not worth squashing that fight into an
/// inch of sector. [maxFittedSpan] is the backstop for a field that is all
/// gaps.
///
/// [at] is every mark to be drawn, in meters, shortest first. [focus] is
/// the athlete the board belongs to, if any.
({double span, double near}) fitBand(List<double> at, double? focus) {
  ({double span, double near, int held})? best;
  for (final span in boardSpans) {
    if (span < minFittedSpan) continue;
    final placed = placeBand(at, focus, span);
    // Everything on the board is the end of it: a deeper rung can only
    // spread the same marks thinner.
    if (placed.held == at.length) return (span: span, near: placed.near);
    // Otherwise go deeper only while going deeper buys a mark. A rung that
    // holds no more than the one before it means the next mark out is a
    // long way out — far enough that reaching it would squash the
    // competition into an inch — so the board stops here and draws at it
    // instead.
    if (best != null && placed.held <= best.held) break;
    best = (span: span, near: placed.near, held: placed.held);
    if (span >= maxFittedSpan) break;
  }
  return (span: best!.span, near: best.near);
}

/// Where a band [span] deep goes, and how many of [at] it ends up holding.
///
/// It grows out from [focus] a mark at a time, nearest first, and stops at
/// the first gap too wide to step over — so what it keeps is the run of the
/// competition around the athlete it belongs to rather than whatever
/// happens to be within half a span. With no focus it takes the run holding
/// the most marks, furthest out on a tie: a competition is decided at the
/// top of it. Both edges land on marker lines, which keeps the board from
/// sliding a few centimeters under every throw.
({double near, int held}) placeBand(
    List<double> at, double? focus, double span) {
  final grid = gridFor(span);

  double low;
  double high;
  if (focus != null) {
    low = focus;
    high = focus;
    for (;;) {
      final under = _under(at, low);
      final over = _over(at, high);
      // The nearer side first, and the other one if the nearer won't go —
      // a band grows towards the throw next to it, not towards the end of
      // the field it happens to be at.
      final down = under == null || _edgeFor(under, high, span, grid) == null
          ? null
          : high - under;
      final up = over == null || _edgeFor(low, over, span, grid) == null
          ? null
          : over - low;
      if (down != null && (up == null || down <= up)) {
        low = under!;
      } else if (up != null) {
        high = over!;
      } else {
        break;
      }
    }
  } else {
    low = at.isEmpty ? 0 : at.last;
    high = low;
    var best = 0;
    for (var top = at.length - 1; top >= 0; top--) {
      var bottom = top;
      while (
          bottom > 0 && _edgeFor(at[bottom - 1], at[top], span, grid) != null) {
        bottom--;
      }
      if (top - bottom + 1 > best) {
        best = top - bottom + 1;
        low = at[bottom];
        high = at[top];
      }
    }
  }

  final near = _edgeFor(low, high, span, grid) ?? nearEdge(low, span, grid);
  final held = at
      .where((mark) => mark >= near - 1e-9 && mark <= near + span + 1e-9)
      .length;
  return (near: near, held: held);
}

/// Where a band [span] deep starts if it is to hold everything from [low] to
/// [high] with both edges on a marker line — null when none exists, which
/// is how far a band is allowed to grow.
///
/// The snap is the whole of the difficulty: a run a hair under a span wide
/// can still be unholdable once both edges have to land on lines, and a run
/// that looked like it fit is worth nothing if drawing it drops a mark off
/// the bottom.
double? _edgeFor(double low, double high, double span, double grid) {
  if (high - low > span) return null;
  var near = nearEdge((low + high) / 2, span, grid);
  if (near > low) {
    near = _round(math.max(0, (low / grid).floorToDouble() * grid));
  }
  if (near + span < high) {
    near = _round(math.max(0, ((high - span) / grid).ceilToDouble() * grid));
  }
  final holds = near <= low + 1e-9 && near + span >= high - 1e-9;
  return holds ? near : null;
}

/// The mark just short of [of], and the one just past it. Null at the ends.
double? _under(List<double> at, double of) {
  double? found;
  for (final mark in at) {
    if (mark < of) {
      found = mark;
    }
  }
  return found;
}

double? _over(List<double> at, double of) {
  for (final mark in at) {
    if (mark > of) return mark;
  }
  return null;
}

/// A name cut to what a board has room for: the surname, keeping whatever a
/// heat sheet put in brackets after it.
///
/// The last word of the name, which is the surname for every way a meet
/// writes one — 'N. Achebe', 'Achebe, N', 'Nnamdi Achebe'. A name that is
/// one word is already as short as it goes.
String boardNameOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;
  // What a program puts after the name — the school, the club, the country.
  final bracket = RegExp(r'\s*(\(.*\))$').firstMatch(trimmed);
  final who =
      bracket == null ? trimmed : trimmed.substring(0, bracket.start).trim();
  final words = who.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return trimmed;
  // 'Achebe, N' — a sheet that leads with the surname has already said it.
  final surname = words.first.endsWith(',') ? words.first : words.last;
  return [
    surname.replaceAll(',', ''),
    if (bracket != null) bracket.group(1)!,
  ].join(' ');
}

/// A band or a marker line as a distance: '5 m', '0.5 m'. Round numbers,
/// round — the scale is only useful if it reads as one number.
String formatBand(double meters) {
  final whole = meters == meters.roundToDouble();
  return '${whole ? meters.round() : meters} m';
}

/// Meters, to the millimeter. Stepping along a grid in floating point
/// otherwise leaves a line at 41.699999999999996, which prints.
double _round(double meters) => (meters * 1000).roundToDouble() / 1000;
