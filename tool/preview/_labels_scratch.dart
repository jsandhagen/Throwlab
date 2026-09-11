// Throwaway: the same two boards drawn three ways, to pick a label layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_board.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/widgets/sector_board.dart';

import 'harness.dart';

MeetStandings _table(List<(String, double, bool)> field, ThrowEvent event,
        {int advancing = 99}) =>
    MeetStandings(
      MeetCompetition(event, event == ThrowEvent.javelin ? 0.8 : 1, [
        for (final (i, e) in field.indexed)
          MeetEntry(
              id: 'e$i',
              athlete: e.$1,
              event: event,
              implementKg: event == ThrowEvent.javelin ? 0.8 : 1,
              tracked: e.$3,
              order: i)
            ..setAttempt(0, MeetAttempt.untracked(e.$2)),
      ]),
      const [],
      advancing: advancing,
      prelimRounds: 3,
    );

void main() {
  testWidgets('labels', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 1560);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final discus = _table([
      ('M. Okoye (Barnet)', 44.90, false),
      ('L. Fischer (Brighton)', 43.20, false),
      ('Anna Sofia', 43.06, true),
      ('S. Patel (Ealing)', 42.60, false),
    ], ThrowEvent.discus);
    final javelin = _table([
      ('T. Brandt (Kiel)', 63.40, false),
      ('R. Novak (Prague)', 60.12, false),
      ('A. Lindqvist (Umea)', 59.55, false),
      ('P. Moreau (Lyon)', 58.90, false),
      ('Jakob', 58.34, true),
      ('D. Whitcombe (Leeds)', 56.20, false),
    ], ThrowEvent.javelin, advancing: 4);

    for (final labels in BoardLabels.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThrowLabApp.theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                for (final (board, event) in [
                  (MeetBoard(discus), ThrowEvent.discus),
                  (MeetBoard(javelin), ThrowEvent.javelin),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF15181B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SectorBoard(
                          board: board,
                          event: event,
                          accent: const Color(0xFF4FC3F7),
                          backdrop: const Color(0xFF15181B),
                          labels: labels,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../../build/preview/labels_${labels.name}.png'));
    }
  });
}
