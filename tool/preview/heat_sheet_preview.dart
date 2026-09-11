// Renders the heat sheet import to PNGs — the page a program is pasted
// into, the events it found, one of them opened on its field, and the meet
// it leaves entered — so the screens can be reviewed without an emulator or
// a track.
//
//   flutter test --update-goldens tool/preview/heat_sheet_preview.dart
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
import 'package:throwlab/models/athlete_record.dart';
import 'package:throwlab/screens/heat_sheet_import_screen.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/services/athlete_library.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';

import 'harness.dart';

const _out = '../../build/preview';

/// A program as a meet manager prints one: two throws events among the
/// running, in columns, with the shot put's field split into the two
/// flights it is actually thrown in and a rule under each heading.
const _sheet = '''
                    Central Invitational - 13 June 2026
                          Meet Program

Event 15  Boys Shot Put 12lb
=======================================================================
    Name                    Year School                  Seed Mark
=======================================================================
Flight  1 of  2
  1 Smith, John                 12 Northside             44-06.00
  2 SANDHAGEN, J                12 Central HS            48-02.50
  3 Fischer, Liam               11 Brighton              41-09.25
Flight  2 of  2
  4 Okonkwo, David              12 Eastside              50-01.00
  5 Brandt, Tomas               12 Kiel Gym              47-03.50
  6 Novak, Radek                11 Prague Int            45-10.00

Event 16  Girls Discus
=======================================================================
  1 Diaz, Ana                   11 Central HS            41.20m
  2 Raman, Priya                12 Central HS            38.90m
  3 Fischer, L                  11 Brighton              37.15m

Event 17  Boys 4x100 Meter Relay
=======================================================================
  1 Central HS                                              43.55
''';

void main() {
  testWidgets('heat sheet import', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final meets = MeetLibrary();
    await meets.load();
    await meets.save(Meet(
      id: 'k1',
      name: 'Central Invitational',
      date: DateTime(2026, 6, 13),
      venue: 'Central HS',
      rounds: 6,
      prelimRounds: 3,
    ));

    // The coach's own throwers, known to the library from their marks.
    final library = VideoLibrary();
    await library.load();
    var id = 0;
    for (final athlete in ['Jakob Sandhagen', 'Ana Diaz', 'Priya Raman']) {
      await library.addMark(ThrowMark(
        id: 'm${id++}',
        athlete: athlete,
        event: ThrowEvent.shotPut,
        implementKg: 5,
        distance: 13.5,
        achievedOn: DateTime(2026, 5, 2),
      ));
    }
    // Another of theirs, filed under a nickname a sheet would never print —
    // matched off the full name and school on their record instead.
    await library.addMark(ThrowMark(
      id: 'm${id++}',
      athlete: 'Dave',
      event: ThrowEvent.shotPut,
      implementKg: 5,
      distance: 15.2,
      achievedOn: DateTime(2026, 5, 2),
    ));
    final athletes = AthleteLibrary();
    await athletes.load();
    await athletes.save(const AthleteRecord(
        name: 'Dave', fullName: 'David Okonkwo', school: 'Eastside'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VideoLibrary>.value(value: library),
          ChangeNotifierProvider<MeetLibrary>.value(value: meets),
          ChangeNotifierProvider<AthleteLibrary>.value(value: athletes),
        ],
        child: MaterialApp(
          theme: ThrowLabApp.theme,
          home: const MeetScreen(meetId: 'k1'),
        ),
      ),
    );
    await settle(tester);

    // Pushed the way the meet's app bar pushes it, so entering the field
    // walks back to the meet in the last shot.
    Navigator.push(
      tester.element(find.byType(MeetScreen)),
      MaterialPageRoute(
        builder: (_) => const HeatSheetImportScreen(meetId: 'k1'),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/heat_sheet_paste.png'));

    await tester.enterText(find.byType(TextField), _sheet);
    await settle(tester);
    await tester.tap(find.text('Read it'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/heat_sheet_review.png'));

    // The shot put opened on its field: who is in it, who is one of yours,
    // the weight the sheet's '12lb' was read as, and where the sheet split
    // the field into flights.
    await tester.tap(find.textContaining('Shot Put'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/heat_sheet_field.png'));

    // And the meet it leaves behind: two events with fields in them.
    await tester.tap(find.textContaining('Enter '));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/heat_sheet_meet.png'));
  });
}
