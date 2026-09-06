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
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await warmImages(tester, thumbs);

    final library = VideoLibrary();
    await library.load();

    // Three sessions on one implement: a mark with a field behind it.
    await _shoot(tester, library, 'Anna Sofia', 'athlete_bests');
    // Two weights at once — each keeps its own mark.
    await _shoot(tester, library, 'Adam', 'athlete_two_implements');
    // A mark entered in feet, which is how it reads back.
    await _shoot(tester, library, 'Jakob', 'athlete_feet');
  });
}

Future<void> _shoot(WidgetTester tester, VideoLibrary library, String name,
    String file) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<VideoLibrary>.value(
      value: library,
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
