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
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/athlete_screen.dart';
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
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await warmImages(tester, thumbs);

    final library = VideoLibrary();
    await library.load();
    final notes = NotesLibrary();
    await notes.load();

    // Sessions on one implement, meet marks, and written-up notes.
    await _shoot(tester, library, notes, 'Anna Sofia', 'athlete_bests');
    // Two weights at once — each keeps its own mark.
    await _shoot(tester, library, notes, 'Adam', 'athlete_two_implements');
    // A mark entered in feet, which is how it reads back.
    await _shoot(tester, library, notes, 'Jakob', 'athlete_feet');
    // A whole season with nothing filmed.
    await _shoot(tester, library, notes, 'Priya Raman',
        'athlete_marks_only');
  });
}

Future<void> _shoot(WidgetTester tester, VideoLibrary library,
    NotesLibrary notes, String name, String file) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<NotesLibrary>.value(value: notes),
      ],
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: AthleteScreen(
          name: name,
          titleFor: (ThrowVideo video) =>
              '${video.event.label} · ${video.implementSpec.weightLabel}',
        ),
      ),
    ),
  );
  await settle(tester);
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$file.png'));
}
