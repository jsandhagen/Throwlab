// Renders the results sheet to a PDF — the file a coach hands out at the
// end of a Saturday — so it can be read without a meet, a phone or a
// printer.
//
//   flutter test tool/preview/report_preview.dart
//
// The file lands at build/preview/results_sheet.pdf (gitignored). Open it.
// Unlike the screen previews this asserts nothing and writes no golden: a
// PDF is the artifact, and looking at it is the review.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/meet_report.dart';

const _out = 'build/preview';

final _date = DateTime(2026, 6, 13);

/// A day at a championship: a discus cut to a final, a men's shot thrown in
/// two flights, and a javelin where the coach's own athlete put out the
/// furthest throw of her life.
void main() {
  test('results sheet', () async {
    final results = <ThrowResult>[];
    var id = 0;

    /// A mark in the record book, and the attempt that points at it.
    MeetAttempt mark(String athlete, ThrowEvent event, double kg, double m,
        {DistanceUnit unit = DistanceUnit.meters, DateTime? on}) {
      final made = ThrowMark(
        id: 'm${id++}',
        athlete: athlete,
        event: event,
        implementKg: kg,
        distance: m,
        distanceUnit: unit,
        achievedOn: on ?? _date,
        note: 'County Champs',
      );
      results.add(made);
      return MeetAttempt.mark(made.id);
    }

    final meet = Meet(
      id: 'k1',
      name: 'County Championships',
      date: _date,
      venue: 'Sportcity',
      rounds: 6,
      prelimRounds: 3,
      advancing: 8,
      conditions: const MeetConditions(
        sky: MeetSky.overcast,
        temperature: 54,
        wind: MeetWind.head,
        note: 'gusting down the runway',
      ),
    );

    var order = 0;
    MeetEntry enter(String athlete, ThrowEvent event, double kg,
        {bool tracked = false, int flight = 1}) {
      final made = MeetEntry(
        id: 'e${order + 1}',
        athlete: athlete,
        event: event,
        implementKg: kg,
        tracked: tracked,
        order: order++,
        flight: flight,
      );
      meet.entries.add(made);
      return made;
    }

    // The women's discus: nine in the field, cut to eight, and the winner
    // found it in the last round.
    const discus = [
      ('Ana Diaz', true, [41.20, null, 43.06, 42.10, null, 44.55]),
      ('M. Okoye (Barnet)', false, [44.12, null, 44.90, 43.00, 44.20, null]),
      ('L. Fischer (Brighton)', false, [43.20, 42.06, 41.90, null, 43.80, 42.00]),
      ('S. Patel (Ealing)', false, [39.80, null, 40.12, 40.90, null, 41.05]),
      ('K. Fox (Sale)', false, [38.44, 39.10, 38.90, 37.20, null, 39.55]),
      ('R. Novak (Prague)', false, [37.10, 36.80, 38.02, null, 37.55, null]),
      ('E. Haugen (Bergen)', false, [36.90, null, 35.40, 36.10, 36.44, null]),
      ('C. Barros (Porto)', false, [35.20, 34.90, 36.05, null, null, 35.80]),
      ('P. Moreau (Lyon)', false, [31.40, 30.90, 32.10]),
    ];
    for (final (athlete, tracked, series) in discus) {
      final entry = enter(athlete, ThrowEvent.discus, 1, tracked: tracked);
      for (var round = 0; round < series.length; round++) {
        final thrown = series[round];
        entry.setAttempt(
            round,
            thrown == null
                ? MeetAttempt.foul()
                : tracked
                    ? mark(athlete, ThrowEvent.discus, 1, thrown)
                    : MeetAttempt.untracked(thrown));
      }
    }
    // An older, further discus, so Ana's 44.55 is not a personal best.
    results.add(ThrowMark(
      id: 'm-old',
      athlete: 'Ana Diaz',
      event: ThrowEvent.discus,
      implementKg: 1,
      distance: 45.90,
      achievedOn: DateTime(2026, 5, 2),
      note: 'Spring Open',
    ));

    // The men's shot, thrown in two flights of five.
    const shot = [
      (1, 'B. Kowalski (Poznan)', [17.90, 18.22, null]),
      (1, 'N. Achebe (Croydon)', [17.44, null, 17.60]),
      (1, 'E. Haugen (Bergen)', [16.80, 17.02, 16.95]),
      (1, 'C. Barros (Porto)', [16.55, null, 16.70]),
      (1, 'D. Whitcombe (Leeds)', [16.10, 16.30, null]),
      (2, 'T. Brandt (Kiel)', [17.20, 17.85, null]),
      (2, 'R. Novak (Prague)', [16.44, 16.90, 17.10]),
      (2, 'A. Lindqvist (Umea)', [15.90, 16.20, null]),
      (2, 'P. Moreau (Lyon)', [15.40, null, 15.75]),
    ];
    for (final (flight, athlete, series) in shot) {
      final entry =
          enter(athlete, ThrowEvent.shotPut, 7.26, flight: flight);
      for (var round = 0; round < series.length; round++) {
        final thrown = series[round];
        entry.setAttempt(
            round,
            thrown == null
                ? MeetAttempt.foul()
                : MeetAttempt.untracked(thrown));
      }
    }

    // The javelin, measured in feet the way this meet measured it, with a
    // personal best in the third round.
    final jakob = enter('Jakob Sandhagen', ThrowEvent.javelin, 0.8,
        tracked: true);
    jakob
      ..setAttempt(
          0,
          mark('Jakob Sandhagen', ThrowEvent.javelin, 0.8, 58.34,
              unit: DistanceUnit.feet))
      ..setAttempt(1, MeetAttempt.foul())
      ..setAttempt(
          2,
          mark('Jakob Sandhagen', ThrowEvent.javelin, 0.8, 61.02,
              unit: DistanceUnit.feet))
      ..setAttempt(3, MeetAttempt.pass());
    for (final (athlete, series) in const [
      ('T. Brandt (Kiel)', [60.40, 59.12, null]),
      ('D. Whitcombe (Leeds)', [57.20, 58.90, 58.10]),
    ]) {
      final entry = enter(athlete, ThrowEvent.javelin, 0.8);
      for (var round = 0; round < series.length; round++) {
        final thrown = series[round];
        entry.setAttempt(
            round,
            thrown == null
                ? MeetAttempt.foul()
                : MeetAttempt.untracked(thrown));
      }
    }

    final bytes =
        meetResultsPdf(meet, results, printedOn: DateTime(2026, 6, 13, 17, 40));
    await Directory(_out).create(recursive: true);
    final file = File('$_out/results_sheet.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('wrote ${file.path} (${bytes.length} bytes)');
  });
}
