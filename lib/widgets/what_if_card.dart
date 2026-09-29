import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/flight_model.dart';
import 'event_glyph.dart';
import 'flight_field.dart';
import 'logo_mark.dart';
import 'sector_art.dart';
import 'throw_card.dart';

/// One of the two throws on a what-if card: whose it is, how it left the
/// hand, and where it went.
class WhatIfSide {
  const WhatIfSide({
    required this.name,
    required this.release,
    required this.flight,
  });

  final String name;
  final Release release;
  final Flight flight;
}

/// A what-if written down to be sent: the question the calculator was
/// asked, with its answer, as a picture somebody can open in a chat.
///
/// Everything on it is already worked out — the flights, the gap's shares —
/// so the card is a rendering and never a second run of the model.
class WhatIfCard extends StatelessWidget {
  const WhatIfCard({
    super.key,
    required this.event,
    required this.spec,
    required this.unit,
    required this.baseline,
    required this.whatIf,
    required this.shares,
    this.speedLossPerDeg = 0,
    this.speedLossEstimated = true,
    this.date,
  });

  /// The width the card is laid out at. A share is looked at on a phone,
  /// so it is a phone's width, and the image is written at its pixels.
  static const width = 360.0;

  final ThrowEvent event;
  final ImplementSpec spec;
  final DistanceUnit unit;
  final WhatIfSide baseline;
  final WhatIfSide whatIf;
  final Map<Lever, double> shares;
  final double speedLossPerDeg;

  /// Whether [speedLossPerDeg] is the event's own estimate rather than a
  /// number the coach set, which the card has to say: it is the assumption
  /// that moves an angle's row the most.
  final bool speedLossEstimated;
  final DateTime? date;

  bool get _feet => unit == DistanceUnit.feet;

  String _speed(double mps) => _feet
      ? '${(mps / 0.44704).toStringAsFixed(1)} mph'
      : '${mps.toStringAsFixed(1)} m/s';

  String _height(double m) =>
      _feet ? formatDistance(m, unit) : '${m.toStringAsFixed(2)} m';

  String _release(Release r) =>
      '${_speed(r.speed)} · ${r.angleDeg.toStringAsFixed(1)}° · '
      '${_height(r.height)}';

  String _signed(double v, int digits) {
    final s = v.abs().toStringAsFixed(digits);
    if (double.parse(s) == 0) return s;
    return '${v > 0 ? '+' : '−'}$s';
  }

  String _mark(double m) {
    final s = formatDistance(m.abs(), unit);
    if (s == formatDistance(0, unit)) return s;
    return '${m > 0 ? '+' : '−'}$s';
  }

  String _change(Lever l) {
    final a = baseline.release;
    final b = whatIf.release;
    final carried = -speedLossPerDeg * (b.angleDeg - a.angleDeg);
    final perSpeed = _feet ? 0.44704 : 1.0;
    final speedUnit = _feet ? 'mph' : 'm/s';
    return switch (l) {
      Lever.speed =>
        '${_signed((b.speed - a.speed - carried) / perSpeed, 1)} $speedUnit',
      Lever.angle => '${_signed(b.angleDeg - a.angleDeg, 1)}°'
          '${carried.abs() < 0.005 ? '' : ' at ${_signed(carried / perSpeed, 1)} $speedUnit'}',
      Lever.height => _feet
          ? '${_signed((b.height - a.height) / 0.0254, 1)} in'
          : '${_signed(b.height - a.height, 2)} m',
      Lever.attack => '${_signed(b.attackDeg - a.attackDeg, 1)}°',
      Lever.wind => '${_signed((b.wind - a.wind) / perSpeed, _feet ? 0 : 1)} '
          '$speedUnit',
      Lever.pitchRate => '${_signed(b.pitchRate - a.pitchRate, 0)}°/s',
    };
  }

  static String _lever(Lever l) => switch (l) {
        Lever.speed => 'Speed',
        Lever.angle => 'Angle',
        Lever.height => 'Height',
        Lever.attack => 'Attack',
        Lever.wind => 'Wind',
        Lever.pitchRate => 'Pitch rate',
      };

