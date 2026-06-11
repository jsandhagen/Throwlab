import 'package:flutter/material.dart';

enum Gender { men, women }

extension GenderLabel on Gender {
  String get label => this == Gender.men ? 'Men' : 'Women';
}

enum ThrowEvent { shotPut, discus, hammer, javelin }

/// The implement's regulated reference dimension, used for camera
/// calibration. All sizes are in meters.
class ImplementSpec {
  const ImplementSpec({
    required this.referenceLabel,
    required this.minSize,
    required this.maxSize,
  });

  /// What the dimension refers to, e.g. 'Ball diameter'.
  final String referenceLabel;
  final double minSize;
  final double maxSize;

  /// Midpoint of the legal range — the default calibration value.
  double get nominalSize => (minSize + maxSize) / 2;
}

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

  IconData get icon {
    switch (this) {
      case ThrowEvent.shotPut:
        return Icons.sports_baseball;
      case ThrowEvent.discus:
        return Icons.album;
      case ThrowEvent.hammer:
        return Icons.sports_handball;
      case ThrowEvent.javelin:
        return Icons.arrow_outward;
    }
  }

  ImplementSpec specFor(Gender gender) {
    switch (this) {
      case ThrowEvent.shotPut:
        return gender == Gender.men
            ? const ImplementSpec(
                referenceLabel: 'Ball diameter', minSize: 0.110, maxSize: 0.130)
            : const ImplementSpec(
                referenceLabel: 'Ball diameter', minSize: 0.095, maxSize: 0.110);
      case ThrowEvent.discus:
        return gender == Gender.men
            ? const ImplementSpec(
                referenceLabel: 'Disc diameter', minSize: 0.219, maxSize: 0.221)
            : const ImplementSpec(
                referenceLabel: 'Disc diameter', minSize: 0.180, maxSize: 0.182);
      case ThrowEvent.hammer:
        return gender == Gender.men
            ? const ImplementSpec(
                referenceLabel: 'Ball diameter', minSize: 0.102, maxSize: 0.120)
            : const ImplementSpec(
                referenceLabel: 'Ball diameter', minSize: 0.095, maxSize: 0.110);
      case ThrowEvent.javelin:
        return gender == Gender.men
            ? const ImplementSpec(
                referenceLabel: 'Length', minSize: 2.6, maxSize: 2.7)
            : const ImplementSpec(
                referenceLabel: 'Length', minSize: 2.2, maxSize: 2.3);
    }
  }
}
