// Renders the home screen to PNGs so library UI changes can be reviewed
// without an emulator — useful when working headless (CI, containers, an
// agent session). It is not a test: it asserts nothing, it just paints.
//
//   flutter test --update-goldens tool/preview/home_preview.dart
//
// Images land in build/preview/ (gitignored). Sample throws and their
// thumbnails are generated at run time, so no fixtures are committed.
//
// Living outside test/ keeps `flutter test` — and therefore CI — clear of it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';

import 'harness.dart';
import 'sample_library.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

void main() {
  testWidgets('home screen', (tester) async {
    await loadPreviewFonts();
    final thumbs = sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(sampleLibrary(thumbs)),
    });

    // A tall phone, the way the app is actually held.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await warmImages(tester, thumbs);
    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await _shoot(tester, 'home_by_athlete');

    await tester.tap(find.text('Event'));
    await settle(tester);
    await _shoot(tester, 'home_by_event');

    await tester.tap(find.text('Date'));
    await settle(tester);
    await _shoot(tester, 'home_by_date');

    await tester.enterText(find.byType(TextField).first, 'javelin');
    await settle(tester);
    await _shoot(tester, 'home_search');
  });

  testWidgets('empty library', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await _shoot(tester, 'home_empty');
  });
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
