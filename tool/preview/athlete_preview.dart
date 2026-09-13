// Renders an athlete's profile to PNGs — the marks they hold and the clips
// those came out of — so the screen can be reviewed without an emulator.
//
//   flutter test --update-goldens tool/preview/athlete_preview.dart
//
// Images land in build/preview/ (gitignored). Same shape as home_preview,
// off the same generated library.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/athlete_record.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/athlete_screen.dart';
import 'package:throwlab/services/athlete_library.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/notes_library.dart';
import 'package:throwlab/services/video_library.dart';

import 'harness.dart';
import 'sample_library.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

void main() {
  testWidgets('athlete profiles', (tester) async {
    await loadPreviewFonts();
    final thumbs = sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(sampleLibrary(thumbs)),
      'flutter.throwlab.marks': jsonEncode(sampleMarks()),
      'flutter.throwlab.notes': jsonEncode(sampleNotes()),
      'flutter.throwlab.meets': jsonEncode(sampleMeets()),
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await warmImages(tester, thumbs);

    final library = VideoLibrary();
    await library.load();
    final notes = NotesLibrary();
    await notes.load();
    final athletes = AthleteLibrary();
    await athletes.load();
    final meets = MeetLibrary();
    await meets.load();
    // A nickname to show Adam by, with the full name and school kept for a
    // heat sheet — so the heading reads 'AJ' and the record line names who.
    await athletes.save(const AthleteRecord(
        name: 'Adam',
        nickname: 'AJ',
        fullName: 'Adam Okafor',
        school: 'Central HS'));

    // Sessions on one implement, meet marks, and written-up notes. Two
    // seasons on record, so the averages open on the most recent.
    await _shoot(tester, library, notes, athletes, meets, 'Anna Sofia',
        'athlete_bests');
    // The same profile read over last season instead.
    await _shoot(tester, library, notes, athletes, meets, 'Anna Sofia',
        'athlete_last_season', season: '${DateTime.now().year - 1}');
    // Two weights at once — each keeps its own mark, under an edited nickname.
    await _shoot(tester, library, notes, athletes, meets, 'Adam',
        'athlete_two_implements');
    // A mark entered in feet, which is how it reads back.
    await _shoot(
        tester, library, notes, athletes, meets, 'Jakob', 'athlete_feet');
    // Six meets this spring and three last: a full season, which is what
    // the averages and the record's own staircase are shaped for.
    await _shoot(tester, library, notes, athletes, meets, 'Marcus Reed',
        'athlete_season');
    // A whole season with nothing filmed.
    await _shoot(tester, library, notes, athletes, meets, 'Priya Raman',
        'athlete_marks_only');
    // Last, because it is the one shot that leaves something behind: which
    // way a meet is read is remembered, so a card shot after this one
    // would open on the best rather than on the average.
    await _shoot(tester, library, notes, athletes, meets, 'Marcus Reed',
        'athlete_meet_bests', best: true);
  });
}

Future<void> _shoot(
    WidgetTester tester,
    VideoLibrary library,
    NotesLibrary notes,
    AthleteLibrary athletes,
    MeetLibrary meets,
    String name,
    String file,
    {String? season,
    bool best = false}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<NotesLibrary>.value(value: notes),
        ChangeNotifierProvider<AthleteLibrary>.value(value: athletes),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: AthleteScreen(
          // A key per shot, so each one mounts a fresh screen: two shots of
          // the same athlete would otherwise share the state of the first,
          // and the second would open on whatever the first was left on.
          key: ValueKey(file),
          name: name,
          titleFor: (ThrowVideo video) =>
              '${video.event.label} · ${video.implementSpec.weightLabel}',
        ),
      ),
    ),
  );
  await settle(tester);
  if (season != null) {
    // Through the picker rather than by seeding it, so the shot is the
    // screen a coach is actually looking at after choosing a season.
    await tester.tap(find.byTooltip('Season'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(season).last);
    await settle(tester);
  }
  if (best) {
    await tester.tap(find.text('Best'));
    await settle(tester);
  }
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$file.png'));
}
