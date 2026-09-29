// The what-if written down to be sent: a javelin measured against a faster,
// flatter release in meters, and a high school 12 lb shot in feet with a
// wind on it. Shot at the card's own size, which is the image a share
// would write. See CLAUDE.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/flight_model.dart';
import 'package:throwlab/widgets/what_if_card.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('what if card', (tester) async {
    await loadPreviewFonts();
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(WhatIfCard.width * 3, 2400);
    addTearDown(tester.view.reset);

    Future<void> shoot(
        String name,
        ThrowEvent event,
        double kg,
        DistanceUnit unit,
        WhatIfSide Function(ImplementSpec) one,
        Release two) async {
      final spec = event.specFor(kg);
      final loss = typicalSpeedLossPerDeg(event);
      final a = one(spec);
      final card = WhatIfCard(
        event: event,
        spec: spec,
        unit: unit,
        baseline: a,
        whatIf: WhatIfSide(
            name: 'Changed', release: two, flight: flyThrow(event, spec, two)),
        shares: gapShares(event, spec, a.release, two, speedLossPerDeg: loss),
        speedLossPerDeg: loss,
        date: DateTime(2026, 9, 29),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: ThrowLabApp.theme,
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(child: card),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(WhatIfCard), matchesGoldenFile('$_out/$name.png'));
    }

    WhatIfSide measured(ThrowEvent e, ImplementSpec s, Release r) => WhatIfSide(
        name: 'Your measured throw', release: r, flight: flyThrow(e, s, r));

    const jav =
        Release(speed: 27.0, angleDeg: 38.0, height: 1.85, attackDeg: 6);
    await shoot(
      'what_if_card_javelin',
      ThrowEvent.javelin,
      0.8,
      DistanceUnit.meters,
      (s) => measured(ThrowEvent.javelin, s, jav),
      jav.copyWith(speed: 28.2, angleDeg: 35.0),
    );

    const shot = Release(speed: 11.4, angleDeg: 33.5, height: 1.95);
    await shoot(
      'what_if_card_shot_feet',
      ThrowEvent.shotPut,
      5.44,
      DistanceUnit.feet,
      (s) => measured(ThrowEvent.shotPut, s, shot),
      shot.copyWith(speed: 11.9, angleDeg: 36.0, height: 2.05),
    );
  });
}
