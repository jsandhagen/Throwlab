// Renders the throwing-themed motifs from lib/widgets/throw_motifs.dart as
// a sample sheet, at the sizes they'd actually be used.
//
//   flutter test --update-goldens tool/preview/motifs_preview.dart
//
// See CLAUDE.md for how this harness works.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/widgets/throw_motifs.dart';

import 'harness.dart';

const _out = '../../build/preview';

const _eventColors = {
  ThrowEvent.shotPut: Colors.orangeAccent,
  ThrowEvent.discus: Colors.greenAccent,
  ThrowEvent.hammer: Colors.purpleAccent,
  ThrowEvent.javelin: Colors.lightBlueAccent,
};

void main() {
  testWidgets('motif sheet', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2760);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4FC3F7), brightness: Brightness.dark),
        fontFamily: 'Barlow',
        useMaterial3: true,
      ),
      home: const _MotifSheet(),
    ));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('$_out/motifs.png'));
  });
}

class _MotifSheet extends StatelessWidget {
  const _MotifSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            _label(context, '1 · Implement glyphs — tile size, then large'),
            Row(
              children: [
                for (final event in ThrowEvent.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        _tile(event),
                        const SizedBox(height: 6),
                        Text(event.label,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final event in ThrowEvent.values)
                  ImplementGlyph(
                      event: event, color: _eventColors[event]!, size: 64),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final event in ThrowEvent.values)
                  Icon(event.icon, size: 40, color: scheme.onSurfaceVariant),
              ],
            ),
            _caption(context, 'above: drawn glyphs · below: the Material '
                'icons in use today'),

            _label(context, '2 · Sector geometry — behind an empty state'),
            _panel(
              height: 200,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                        painter: SectorPainter(color: scheme.primary)),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No throws yet',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Film side-on, then import the clip',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _caption(context,
                'the 34.92° sector, its circle, and distance arcs'),

            _label(context, '3 · Flight arc — as a shelf separator'),
            _panel(
              height: 96,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('Anna Sofia · 3 throws',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  SizedBox(
                    height: 26,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: FlightArcPainter(color: scheme.primary),
                    ),
                  ),
                  Text('Jakob · 2 throws',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            _caption(context,
                'the real trajectory for a 13 m/s release at 36°, from 1.8 m'),

            _label(context, '4 · Cage and runway — cards with no thumbnail'),
            Row(
              children: [
                for (final event in [ThrowEvent.discus, ThrowEvent.javelin])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Material(
                          color: Colors.black,
                          clipBehavior: Clip.antiAlias,
                          shape: const BeveledRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                  painter: ThrowSurfacePainter(
                                      event: event,
                                      color: _eventColors[event]!)),
                              Center(
                                child: ImplementGlyph(
                                    event: event,
                                    color: Colors.white.withOpacity(0.75),
                                    size: 40),
                              ),
                              Positioned(
                                left: 10,
                                right: 10,
                                bottom: 8,
                                child: Text(
                                  '${event.label} · Men',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            _caption(context, 'cage netting for the ring events, runway '
                'lanes for the javelin'),
          ],
        ),
      ),
    );
  }

  Widget _tile(ThrowEvent event) {
    final color = _eventColors[event]!;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: BeveledRectangleBorder(
          side: BorderSide(color: color.withOpacity(0.55)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(13),
            bottomRight: Radius.circular(13),
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.85), color.withOpacity(0.28)],
        ),
      ),
      child: ImplementGlyph(event: event, color: Colors.white, size: 24),
    );
  }

  Widget _panel({required double height, required Widget child}) => Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF101418),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      );

  Widget _caption(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
