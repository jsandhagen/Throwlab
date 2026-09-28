import 'throw_event.dart';

/// A release measured on a real elite thrower at a championship, for the
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

/// The elite implement whose throwers stand as the reference for
/// [event]'s [weightKg] one, or null where there are none.
///
/// The senior implements are their own. A boys' or junior men's implement —
/// anything lighter than the men's and heavier than the women's, the
/// 12 lb and 5 kg shots, the 1.6 kg discus, the 700 g javelin — takes the
/// men's: what carries across is the release, its speed and angle, and a
/// boy is working towards a man's, not a woman's. Lighter than the
/// women's is masters and the youngest grades, and nobody elite is thrown
/// with anything like it.
double? eliteWeightFor(ThrowEvent event, double weightKg) {
  final ranges = eliteRanges[event]!;
  final men = ranges[EliteField.men]!.weightKg;
  final women = ranges[EliteField.women]!.weightKg;
  if (weightKg == men || weightKg == women) return weightKg;
  if (weightKg < men && weightKg > women) return men;
  return null;
}

/// The typical elite release that stands as the reference for [event]'s
/// [weightKg] implement (`eliteWeightFor`), or null where there is none.
EliteRange? eliteRangeFor(ThrowEvent event, double weightKg) {
  final elite = eliteWeightFor(event, weightKg);
  if (elite == null) return null;
  for (final r in eliteRanges[event]!.values) {
    if (r.weightKg == elite) return r;
  }
  return null;
}

/// The elite range thrown with the implement nearest [weightKg], for a
/// release to start from where there is none of its own.
EliteRange nearestEliteRange(ThrowEvent event, double weightKg) =>
    eliteRanges[event]!.values.reduce((a, b) =>
        (a.weightKg - weightKg).abs() <= (b.weightKg - weightKg).abs() ? a : b);

/// The releases measured with [event]'s [weightKg] implement.
List<EliteRelease> eliteReleasesFor(ThrowEvent event, double weightKg) => [
      for (final r in eliteReleases)
        if (r.event == event && r.weightKg == weightKg) r
    ];

/// The named elite releases that stand as the reference for [event]'s
/// [weightKg] implement: its own, or the men's for a boys' implement.
List<EliteRelease> eliteReferencesFor(ThrowEvent event, double weightKg) {
  final elite = eliteWeightFor(event, weightKg);
  return elite == null ? const [] : eliteReleasesFor(event, elite);
}

/// The papers the flight model and the typical ranges lean on, and what
/// each was used for. The measured releases cite their own reports
/// ([EliteRelease.source]); this is the rest.
const whatIfSources = <({String citation, String usedFor})>[
  (
    citation: 'Red, W. E., & Zogaib, A. J. (1977). Javelin dynamics '
        'including body interaction. Journal of Applied Mechanics, 44(3), '
        '496–498.',
    usedFor: "Why an athlete's best angle sits below the flight's: release "
        'speed falls as the release angle rises. Measured on javelin '
        'throwers, and the method the best-angle search follows. The '
        "javelin's speed lost per degree is an estimate scaled from their "
        'finding, not a figure they published.',
  ),
  (
    citation: 'Linthorne, N. P. (2001). Optimum release angle in the shot '
        'put. Journal of Sports Sciences, 19(5), 359–372.',
    usedFor: 'The same fall in release speed measured on shot putters. The '
        "shot's speed lost per degree is estimated from the 1.7 (m/s)/rad "
        "reported for his college putters, and the discus's from the same "
        'share of release speed, at a discus\'s speed.',
  ),
  (
    citation: 'Castaldi, G. M., Borzuola, R., Camomilla, V., Bergamini, E., '
        'Vannozzi, G., & Macaluso, A. (2022). Biomechanics of the hammer '
        'throw: narrative review. Frontiers in Sports and Active Living, 4, '
        '853536.',
    usedFor: 'Why elite hammer throwers release under the flight\'s best '
        'angle: a steeper release costs speed. The hammer\'s speed lost per '
        'degree is set so its best angle lands where they release, not a '
        'figure the review gives.',
  ),
  (
    citation: 'Leigh, S., Liu, H., Hubbard, M., & Yu, B. (2010). '
        'Individualized optimal release angles in discus throwing. Journal '
        'of Biomechanics, 43(3), 540–545.',
    usedFor: 'That discus throwers release slower as they release higher, '
        "and by different amounts each — why the discus's speed lost per "
        'degree is an estimate best replaced by an athlete\'s own.',
  ),
  (
    citation: 'Seo, K., Okuizumi, H., Konishi, Y., Kobayashi, T., Hasegawa, '
        'H., & Obayashi, S. (2023). Measurement of aerodynamic force and '
        'moment acting on a javelin using a magnetic suspension and balance '
        'system. Scientific Reports, 13, 391.',
    usedFor: 'The javelin\'s drag, lift and pitching moment, read off '
        "their Fig. 10 for a women's 600 g javelin, unsupported, at 25 m/s. "
        'Every javelin weight flies on these.',
  ),
  (
    citation: 'Chowdhury, H., Alam, F., Muscara, A., & Mustary, I. (2013). '
        'An experimental study of new rule javelins. Procedia Engineering, '
        '60, 485–490.',
    usedFor: "The men's 800 g javelin's thickness, which sets how much air "
        'it meets on the measured coefficients.',
  ),
  (
    citation: 'Frohlich, C. (1981). Aerodynamic effects on discus flight. '
        'American Journal of Physics, 49(12), 1125–1132.',
    usedFor: 'The shape of the discus lift and drag curves, and why a '
        'headwind helps a discus.',
  ),
  (
    citation: 'Hubbard, M., & Cheng, K. B. (2007). Optimal discus '
        'trajectories. Journal of Biomechanics, 40(16), 3650–3659.',
    usedFor: "The discus's flight in three dimensions: the pitching moment's "
        'slope (0.007 per degree), the spin and the bank at release, the '
        'roll the spin turns the moment into, and the best release (38.4°, '
        '69.4 m at 25 m/s) the model is checked against.',
  ),
  (
    citation: 'Bartlett, R. M., & Best, R. J. (1988). The biomechanics of '
        'javelin throwing: a review. Journal of Sports Sciences, 6(1), '
        '1–38.',
    usedFor: 'Javelin release ranges for the typical elite thrower.',
  ),
];
