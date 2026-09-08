// Renders the season list three ways so the layouts can be compared side by
// side — a date rail, a hero for the next fixture, and cards.
//
//   flutter test --update-goldens tool/preview/season_preview.dart
//
// Images land in build/preview/ (gitignored). Same shape as meet_preview.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/screens/meets_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';

import 'harness.dart';

const _out = '../../build/preview';

final _now = DateTime.now();
DateTime _days(int days) => _now.add(Duration(days: days));

void main() {
  testWidgets('the season, three ways', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final library = VideoLibrary();
    await library.load();
    final meets = MeetLibrary();
    await meets.load();

    // Marks behind the attempts, so a meet already thrown has a best to
    // show rather than only a count.
    var mark = 0;
    Future<String> throwOf(String athlete, ThrowEvent event, double kg,
        double distance, DateTime on) async {
      final id = 'mk${mark++}';
      await library.addMark(ThrowMark(
        id: id,
        athlete: athlete,
        event: event,
        implementKg: kg,
        distance: distance,
        achievedOn: on,
      ));
      return id;
    }

    Future<void> thrown(String meetId, String athlete, ThrowEvent event,
        double kg, List<double> series, DateTime on) async {
      final entry = MeetEntry(
        id: 'e${mark}_$meetId',
        athlete: athlete,
        event: event,
        implementKg: kg,
        order: meets.byId(meetId)!.entries.length,
      );
      for (var round = 0; round < series.length; round++) {
        entry.setAttempt(
            round,
            series[round] == 0
                ? MeetAttempt.foul()
                : MeetAttempt.mark(
                    await throwOf(athlete, event, kg, series[round], on)));
      }
      await meets.addEntry(meetId, entry: entry);
    }

    // Two behind, one on today, three ahead.
    await meets.save(Meet(
        id: 'past2',
        name: 'Indoor Open',
        date: _days(-61),
        venue: 'Lee Valley'));
    await thrown('past2', 'Priya Raman', ThrowEvent.shotPut, 4,
        [12.88, 0, 13.10], _days(-61));

    await meets.save(Meet(
        id: 'past1',
        name: 'Winter Throws',
        date: _days(-26),
        venue: 'Loughborough'));
    await thrown('past1', 'Jakob Sandhagen', ThrowEvent.shotPut, 5,
        [14.02, 14.55, 0], _days(-26));
    await thrown('past1', 'Ana Sofia', ThrowEvent.discus, 1,
        [41.20, 0, 43.06], _days(-26));

    await meets.save(Meet(
        id: 'today', name: 'Club Open', date: _now, venue: 'Sportcity'));
    await thrown('today', 'Ana Sofia', ThrowEvent.discus, 1, [44.90], _now);
    await thrown('today', 'Jakob Sandhagen', ThrowEvent.javelin, 0.8,
        [58.34], _now);

    await meets.save(Meet(
        id: 'soon',
        name: 'Spring Open',
        date: _days(5),
        venue: 'Sportcity'));
    await meets.save(Meet(
        id: 'champs',
        name: 'County Championships',
        date: _days(23),
        venue: 'Alexander Stadium'));
    await meets.save(Meet(
        id: 'tigers',
        name: 'Tiger Relays',
        date: DateTime(_now.year + 1, 3, 13),
        venue: 'Auburn, AL'));

    for (final layout in MeetsLayout.values) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VideoLibrary>.value(value: library),
            ChangeNotifierProvider<MeetLibrary>.value(value: meets),
          ],
          child: MaterialApp(
            theme: ThrowLabApp.theme,
            home: MeetsScreen(layout: layout),
          ),
        ),
      );
      await settle(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('$_out/season_${layout.name}.png'));
    }
  });
}
