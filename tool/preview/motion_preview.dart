// Renders the app's animations a frame at a time, so motion can be reviewed
// the way everything else here is — by looking at it, headless.
//
//   flutter test --update-goldens tool/preview/motion_preview.dart
//   node tool/preview/flipbook.js     # build/preview/motion/index.html
//
// A golden is a still, and a still of an animation is a still of one
// moment of it: the three things here are only right or wrong in motion.
// So each is stepped through on the test clock and shot every few
// milliseconds into build/preview/motion/<scene>/, and flipbook.js plays
// the frames back in a page at the speed they were shot at.
//
// - flight: the live board as three throws come in — a rival's that falls
//   short of his best, a foul, and one of the coach's own that is a
//   personal best — each flown out of the circle and brought down where
//   it landed, which is how the board says what the last thrower threw.
// - best: a throw in the library that has just become a personal best, the
//   frame traced out of the medal's corner and the medal dropped in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/athlete_record.dart';
import 'package:throwlab/screens/home_screen.dart';
import 'package:throwlab/screens/meet_event_screen.dart';
import 'package:throwlab/services/athlete_library.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/meet_server.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/utils/meet_feed.dart';
import 'package:throwlab/utils/spectator_page.dart';
import 'package:throwlab/widgets/gold.dart';
import 'package:throwlab/widgets/throw_card.dart';

import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview/motion';

/// What each scene was shot at, for the flipbook to play it back at.
final _scenes = <String, Map<String, Object>>{};

Future<void> _record(
  WidgetTester tester,
  String scene, {
  required Duration length,
  Duration step = const Duration(milliseconds: 40),
  String caption = '',
  int start = 0,
}) async {
  var frame = start;
  for (var at = Duration.zero; at <= length; at += step) {
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/$scene/${'$frame'.padLeft(3, '0')}.png'));
    frame++;
    await tester.pump(step);
  }
  final entry = _scenes.putIfAbsent(
      scene, () => {'step': step.inMilliseconds, 'cuts': <Object>[]});
  (entry['cuts'] as List<Object>).add({'from': start, 'caption': caption});
  entry['frames'] = frame;
}

/// A still held for a moment, as the same frame written several times —
/// the flipbook plays frames, and a pause between two throws is part of
/// what is being looked at.
Future<int> _hold(WidgetTester tester, String scene, int frame, int count) async {
  for (var i = 0; i < count; i++) {
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/$scene/${'${frame + i}'.padLeft(3, '0')}.png'));
  }
  return frame + count;
}

void _writeIndex() {
  final dir = Directory('build/preview/motion');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/scenes.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_scenes));
}

/// The spectator's page with [feeds] served in place of the phone: the
/// fetch hands back whichever one `window.__feed` names, so the page can
/// be stepped through the same throws the app was.
Future<void> _writePage(List<Map<String, dynamic>> feeds) async {
  final dir = Directory('build/preview/motion/web');
  Directory('${dir.path}/f').createSync(recursive: true);
  final stub = '<script>var FEEDS=${jsonEncode(feeds)};window.__feed=0;\n'
      'window.fetch=function(){return Promise.resolve({ok:true,status:200,'
      'headers:{get:function(){return null;}},'
      'json:function(){return Promise.resolve(FEEDS[window.__feed]);}});};'
      '</script>\n';
  File('${dir.path}/spectator.html').writeAsStringSync(
      spectatorPage(ThrowLabApp.theme.colorScheme)
          .replaceFirst('<script>', '$stub<script>'));
  File('${dir.path}/f/r.ttf').writeAsBytesSync(
      File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync());
  File('${dir.path}/f/s.ttf').writeAsBytesSync(
      File('assets/fonts/Barlow-SemiBold.ttf').readAsBytesSync());
  File('${dir.path}/pb.png')
      .writeAsBytesSync(await medalPng(Medal.gold, size: 48));
}

final _date = DateTime(2026, 6, 13);

