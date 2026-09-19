import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/meet_relay.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/utils/spectator_page.dart';
import 'package:throwlab/widgets/share_meet.dart';

/// The sheet a link is handed over on.
///
/// What it says has changed with what it hands over: the link used to be
/// this phone's address on the wifi, and the sheet was mostly about who
/// could reach it. It is a public one now, so the thing a coach has to
/// know is the other half — the phone is still the only thing that knows
/// what was thrown, and a board it cannot reach is a board that stopped.
void main() {
  late MeetLibrary meets;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    meets = MeetLibrary();
    await meets.load();
    library = VideoLibrary();
    await library.load();
    await meets.save(Meet(
        id: 'k1',
        name: 'County Champs',
        date: DateTime(2026, 6, 13),
        rounds: 6));
    await meets.addEntry('k1',
        entry: MeetEntry(
            id: 'e1',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1));
  });

  MeetRelay relayThat(int status, {String base = 'https://share.test'}) =>
      MeetRelay(
        base: base,
        client: MockClient((_) async =>
            http.Response(status == 200 ? '{"ok":true}' : 'no', status)),
      );

  Future<void> openSheet(WidgetTester tester, MeetRelay relay) async {
    // A live share keeps a retry running, which is the point of it — so
    // the test has to put it down rather than leave a timer behind.
    addTearDown(relay.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final meet = meets.byId('k1')!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
        ChangeNotifierProvider<MeetRelay>.value(value: relay),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShareCompetition(context,
                meet: meet, competition: MeetCompetition.of(meet).first),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Starting a share and letting the first push finish.
  ///
  /// The medal is struck through the engine and the push gives up waiting
  /// on it after a couple of seconds rather than holding the link up, so
  /// the clock has to be wound past that here.
  Future<void> tapStart(WidgetTester tester) async {
    await tester.tap(find.text('Start sharing'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('hands over the link the page is actually on', (tester) async {
    final relay = relayThat(200);
    await openSheet(tester, relay);

    expect(find.text('Follow along'), findsOneWidget);
    await tapStart(tester);

    final url = relay.urlFor('k1', ThrowEvent.discus, 1)!;
    expect(url, startsWith('https://share.test/M/'));
    // The link itself, not an address on somebody's wifi.
    expect(find.text(url), findsOneWidget);
    expect(find.textContaining('192.168'), findsNothing);
    expect(find.textContaining('hotspot'), findsNothing);

    await relay.stopAll();
    await tester.pumpAndSettle();
  });

  testWidgets('says the phone is what the board is fed from', (tester) async {
    final relay = relayThat(200);
    await openSheet(tester, relay);

    // Before: what starting it will do, and what it needs.
    expect(find.textContaining('needs signal'), findsOneWidget);
    await tapStart(tester);

    // After: the one thing a coach has to keep true for the rest of the
    // competition.
    expect(find.textContaining('Keep this phone on signal'), findsOneWidget);

    await relay.stopAll();
    await tester.pumpAndSettle();
  });

  testWidgets('says so when the competition is not getting there',
      (tester) async {
    await openSheet(tester, relayThat(500));

    await tapStart(tester);

    // A push that failed leaves no link to hand anybody, and the reason
    // where the button was.
    expect(find.textContaining('would not take'), findsOneWidget);
    expect(find.textContaining('https://share.test/M/'), findsNothing);
  });

  testWidgets('says a build with no relay cannot share at all',
      (tester) async {
    await openSheet(tester, relayThat(200, base: ''));

    await tapStart(tester);

    expect(find.textContaining('no relay'), findsOneWidget);
  });

  group('what the page says about itself', () {
    test('promises nothing was stored only where that is true', () {
      // Served off the phone, nothing left it.
      expect(spectatorPage(const ColorScheme.dark()),
          contains('Nothing here is stored anywhere else'));

      // Through the relay it did, and a page that went on promising
      // otherwise would be telling a spectator something untrue about a
      // field of other people's children.
      final relayed = spectatorPage(const ColorScheme.dark(),
          servedByPhone: false, asksWhoYouFollow: false);
      expect(relayed, isNot(contains('Nothing here is stored anywhere else')));
      expect(relayed, contains('not kept afterwards'));
    });

    test('asks who you are watching only where it can be answered', () {
      // The phone works the competition out again around whoever is
      // ticked; the relay holds one feed for everybody, so the question
      // would be asked, ticked, and quietly do nothing.
      expect(spectatorPage(const ColorScheme.dark()), contains('var ASKS = true;'));
      expect(spectatorPage(const ColorScheme.dark(), asksWhoYouFollow: false),
          contains('var ASKS = false;'));
    });
  });
}
