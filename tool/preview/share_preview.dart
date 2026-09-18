// Renders sharing a meet — the sheet a coach hands the link over from, and
// the page a spectator actually gets.
//
//   flutter test --update-goldens tool/preview/share_preview.dart
//
// Two artifacts. The PNGs are the app's own side of it: the competition
// screen with the share action in its app bar (off and lit), and the sheet
// in both states. The other is build/preview/spectator.html — the real page
// with a real competition's feed baked into it, which is the only honest
// way to review a page whose whole job happens in a browser. Open it; every
// tab works, because the page already holds the whole competition.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/meet_event_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/meet_server.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/utils/meet_feed.dart';
import 'package:throwlab/utils/spectator_page.dart';
import 'package:throwlab/widgets/gold.dart';

import 'harness.dart';

const _out = '../../build/preview';
final _date = DateTime(2026, 6, 13);

/// The coach's own throwers' marks, which live in the record book.
List<Map<String, dynamic>> _marks() => [
      _mark('mk1', 'Anna Sofia', ThrowEvent.discus, 1, 41.20),
      _mark('mk2', 'Anna Sofia', ThrowEvent.discus, 1, 43.06),
      _mark('mk3', 'Jakob', ThrowEvent.javelin, 0.8, 58.34, feet: true),
      _mark('mk4', 'Jakob', ThrowEvent.javelin, 0.8, 61.02, feet: true),
    ];

Map<String, dynamic> _mark(
        String id, String athlete, ThrowEvent event, double kg, double distance,
        {bool feet = false}) =>
    ThrowMark(
      id: id,
      athlete: athlete,
      event: event,
      implementKg: kg,
      distance: distance,
      distanceUnit: feet ? DistanceUnit.feet : DistanceUnit.meters,
      achievedOn: _date,
      note: 'County Champs',
    ).toJson();

