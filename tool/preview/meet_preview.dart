// Renders the meet tracker to PNGs — the competitions, one in progress, and
// the sheet a round is entered in — so the screens can be reviewed without
// an emulator or a track.
//
//   flutter test --update-goldens tool/preview/meet_preview.dart
//
// Images land in build/preview/ (gitignored). Same shape as home_preview.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/screens/meets_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';

import 'harness.dart';

const _out = '../../build/preview';

/// A meet part-way through: three throwers, a series each, and the mix of
/// marks, fouls and passes a real results sheet is made of.
final _date = DateTime(2026, 6, 13);

List<Map<String, dynamic>> _marks() => [
      // Anna Sofia's discus: an opener, a foul, then the winning throw.
      _mark('mk1', 'Anna Sofia', ThrowEvent.discus, 1, 41.20),
      _mark('mk2', 'Anna Sofia', ThrowEvent.discus, 1, 43.06),
      // Jakob's javelin, in feet, the way his meet measured.
      _mark('mk3', 'Jakob', ThrowEvent.javelin, 0.8, 58.34, feet: true),
      _mark('mk4', 'Jakob', ThrowEvent.javelin, 0.8, 61.02, feet: true),
      // Priya's shot, one round in.
      _mark('mk5', 'Priya Raman', ThrowEvent.shotPut, 4, 13.88),
      // An older, further discus so Anna's meet best is not a PB.
      ThrowMark(
        id: 'mk-old',
        athlete: 'Anna Sofia',
        event: ThrowEvent.discus,
        implementKg: 1,
        distance: 44.90,
        achievedOn: DateTime(2026, 5, 2),
        note: 'Spring Open',
      ).toJson(),
    ];

Map<String, dynamic> _mark(String id, String athlete, ThrowEvent event,
        double kg, double distance, {bool feet = false}) =>
    ThrowMark(
      id: id,
      athlete: athlete,
      event: event,
      implementKg: kg,
      distance: distance,
      distanceUnit: feet ? DistanceUnit.feet : DistanceUnit.metres,
      achievedOn: _date,
      note: 'County Champs',
    ).toJson();

List<Map<String, dynamic>> _meets() {
  final champs = Meet(
    id: 'k1',
    name: 'County Champs',
    date: _date,
    rounds: 6,
    advancing: 2,
  );

  final anna = MeetEntry(
      id: 'e1',
      athlete: 'Anna Sofia',
      event: ThrowEvent.discus,
      implementKg: 1,
      order: 0)
    ..setAttempt(0, MeetAttempt.mark('mk1'))
    ..setAttempt(1, MeetAttempt.foul())
    ..setAttempt(2, MeetAttempt.mark('mk2'))
    ..setAttempt(3, MeetAttempt.foul());

  final jakob = MeetEntry(
      id: 'e2',
      athlete: 'Jakob',
      event: ThrowEvent.javelin,
      implementKg: 0.8,
      order: 2)
    ..setAttempt(0, MeetAttempt.mark('mk3'))
    ..setAttempt(1, MeetAttempt.mark('mk4'))
    ..setAttempt(2, MeetAttempt.pass());

  final priya = MeetEntry(
      id: 'e3',
      athlete: 'Priya Raman',
      event: ThrowEvent.shotPut,
      implementKg: 4,
      order: 4)
    ..setAttempt(0, MeetAttempt.mark('mk5'));

  // The rest of the discus field: not the coach's athletes, so their marks
  // live on the attempts and never reach the library.
  MeetEntry rival(String id, String name, int order, List<double?> marks) {
    final entry = MeetEntry(
      id: id,
      athlete: name,
      event: ThrowEvent.discus,
      implementKg: 1,
      tracked: false,
      order: order,
    );
    for (var round = 0; round < marks.length; round++) {
      entry.setAttempt(
          round,
          marks[round] == null
              ? MeetAttempt.foul()
              : MeetAttempt.untracked(marks[round]!));
    }
    return entry;
  }

  champs.entries.addAll([
    anna,
    rival('r1', 'M. Okoye (Barnet)', 1, [44.12, null, 44.90]),
    jakob,
    rival('r2', 'L. Fischer (Brighton)', 3, [43.20, 42.06]),
    priya,
    rival('r3', 'S. Patel (Ealing)', 5, [39.80, null]),
  ]);

  final spring = Meet(
    id: 'k0',
    name: 'Spring Open',
    date: DateTime(2026, 5, 2),
    rounds: 4,
  )..entries.add(MeetEntry(
      id: 'e0',
      athlete: 'Anna Sofia',
      event: ThrowEvent.discus,
      implementKg: 1)
    ..setAttempt(0, MeetAttempt.mark('mk-old')));

  return [champs.toJson(), spring.toJson()];
}

void main() {
  testWidgets('meet tracker', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.marks': jsonEncode(_marks()),
      'flutter.throwlab.meets': jsonEncode(_meets()),
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final library = VideoLibrary();
    await library.load();
    final meets = MeetLibrary();
    await meets.load();

    // The meets, as the trophy opens them on a day with nothing on.
    await _shoot(tester, library, meets, const MeetsScreen(), 'meets_list');

    // The competition itself, part-way through.
    await _shoot(tester, library, meets,
        const MeetScreen(meetId: 'k1'), 'meet_tracker');

    // Where the competition stands, with the cut and what it takes to
    // get past it.
    await tester.tap(find.text('Standings'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/meet_standings.png'));
    await tester.tap(find.text('Series'));
    await settle(tester);

    // The sheet a round is entered in, as it opens on a filmed attempt.
    await tester.tap(find.byKey(const ValueKey('round-4')).first);
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/meet_attempt.png'));
  });
}

Future<void> _shoot(WidgetTester tester, VideoLibrary library,
    MeetLibrary meets, Widget screen, String file) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: MaterialApp(theme: ThrowLabApp.theme, home: screen),
    ),
  );
  await settle(tester);
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$file.png'));
}
