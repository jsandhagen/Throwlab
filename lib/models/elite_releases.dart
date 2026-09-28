import 'throw_event.dart';

/// A release measured on a real throw at a championship final, for the
/// what-if calculator to hold a coach's numbers against.
///
/// Only what was measured goes in. Most of the published figures that
/// could be confirmed for this table are the release speed alone; where the
/// angle and height were not, they stay null and the calculator leaves its
/// own sliders where they were rather than filling them with a guess under
/// somebody's name. Add a row by copying the figures out of the report
/// named in [source] — every number here should be one somebody can go
/// and check.
class EliteRelease {
  const EliteRelease({
    required this.athlete,
    required this.event,
    required this.weightKg,
    required this.mark,
    required this.meet,
    required this.speed,
    this.angleDeg,
    this.height,
    required this.source,
  });

  final String athlete;
  final ThrowEvent event;
  final double weightKg;

  /// The official distance of the throw that was analyzed, meters.
  final double mark;

  final String meet;

  /// m/s.
  final double speed;
  final double? angleDeg;
  final double? height;

  /// Where the numbers come from.
  final String source;

  bool get complete => angleDeg != null && height != null;
}

/// Whose final a typical release is taken from.
enum EliteField {
  men('Elite men'),
  women('Elite women');

  const EliteField(this.label);
  final String label;
}

/// What a senior final looks like at the moment of release, as ranges
/// rather than anybody's throw, thrown with the senior implement for
/// [field].
///
/// Approximate, and said so on the screen: these are the spans the
/// biomechanics literature reports for championship finals across many
/// reports, not the figures of one of them. The women's are the thinner
/// literature of the two.
class EliteRange {
  const EliteRange({
    required this.field,
    required this.weightKg,
    required this.speed,
    required this.angleDeg,
    required this.height,
    required this.marks,
    this.attackDeg = 0,
  });

  final EliteField field;
  final double weightKg;
  final (double, double) speed;
  final (double, double) angleDeg;
  final (double, double) height;

  /// The distances those releases throw, meters.
  final (double, double) marks;

  /// The attack a typical release is set at: a discus flies best leading
  /// edge a little down on the path, a javelin with its nose on it.
  final double attackDeg;

  /// The middle of each range — the release a tap on the card loads.
  double get typicalSpeed => (speed.$1 + speed.$2) / 2;
  double get typicalAngle => (angleDeg.$1 + angleDeg.$2) / 2;
  double get typicalHeight => (height.$1 + height.$2) / 2;
}

const _wc2017 = '2017 World Championships, London';

const eliteReleases = [
  EliteRelease(
    athlete: 'Tom Walsh',
    event: ThrowEvent.shotPut,
    weightKg: 7.26,
    mark: 22.31,
    meet: '2018 World Indoor Championships, Birmingham',
    speed: 14.12,
    angleDeg: 37.3,
    height: 2.11,
    source: 'IAAF Biomechanical Report, World Indoor Championships 2018: '
        'Shot Put Men',
  ),
  EliteRelease(
    athlete: 'Paweł Fajdek',
    event: ThrowEvent.hammer,
    weightKg: 7.26,
    mark: 79.81,
    meet: _wc2017,
    speed: 27.68,
    source: 'IAAF Biomechanical Report, World Championships 2017: '
        'Hammer Throw Men',
  ),
  EliteRelease(
    athlete: 'Andrius Gudžius',
    event: ThrowEvent.discus,
    weightKg: 2,
    mark: 69.21,
    meet: _wc2017,
    speed: 24.07,
    source: 'IAAF Biomechanical Report, World Championships 2017: '
        'Discus Throw Men',
  ),
  EliteRelease(
    athlete: 'Daniel Ståhl',
    event: ThrowEvent.discus,
    weightKg: 2,
    mark: 69.19,
    meet: _wc2017,
    speed: 23.97,
    source: 'IAAF Biomechanical Report, World Championships 2017: '
        'Discus Throw Men',
  ),
  EliteRelease(
    athlete: 'Mason Finley',
    event: ThrowEvent.discus,
    weightKg: 2,
    mark: 68.03,
    meet: _wc2017,
    speed: 23.59,
    source: 'IAAF Biomechanical Report, World Championships 2017: '
        'Discus Throw Men',
  ),
];

const eliteRanges = {
  ThrowEvent.shotPut: {
    EliteField.men: EliteRange(
        field: EliteField.men,
        weightKg: 7.26,
        speed: (13.5, 14.5),
        angleDeg: (34, 39),
        height: (2.0, 2.3),
        marks: (21, 23)),
    EliteField.women: EliteRange(
        field: EliteField.women,
        weightKg: 4,
        speed: (13.0, 14.0),
        angleDeg: (34, 38),
        height: (1.8, 2.1),
        marks: (19, 21)),
  },
  ThrowEvent.discus: {
    EliteField.men: EliteRange(
        field: EliteField.men,
        weightKg: 2,
        speed: (23.5, 25.5),
        angleDeg: (33, 40),
        height: (1.5, 1.8),
        marks: (65, 70),
        attackDeg: -8),
    EliteField.women: EliteRange(
        field: EliteField.women,
        weightKg: 1,
        speed: (23.5, 25.5),
        angleDeg: (34, 40),
        height: (1.4, 1.7),
        marks: (63, 70),
        attackDeg: -8),
  },
  ThrowEvent.hammer: {
    EliteField.men: EliteRange(
        field: EliteField.men,
        weightKg: 7.26,
        speed: (27, 29.5),
        angleDeg: (37, 42),
        height: (1.3, 1.7),
        marks: (77, 82)),
    EliteField.women: EliteRange(
        field: EliteField.women,
        weightKg: 4,
        speed: (26, 28),
        angleDeg: (38, 42),
        height: (1.2, 1.6),
        marks: (72, 78)),
  },
  ThrowEvent.javelin: {
    EliteField.men: EliteRange(
        field: EliteField.men,
        weightKg: 0.8,
        speed: (28, 31),
        angleDeg: (32, 37),
        height: (1.7, 2.0),
        marks: (84, 90)),
    EliteField.women: EliteRange(
        field: EliteField.women,
        weightKg: 0.6,
        speed: (24, 26),
        angleDeg: (33, 38),
        height: (1.6, 1.9),
        marks: (62, 68)),
  },
};

/// The releases measured with [event]'s [weightKg] implement.
List<EliteRelease> eliteReleasesFor(ThrowEvent event, double weightKg) => [
      for (final r in eliteReleases)
        if (r.event == event && r.weightKg == weightKg) r
    ];