  /// What the answer rests on, said in the order it matters. The trade
  /// between speed and angle leads, since it decides whether a change of
  /// angle reads as a gain at all, and it is the one a reader cannot see
  /// in the two releases printed above it.
  List<(String, String)> _assumptions() {
    final perSpeed = _feet ? 0.44704 : 1.0;
    final speedUnit = _feet ? 'mph' : 'm/s';
    final a = baseline.release;
    final b = whatIf.release;
    final String trade;
    if (speedLossPerDeg == 0) {
      trade = 'Speed is held whatever the angle. No athlete keeps their '
          'speed going higher, so a steeper what-if reads long.';
    } else {
      final per10 = (speedLossPerDeg * 10 / perSpeed).toStringAsFixed(1);
      final turned = b.angleDeg - a.angleDeg;
      final carried = (speedLossPerDeg * turned / perSpeed).abs();
      final here = turned.abs() < 0.05
          ? ''
          : ' Here ${_signed(turned, 1)}° ${turned < 0 ? 'gave back' : 'cost'} '
              '${carried.toStringAsFixed(1)} $speedUnit, which is in the '
              "angle's row above.";
      // Whose measurement the number is scaled from, per event: nobody
      // published one figure, so the card names where it came from.
      final source = switch (event) {
        ThrowEvent.javelin => 'scaled from Red and Zogaib on javelin throwers',
        ThrowEvent.shotPut => "from Linthorne's college shot putters",
        ThrowEvent.discus => "carried across from Linthorne's shot putters",
        ThrowEvent.hammer =>
          'backed out of the angles elite throwers release at',
      };
      trade = 'Every 10° steeper costs $per10 $speedUnit of release speed, '
          'so a flatter release is a faster one.$here '
          '${speedLossEstimated ? 'An estimate $source, not measured on this '
              'athlete.' : 'Set by the coach.'}';
    }
    final wind = a.wind == 0 && b.wind == 0
        ? 'Still air. A head or tail wind would move both throws.'
        : 'Wind along the throw: ${_windWords(a.wind)} for the baseline, '
            '${_windWords(b.wind)} for the what-if.';
    final implement = switch (event) {
      ThrowEvent.javelin => 'Drag, lift and pitch measured in a wind tunnel '
          "on a women's 600 g javelin (Seo et al. 2023). Every weight flies "
          'on that table at its own length and thickness.',
      ThrowEvent.discus => 'Flown spinning and released banked, with lift '
          'and drag after Hubbard and Cheng. The spin and bank are typical '
          "values, not this athlete's.",
      ThrowEvent.shotPut =>
        'A sphere with drag. At a shot\'s speed the air costs it little.',
      ThrowEvent.hammer => 'The head as a sphere with drag. The wire and '
          "handle's drag is left out, so it reads a little long.",
    };
    return [
      ('Speed and angle', trade),
      ('Air', wind),
      ('Implement', implement),
      (
        'Distance',
        'Measured from the hand at release. A tape run from the stop board '
            'or foul line reads a little further.'
      ),
    ];
  }

  String _windWords(double v) {
    if (v == 0) return 'still';
    final size = _feet
        ? '${(v.abs() / 0.44704).toStringAsFixed(0)} mph'
        : '${v.abs().toStringAsFixed(1)} m/s';
    return '$size ${v > 0 ? 'tail' : 'head'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final label = theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant);
    final gap = whatIf.flight.distance - baseline.flight.distance;
    final same = formatDistance(gap.abs(), unit) == formatDistance(0, unit);
    final gapColor = same
        ? scheme.onSurface
        : gap > 0
            ? scheme.primary
            : scheme.error;
    final surface = solidCardOverSector(scheme);
    final order = shares.keys.toList()
      ..sort((x, y) => shares[y]!.abs().compareTo(shares[x]!.abs()));

    Widget side(WhatIfSide s, String role, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: role,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(
                            text: ' · ${s.name}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ]),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(_release(s.release), style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('≈ ${formatDistance(s.flight.distance, unit)}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return SizedBox(
      width: width,
      child: ColoredBox(
        color: scheme.surface,
        child: CustomPaint(
          painter: SectorBackdropPainter(color: scheme.primary),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    EventGlyph(event, size: 22, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${event.label} · ${spec.weightLabel}',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (date != null)
                      Text(
                          '${date!.year}-${date!.month.toString().padLeft(2, '0')}'
                          '-${date!.day.toString().padLeft(2, '0')}',
                          style: muted),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  color: surface,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('WHAT IF',
                            style: label?.copyWith(color: scheme.primary)),
                        Text('≈ ${_mark(gap)}',
                            style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w700, color: gapColor)),
                        Text(
                            same
                                ? 'the same as the baseline'
                                : gap > 0
                                    ? 'further than the baseline'
                                    : 'shorter than the baseline',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        FlightField(
                          event: event,
                          unit: unit,
                          backdrop: surface,
                          maxHeight: 170,
                          flights: [
                            FieldFlight(
                                baseline.flight, scheme.onSurfaceVariant),
                            FieldFlight(whatIf.flight, scheme.primary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        side(baseline, 'Baseline', scheme.onSurfaceVariant),
                        side(whatIf, 'What if', scheme.primary),
                        if (order.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Text('WHERE THE GAP COMES FROM', style: label),
                          const SizedBox(height: 4),
                          for (final l in order)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: _lever(l)),
                                        TextSpan(
                                            text: '  ${_change(l)}',
                                            style: muted),
                                      ]),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    _mark(shares[l]!),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: shares[l]! >= 0
                                          ? scheme.primary
                                          : scheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Text('ASSUMPTIONS', style: label),
                        const SizedBox(height: 4),
                        for (final (title, body) in _assumptions())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: '$title  ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface)),
                                TextSpan(text: body),
                              ]),
                              style: muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const LogoMark(height: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'An estimate from ThrowLab\'s flight model — a '
                        'guide, not a reference.',
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