/// A meet with everything the page has to cope with on it: a discus cut to
/// a final, a javelin measured in feet in a metric field, and a shot with
/// the leader far enough clear that the board breaks and draws her as an
/// arrow off the top.
Meet _meet() {
  final champs = Meet(
    id: 'k1',
    name: 'County Champs',
    date: _date,
    venue: 'Sportcity',
    rounds: 6,
    prelimRounds: 3,
    advancing: 4,
    conditions: const MeetConditions(
      sky: MeetSky.overcast,
      temperature: 54,
      wind: MeetWind.head,
      note: 'gusting down the runway',
    ),
  );

  MeetEntry rival(String id, String name, ThrowEvent event, double kg,
      int order, List<double?> marks) {
    final entry = MeetEntry(
        id: id,
        athlete: name,
        event: event,
        implementKg: kg,
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

  champs.entries.addAll([
    MeetEntry(
        id: 'e1',
        athlete: 'Anna Sofia',
        event: ThrowEvent.discus,
        implementKg: 1,
        order: 0)
      ..setAttempt(0, MeetAttempt.mark('mk1'))
      ..setAttempt(1, MeetAttempt.foul())
      ..setAttempt(2, MeetAttempt.mark('mk2')),
    rival('r1', 'M. Okoye (Barnet)', ThrowEvent.discus, 1, 1,
        [44.12, null, 44.90]),
    rival('r2', 'L. Fischer (Brighton)', ThrowEvent.discus, 1, 2,
        [43.20, 42.06, 41.90]),
    rival('r3', 'S. Patel (Ealing)', ThrowEvent.discus, 1, 3, [39.80, null]),
    // The javelin, thrown in feet — every mark on the page reads back the
    // way the tape was read.
    MeetEntry(
        id: 'e2',
        athlete: 'Jakob',
        event: ThrowEvent.javelin,
        implementKg: 0.8,
        order: 4)
      ..setAttempt(0, MeetAttempt.mark('mk3'))
      ..setAttempt(1, MeetAttempt.mark('mk4')),
    rival('j1', 'T. Brandt (Kiel)', ThrowEvent.javelin, 0.8, 5, [63.40]),
    rival('j2', 'R. Novak (Prague)', ThrowEvent.javelin, 0.8, 6, [60.12]),
    // The shot, where one thrower is a long way clear of the rest.
    rival('s1', 'B. Kowalski (Poznan)', ThrowEvent.shotPut, 4, 7, [18.60]),
    rival('s2', 'N. Achebe (Croydon)', ThrowEvent.shotPut, 4, 8, [14.05]),
    rival('s3', 'E. Haugen (Bergen)', ThrowEvent.shotPut, 4, 9, [13.60]),
  ]);
  return champs;
}

void main() {
  testWidgets('sharing a meet', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.marks': jsonEncode(_marks()),
      'flutter.throwlab.meets': jsonEncode([_meet().toJson()]),
    });

    // The same 390 x 844 the spectator's page is reviewed at, so the two
    // can be stood side by side and the differences are differences rather
    // than a change of canvas.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final library = VideoLibrary();
    await library.load();
    final meets = MeetLibrary();
    await meets.load();

    // A real socket, on the loopback, reading a plausible address back: the
    // sheet has to show the link a coach would actually be handed.
    // ignore: invalid_use_of_visible_for_testing_member
    MeetServer.bind =
        (port) => HttpServer.bind(InternetAddress.loopbackIPv4, port);
    // ignore: invalid_use_of_visible_for_testing_member
    MeetServer.lanAddress = () async => '192.168.43.1';
    final server = MeetServer();
    addTearDown(server.stopAll);

    Future<void> pump() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VideoLibrary>.value(value: library),
            ChangeNotifierProvider<MeetLibrary>.value(value: meets),
            ChangeNotifierProvider<MeetServer>.value(value: server),
          ],
          child: MaterialApp(
            theme: ThrowLabApp.theme,
            home: const MeetEventScreen(
                meetId: 'k1', event: ThrowEvent.discus, implementKg: 1),
          ),
        ),
      );
      await settle(tester);
    }

    // The competition, with the share action beside the sheet in its app
    // bar — the two things a coach reaches for at a ring.
    await pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/share_meet_bar.png'));

    // The app's own three views of this competition, for standing beside
    // the page's three. This is the comparison that matters: the page is
    // meant to read as the app, and the only way to know is to look at
    // them together.
    for (final view in ['Live', 'Series', 'Standings']) {
      await tester.tap(find.text(view));
      await settle(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('$_out/app_${view.toLowerCase()}.png'));
    }
    await tester.tap(find.text('Live'));
    await settle(tester);

    // The sheet before anything is shared: what it is, and what it costs.
    await tester.tap(find.byTooltip('Follow along'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/share_offer.png'));

    // And sharing: the QR on its white card, the link under it big enough
    // to read out, and the way to stop.
    await tester.runAsync(() async {
      await server.start(
        meetId: 'k1',
        event: ThrowEvent.discus,
        implementKg: 1,
        scheme: ThrowLabApp.theme.colorScheme,
        meet: () => meets.byId('k1'),
        results: () => library.results,
        isPersonalBest: library.isPersonalBest,
      );
    });
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/share_live.png'));

    // The app bar again with the action lit, the sheet put away — a coach
    // who has walked to the next ring has no other way to tell that the
    // phone is still serving.
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/share_meet_bar_live.png'));

    // The spectator's side. The page is served whole and asks for its own
    // state, so the only way to look at one off a track is to hand it a
    // meet's feed instead of a fetch — the page itself is untouched.
    await tester.runAsync(() async {
      final made = meets.byId('k1')!;
      final feed = jsonEncode(competitionFeed(
          made,
          MeetCompetition.of(made)
              .firstWhere((c) => c.event == ThrowEvent.discus),
          library.results,
          at: DateTime.utc(2026, 6, 13, 14, 32),
          isPersonalBest: library.isPersonalBest));
      final stub = '<script>window.fetch=function(){'
          'return Promise.resolve({ok:true,status:200,'
          'headers:{get:function(){return null;}},'
          'json:function(){return Promise.resolve($feed);}});};</script>\n';
      final folder = Directory('build/preview');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final file = File('${folder.path}/spectator.html');
      // The page as the app paints it, in the app's own colors — and with
      // Barlow pointed at the files beside it rather than at the phone,
      // since there is no server behind a file:// page.
      final page = spectatorPage(ThrowLabApp.theme.colorScheme)
          .replaceFirst('<script>', '$stub<script>');
      await file.writeAsString(page);
      final fonts = Directory('${folder.path}/f');
      if (!fonts.existsSync()) fonts.createSync(recursive: true);
      File('${fonts.path}/r.ttf')
          .writeAsBytesSync(File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync());
      File('${fonts.path}/s.ttf').writeAsBytesSync(
          File('assets/fonts/Barlow-SemiBold.ttf').readAsBytesSync());
      // The medal the page pins on a personal best, struck by the app's own
      // painter exactly as the server strikes it.
      File('${folder.path}/pb.png')
          .writeAsBytesSync(await medalPng(Medal.gold, size: 48));
      // ignore: avoid_print
      print('wrote ${file.path} (${file.lengthSync()} bytes)');
    });
  });
}
