enum ThrowEvent { shotPut, discus, hammer, javelin }

/// One legal implement: what it weighs, and the regulated dimension the
/// analyzer calibrates the camera against. All sizes are in metres.
///
/// Weight rather than a gender is what actually fixes those dimensions. A
/// 4 kg shot is 95–110 mm across whether it is a senior woman's, an U16
/// boy's or an M60's, and calling that "women's" both mis-sizes the
/// reference for everyone else throwing it and leaves masters throwers
/// picking whichever of two options is closer to wrong.
class ImplementSpec {
  const ImplementSpec({
    required this.weightKg,
    required this.referenceLabel,
    required this.minSize,
    required this.maxSize,
    required this.usedBy,
  });

  final double weightKg;

  /// What the dimension refers to, e.g. 'Ball diameter'.
  final String referenceLabel;
  final double minSize;
  final double maxSize;

  /// Who throws this weight, as a hint for picking it — the age grades that
  /// use it, not a rule the app enforces.
  final String usedBy;

  /// Midpoint of the legal range — the default calibration value.
  double get nominalSize => (minSize + maxSize) / 2;

  /// '7.26 kg', '600 g' — implements under a kilo are sold and spoken about
  /// in grams.
  String get weightLabel => weightKg < 1
      ? '${(weightKg * 1000).round()} g'
      : '${weightKg.toString().replaceFirst(RegExp(r'\.0$'), '')} kg';
}

/// Diameters and lengths are World Athletics' implement specifications; the
/// masters weights are the same implements, which is why they carry the
/// same dimensions. Where a weight has no World Athletics entry of its own
/// (the 0.75 kg discus, the 2 kg shot) it is thrown as the next size's
/// shell and is listed here as such.
const _shotPut = [
  ImplementSpec(
      weightKg: 7.26,
      referenceLabel: 'Ball diameter',
      minSize: 0.110,
      maxSize: 0.130,
      usedBy: 'Men, M35–M49'),
  ImplementSpec(
      weightKg: 6,
      referenceLabel: 'Ball diameter',
      minSize: 0.105,
      maxSize: 0.125,
      usedBy: 'U20 men, M50–M59'),
  ImplementSpec(
      weightKg: 5,
      referenceLabel: 'Ball diameter',
      minSize: 0.100,
      maxSize: 0.120,
      usedBy: 'U18 men, M60–M69'),
  ImplementSpec(
      weightKg: 4,
      referenceLabel: 'Ball diameter',
      minSize: 0.095,
      maxSize: 0.110,
      usedBy: 'Women, M70–M79, W35–W49'),
  ImplementSpec(
      weightKg: 3,
      referenceLabel: 'Ball diameter',
      minSize: 0.085,
      maxSize: 0.100,
      usedBy: 'M80+, W50–W74, U16'),
  ImplementSpec(
      weightKg: 2,
      referenceLabel: 'Ball diameter',
      minSize: 0.080,
      maxSize: 0.090,
      usedBy: 'W75+'),
];

const _discus = [
  ImplementSpec(
      weightKg: 2,
      referenceLabel: 'Disc diameter',
      minSize: 0.219,
      maxSize: 0.221,
      usedBy: 'Men, M35–M49'),
  ImplementSpec(
      weightKg: 1.75,
      referenceLabel: 'Disc diameter',
      minSize: 0.210,
      maxSize: 0.212,
      usedBy: 'U20 men, M50–M59'),
  ImplementSpec(
      weightKg: 1.5,
      referenceLabel: 'Disc diameter',
      minSize: 0.200,
      maxSize: 0.202,
      usedBy: 'U18 men, M60–M69'),
  ImplementSpec(
      weightKg: 1,
      referenceLabel: 'Disc diameter',
      minSize: 0.180,
      maxSize: 0.182,
      usedBy: 'Women, M70+, W35–W74'),
  ImplementSpec(
      weightKg: 0.75,
      referenceLabel: 'Disc diameter',
      minSize: 0.180,
      maxSize: 0.182,
      usedBy: 'W75+ (1 kg shell)'),
];

