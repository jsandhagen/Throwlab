import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/widgets/logo_mark.dart';

void main() {
  testWidgets('the flask says how far along it is, and settles', (tester) async {
    final progress = ValueNotifier<double?>(null);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) =>
            Center(child: FillingFlask(height: 96, progress: value)),
      ),
    ));
    expect(find.bySemanticsLabel('Progress'), findsOneWidget);

    progress.value = 0.55;
    await tester.pump();
    expect(tester.getSemantics(find.byType(FillingFlask)).value, '55%');

    // Eased onto the reading and then still: the ticker stops once the
    // level has landed and the surface has flattened, so nothing is left
    // repainting a flask that has stopped moving.
    await tester.pumpAndSettle();
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(FillingFlask), matching: find.byType(CustomPaint)))
        .painter! as LogoPainter;
    expect(painter.fill, closeTo(0.55, 0.001));
    expect(painter.ripple, 0);
  });

  testWidgets('it is only full when the wait is over', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: FillingFlask(height: 96, progress: 1)),
    ));
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(FillingFlask), matching: find.byType(CustomPaint)))
        .painter! as LogoPainter;
    expect(painter.fill, 1);
  });
}
