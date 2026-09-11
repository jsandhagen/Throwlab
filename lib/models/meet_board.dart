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
class MeetBoard {
  factory MeetBoard(MeetStandings standings, {MeetEntry? inTheCircle}) {
    final placed = [
      for (final place in standings.places)
        if (place.best != null) place,
    ];
    if (placed.isEmpty) {
      return const MeetBoard._(
          marks: [], others: [], near: 0, far: 0, hasCut: false);
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
    var lowest = marks.last.distance;
    var highest = marks.first.distance;
    // A board with one line on it, or a field all level, still has to be a
    // band rather than a line: half a meter either side puts the mark in
    // the middle of the sector instead of along one edge of it.
    final pad = math.max((highest - lowest) * 0.25, 0.5);
    lowest = math.max(0, lowest - pad);
    highest += pad;

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
      hasCut: standings.hasCut,
    );
  }

  const MeetBoard._({
    required this.marks,
    required this.others,
    required this.near,
    required this.far,
    required this.hasCut,
  });

  /// The lines to draw, furthest first.
  final List<MeetBoardMark> marks;

  /// Every other mark in the competition, furthest first.
  final List<double> others;

  /// The stretch of the sector the board covers, in meters.
  final double near;
  final double far;

  /// Whether anybody is going to be left out, which is what makes the cut
  /// line worth drawing at all.
  final bool hasCut;

  /// Nobody has a mark on the board yet.
  bool get isEmpty => marks.isEmpty;

  /// Where [distance] falls across the band, 0 at the near edge and 1 at
  /// the far one. Outside that for a mark off the board, which the drawing
  /// clips rather than pretends about.
  double fractionOf(double distance) =>
      far == near ? 0.5 : (distance - near) / (far - near);
}