Meet _meet() {
  final meet = Meet(
    id: 'k1',
    name: 'County Champs',
    date: _date,
    venue: 'Sportcity',
    rounds: 6,
    prelimRounds: 6,
    advancing: 8,
  );
  MeetEntry rival(String id, String name, int order, List<double?> marks) {
    final entry = MeetEntry(
        id: id,
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: order);
    for (var round = 0; round < marks.length; round++) {
      entry.setAttempt(
          round,
          marks[round] == null
              ? MeetAttempt.foul()
              : MeetAttempt.untracked(marks[round]!));
    }
    return entry;
  }

  meet.entries.addAll([
    rival('r1', 'M. Okoye (Barnet)', 0, [44.12, null, 44.90]),
    rival('r2', 'L. Fischer (Brighton)', 1, [43.20, 42.06, 41.90]),
    MeetEntry(
        id: 'e1',
        athlete: 'Anna Sofia',
        event: ThrowEvent.discus,
        implementKg: 1,
        order: 2)
      ..setAttempt(0, MeetAttempt.mark('mk1'))
      ..setAttempt(1, MeetAttempt.foul())
      ..setAttempt(2, MeetAttempt.mark('mk2')),
    rival('r3', 'S. Patel (Ealing)', 3, [39.80, null, 40.64]),
  ]);
  return meet;
}

Map<String, dynamic> _mark(String id, double distance) => ThrowMark(
      id: id,
      athlete: 'Anna Sofia',
      event: ThrowEvent.discus,
      implementKg: 1,
      distance: distance,
      achievedOn: _date,
      note: 'County Champs',
    ).toJson();

