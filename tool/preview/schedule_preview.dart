// Renders the schedule import to PNGs — the page a fixture list is pasted
// into, what the parser made of one, and the season it leaves behind — so
// the screens can be reviewed without an emulator or a track.
//
//   flutter test --update-goldens tool/preview/schedule_preview.dart
//
// Images land in build/preview/ (gitignored). Same shape as meet_preview.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/screens/meets_screen.dart';
import 'package:throwlab/screens/schedule_import_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';

import 'harness.dart';

const _out = '../../build/preview';

/// A season as somebody actually pastes one: columns that don't line up, a
/// weekday in front of half the dates, a row with the year left off, and a
/// meet that is already on the calendar.
const _schedule = '''
2027 Outdoor Schedule

Date        Meet                     Site
Sat 3/13    Tiger Relays             Auburn, AL
3/27        Spring Invitational      Home
Sat 10 April 2027 — County Champs @ Sportcity
May 1       Loughborough Open        Loughborough
''';

void main() {
  testWidgets('schedule import', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final meets = MeetLibrary();
    await meets.load();
    // Already on the books, so the review has one row it will not enter.
    await meets.save(Meet(
      id: 'k0',
      name: 'Tiger Relays',
      date: DateTime(2027, 3, 13),
      venue: 'Auburn, AL',
    ));

    // Pushed onto the season the way the trophy's import button pushes it,
    // so adding walks back to the calendar in the last shot.
    await _mount(tester, meets, const MeetsScreen());
    Navigator.push(
      tester.element(find.byType(MeetsScreen)),
      MaterialPageRoute(builder: (_) => const ScheduleImportScreen()),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/schedule_paste.png'));

    await tester.enterText(find.byType(TextField), _schedule);
    await settle(tester);
    await tester.tap(find.text('Read it'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/schedule_review.png'));

    // Correcting a row before it becomes a meet — opened on the one the
    // parser had to guess the year for, with the line it read underneath.
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/schedule_edit.png'));
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // A season the coach has already been throwing in, so the shot below
    // shows all three headings rather than only what was just imported.
    await meets.save(Meet(
      id: 'k-past',
      name: 'Winter Throws',
      date: DateTime.now().subtract(const Duration(days: 26)),
      venue: 'Lee Valley',
    ));
    await meets.save(Meet(
      id: 'k-today',
      name: 'Club Open',
      date: DateTime.now(),
      venue: 'Sportcity',
    ));

    // The season it leaves behind: meets with a place and a date, and
    // nobody entered for them yet.
    await tester.tap(find.text('Add 3 meets'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/schedule_season.png'));
  });
}

Future<void> _mount(
    WidgetTester tester, MeetLibrary meets, Widget screen) async {
  final library = VideoLibrary();
  await library.load();
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
}