// A hammer's head is the shot of the same weight, so the diameters match.
// The wire and grip are not a calibration reference: they hang, bend and
// foreshorten, while the head is a sphere from every angle.
const _hammer = [
  ImplementSpec(
      weightKg: 7.26,
      referenceLabel: 'Head diameter',
      minSize: 0.110,
      maxSize: 0.130,
      usedBy: 'Men, M35–M49'),
  ImplementSpec(
      weightKg: 6,
      referenceLabel: 'Head diameter',
      minSize: 0.105,
      maxSize: 0.125,
      usedBy: 'U20 men, M50–M59'),
  ImplementSpec(
      weightKg: 5,
      referenceLabel: 'Head diameter',
      minSize: 0.100,
      maxSize: 0.120,
      usedBy: 'U18 men, M60–M69'),
  ImplementSpec(
      weightKg: 4,
      referenceLabel: 'Head diameter',
      minSize: 0.095,
      maxSize: 0.110,
      usedBy: 'Women, M70–M79, W35–W49'),
  ImplementSpec(
      weightKg: 3,
      referenceLabel: 'Head diameter',
      minSize: 0.085,
      maxSize: 0.100,
      usedBy: 'M80+, W50–W74, U16'),
  ImplementSpec(
      weightKg: 2,
      referenceLabel: 'Head diameter',
      minSize: 0.080,
      maxSize: 0.090,
      usedBy: 'W75+'),
];

const _javelin = [
  ImplementSpec(
      weightKg: 0.8,
      referenceLabel: 'Length',
      minSize: 2.6,
      maxSize: 2.7,
      usedBy: 'Men, M35–M49'),
  ImplementSpec(
      weightKg: 0.7,
      referenceLabel: 'Length',
      minSize: 2.3,
      maxSize: 2.4,
      usedBy: 'M50–M59, U18 men'),
  ImplementSpec(
      weightKg: 0.6,
      referenceLabel: 'Length',
      minSize: 2.2,
      maxSize: 2.3,
      usedBy: 'Women, M60–M69, W35–W49'),
  ImplementSpec(
      weightKg: 0.5,
      referenceLabel: 'Length',
      minSize: 2.2,
      maxSize: 2.3,
      usedBy: 'M70+, W50–W74'),
  ImplementSpec(
      weightKg: 0.4,
      referenceLabel: 'Length',
      minSize: 2.0,
      maxSize: 2.1,
      usedBy: 'W75+'),
];

extension ThrowEventInfo on ThrowEvent {
  String get label {
    switch (this) {
      case ThrowEvent.shotPut:
        return 'Shot Put';
      case ThrowEvent.discus:
        return 'Discus';
      case ThrowEvent.hammer:
        return 'Hammer';
      case ThrowEvent.javelin:
        return 'Javelin';
    }
  }

  /// Every weight this event is thrown at, heaviest first.
  List<ImplementSpec> get implements {
    switch (this) {
      case ThrowEvent.shotPut:
        return _shotPut;
      case ThrowEvent.discus:
        return _discus;
      case ThrowEvent.hammer:
        return _hammer;
      case ThrowEvent.javelin:
        return _javelin;
    }
  }

  /// What a new import starts on: the senior implement, the one most clips
  /// will be.
  ImplementSpec get defaultImplement => implements.first;

  /// The spec for [weightKg], or the nearest weight this event is thrown
  /// at. Nothing in the app can produce a weight off the list, but a
  /// hand-edited store or a spec table that changes under an old import
  /// shouldn't leave a throw with no reference dimension.
  ImplementSpec specFor(double weightKg) {
    var closest = implements.first;
    for (final spec in implements) {
      if (spec.weightKg == weightKg) return spec;
      if ((spec.weightKg - weightKg).abs() <
          (closest.weightKg - weightKg).abs()) {
        closest = spec;
      }
    }
    return closest;
  }
}