void main() {
  tearDownAll(_writeIndex);

  testWidgets('the last throw, flown in', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.marks':
          jsonEncode([_mark('mk1', 41.20), _mark('mk2', 43.06)]),
      'flutter.throwlab.meets': jsonEncode([_meet().toJson()]),
    });
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final library = VideoLibrary();
    await library.load();
    final meets = MeetLibrary();
    await meets.load();
    final records = AthleteLibrary();
    await records.load();
    await records
        .save(const AthleteRecord(name: 'Anna Sofia', firstName: 'Anna Sofia'));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<AthleteLibrary>.value(value: records),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
        ChangeNotifierProvider<MeetServer>.value(value: MeetServer()),
      ],
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: const MeetEventScreen(
            meetId: 'k1', event: ThrowEvent.discus, implementKg: 1),
      ),
    ));
    await settle(tester);

    // The spectator's page is handed the same competition after each throw,
    // so flipbook.js can fly the page's half of it over the same four
    // states and the two can be looked at side by side.
    final feeds = <Map<String, dynamic>>[];
    void feed() {
      final meet = meets.byId('k1')!;
      feeds.add(competitionFeed(
        meet,
        MeetCompetition.of(meet).single,
        library.results,
        at: DateTime.utc(2026, 6, 13, 14, 32),
        isPersonalBest: library.isPersonalBest,
        boardNames: records.boardName,
      ));
    }

    feed();
    var frame = await _hold(tester, 'flight', 0, 12);

    Future<void> thrown(String entry, MeetAttempt attempt, String caption,
        {Future<void> Function()? first}) async {
      await tester.runAsync(() async {
        await first?.call();
        await meets.setAttempt('k1', entry, 3, attempt);
      });
      feed();
      await tester.pump();
      await _record(tester, 'flight',
          length: const Duration(milliseconds: 1520),
          start: frame,
          caption: caption);
      frame = _scenes['flight']!['frames']! as int;
      frame = await _hold(tester, 'flight', frame, 14);
    }

    // Round 4. Okoye short of his best: the board's lines don't move, and
    // the only thing that says he threw at all is the flight.
    await thrown('r1', MeetAttempt.untracked(43.62),
        'Okoye 43.62 — short of his best, so no line moves');
    // Fischer fouls: down outside the sector line, as a cross.
    await thrown('r2', MeetAttempt.foul(), 'Fischer fouls — outside the line');
    // Anna Sofia, one of the coach's own, beats her best.
    final best = ThrowMark(
      id: 'mk3',
      athlete: 'Anna Sofia',
      event: ThrowEvent.discus,
      implementKg: 1,
      distance: 44.31,
      achievedOn: _date,
      note: 'County Champs',
    );
    await thrown('e1', MeetAttempt.mark('mk3'),
        'Anna Sofia 44.31 — a personal best, struck in gold',
        first: () => library.addMark(best));
    _scenes['flight']!['frames'] = frame;
    await tester.runAsync(() => _writePage(feeds));
  });

  testWidgets('a new best, struck', (tester) async {
    await loadPreviewFonts();
    final thumbs = sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(sampleLibrary(thumbs)),
      'flutter.throwlab.marks': jsonEncode(sampleMarks()),
    });
    tester.view.physicalSize = const Size(720, 1520);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await warmImages(tester, thumbs);
    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);

    final library =
        tester.element(find.byType(HomeScreen)).read<VideoLibrary>();
    final card = tester.widget<ThrowCard>(find.byType(ThrowCard).first);
    final video = card.video;
    // Past the furthest they have thrown that implement, clip or mark.
    var furthest = 0.0;
    for (final result in library.results) {
      if (result.athlete == video.athlete &&
          result.event == video.event &&
          result.implementKg == video.implementKg &&
          (result.distance ?? 0) > furthest) {
        furthest = result.distance!;
      }
    }
    var frame = await _hold(tester, 'best', 0, 12);
    await tester.runAsync(() async {
      video.distance = furthest + 0.84;
      await library.update(video);
    });
    await tester.pump();
    await _record(tester, 'best',
        length: const Duration(milliseconds: 1960),
        start: frame,
        caption: '${video.athlete} beats her best: the frame is traced out '
            'of the corner and the medal dropped in');
    frame = _scenes['best']!['frames']! as int;
    _scenes['best']!['frames'] = await _hold(tester, 'best', frame, 16);
  });

  testWidgets('an import filling the flask', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(720, 1520);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final progress = ValueNotifier<double?>(null);
    final stage = ValueNotifier<String>(
        'Re-encoding for instant frame-by-frame scrubbing. Long or '
        'high-fps clips take a few minutes.');
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(body: OptimizingDialog(progress: progress, stage: stage)),
    ));
    await settle(tester);
    var frame = await _hold(tester, 'flask', 0, 10);
    // Readings the way ffmpeg gives them: in lurches, with a stall in the
    // middle where the surface should go still, and the frames after.
    const readings = [
      0.04, 0.09, 0.15, 0.22, 0.28, 0.33, 0.38, 0.38, 0.38, 0.38, //
      0.44, 0.52, 0.60, 0.68, 0.75, 0.80, 0.86, 0.92, 0.97, 1.0,
    ];
    for (var i = 0; i < readings.length; i++) {
      progress.value = readings[i];
      if (readings[i] >= 0.75 && stage.value.startsWith('Re-encoding')) {
        stage.value = 'Extracting frames for smooth scrubbing…';
      }
      await tester.pump();
      await _record(tester, 'flask',
          length: const Duration(milliseconds: 360),
          start: frame,
          caption: i == 0
              ? 'The level eases onto each reading; the surface moves while '
                  'readings arrive'
              : i == 7
                  ? 'Stalled: no new readings, so the surface settles flat'
                  : i == 10
                      ? 'Moving again'
                      : i == readings.length - 1
                          ? 'Full: the meniscus comes in and it is the logo'
                          : '');
      frame = _scenes['flask']!['frames']! as int;
    }
    // Long enough for the level to land and the surface to still, and then
    // the full mark held.
    await _record(tester, 'flask',
        length: const Duration(milliseconds: 1600), start: frame);
    frame = _scenes['flask']!['frames']! as int;
    _scenes['flask']!['frames'] = await _hold(tester, 'flask', frame, 20);
  });
}
