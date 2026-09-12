// Renders the compare picker to PNGs — the sheet both ways in, part-way
// through picking, and when a filter has emptied it — so the modal can be
// reviewed without an emulator.
//
//   flutter test --update-goldens tool/preview/compare_preview.dart
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
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/athlete_library.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/throw_picker.dart';

import 'harness.dart';
import 'sample_library.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

void main() {
  testWidgets('compare picker', (tester) async {
    await loadPreviewFonts();
    final thumbs = sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(sampleLibrary(thumbs)),
      'flutter.throwlab.marks': jsonEncode(sampleMarks()),
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await warmImages(tester, thumbs);

    final library = VideoLibrary();
    await library.load();
    final athletes = AthleteLibrary();
    await athletes.load();
    // A nickname, so the rows prove they read through the records rather
    // than the spelling the clips are filed under.
    await athletes.save(const AthleteRecord(name: 'Adam', nickname: 'AJ'));

    // Opened from the library: neither half chosen yet.
    await _open(tester, library, athletes);
    await _shoot(tester, 'compare_pick_empty');

    // One picked — slot A filled, the event chip on, the button saying
    // what is still missing.
    await tester.tap(find.textContaining('Anna Sofia · Discus').first);
    await settle(tester);
    await _shoot(tester, 'compare_pick_one');

    // Both picked, ready to open.
    await tester.tap(find.textContaining('49.80').first);
    await settle(tester);
    await _shoot(tester, 'compare_pick_two');

    // Opened from a throw: that throw is A and a tap is the whole job.
    await _open(tester, library, athletes,
        against: library.videos.firstWhere((video) => video.id == '4'));
    await _shoot(tester, 'compare_anchored');

    // Dropped off the event filter — the whole library, across implements.
    await tester.tap(find.text('Javelin'));
    await settle(tester);
    await _shoot(tester, 'compare_all_events');

    // A search that matches nothing, and the way out of it.
    await tester.enterText(find.byType(TextField), 'wind');
    await settle(tester);
    await _shoot(tester, 'compare_search');
    await tester.enterText(find.byType(TextField), 'sofía');
    await settle(tester);
    await _shoot(tester, 'compare_no_match');
  });
}

/// Mounts a bare screen under the app's theme and opens the sheet on it, so
/// what is painted is the picker rather than whatever screen called it.
Future<void> _open(
  WidgetTester tester,
  VideoLibrary library,
  AthleteLibrary athletes, {
  ThrowVideo? against,
}) async {
  // Remounting keeps the navigator, and with it whatever sheet is already
  // up: tap the barrier off first so the next one opens on its own.
  if (find.byType(BottomSheet).evaluate().isNotEmpty) {
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<AthleteLibrary>.value(value: athletes),
      ],
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('ThrowLab')),
            body: Center(
              child: ElevatedButton(
                onPressed: () => pickThrowsToCompare(context,
                    library: library, against: against),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Open picker'));
  await settle(tester);
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
