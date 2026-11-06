import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/backup.dart';
import 'package:throwlab/services/clip_export.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/backup_flow.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:throwlab/widgets/share_throw.dart';
import 'package:throwlab/widgets/throw_actions.dart';

import 'analysis_harness.dart';

/// A throw leaving the app: the drawings painted over the clip by the app's
/// own painter, what the file is called, and what is offered where.
void main() {
  ThrowDrawing drawing(List<Annotation> marks) => ThrowDrawing(
        annotations: marks,
        layout: const Size(400, 225),
        position: const Duration(milliseconds: 500),
        labelStyle: const TextStyle(fontSize: 14),
      );

  group('overlay', () {
    Future<ui.Image> decode(List<int> png) async {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
      return (await codec.getNextFrame()).image;
    }

    Future<(int, int, int, int)> pixel(ui.Image image, int x, int y) async {
      final data = (await image.toByteData())!;
      final at = (y * image.width + x) * 4;
      return (
        data.getUint8(at),
        data.getUint8(at + 1),
        data.getUint8(at + 2),
        data.getUint8(at + 3),
      );
    }

    testWidgets('paints the marks at the clip\'s own size', (tester) async {
      await tester.runAsync(() async {
        // A line across the middle of the frame, drawn on a 400-wide
        // screen, laid over a clip four times that.
        final png = await ClipExport.overlayPng(
          drawing([
            LineAnnotation(const Color(0xFFFF0000), 4, const Offset(0.1, 0.5),
                const Offset(0.9, 0.5)),
          ]),
          const Size(1600, 900),
        );
        final image = await decode(png);
        expect(image.width, 1600);
        expect(image.height, 900);
        final (r, _, _, a) = await pixel(image, 800, 450);
        expect(r, greaterThan(200));
        expect(a, greaterThan(200));
        // Everywhere else is see-through, so the clip shows.
        expect((await pixel(image, 100, 100)).$4, 0);
        // Ink scaled with the frame: a 4 px pen on the phone is thicker than
        // 4 px on a clip four times the size.
        expect((await pixel(image, 800, 450 + 5)).$4, greaterThan(0));
        image.dispose();
      });
    });

    test('a timer makes the overlay move; a drawing alone does not', () {
      expect(
          drawing([
            CircleAnnotation(const Color(0xFFFFFFFF), 3, const Offset(0.5, 0.5),
                const Offset(0.6, 0.5)),
          ]).moves,
          isFalse);
      expect(
          drawing([
            TimerMarker(const Color(0xFFFFFFFF), 3, const Offset(0.2, 0.2),
                Duration.zero),
          ]).moves,
          isTrue);
      expect(drawing(const []).isEmpty, isTrue);
    });
  });

  group('ffmpeg', () {
    test('lays the overlay over the clip, scaled to it', () {
      final command =
          ClipExport.stillOverlayCommand('/c.mp4', '/o.png', '/x.mp4');
      expect(command, contains('-i "/c.mp4" -i "/o.png"'));
      expect(command, contains('[1:v][0:v]scale2ref[ov][base]'));
      expect(command, contains('overlay=0:0'));
      expect(command, contains('-movflags +faststart'));
      expect(command, endsWith('"/x.mp4"'));
    });

    test('a moving overlay is read as frames at the clip\'s rate', () {
      final command = ClipExport.movingOverlayCommand(
          '/c.mp4', '/f/o%05d.png', 29.97, '/x.mp4');
      expect(command, contains('-framerate 29.970000 -i "/f/o%05d.png"'));
      expect(ClipExport.overlayFrame(7), 'o00007.png');
    });

    test('a frame is cut where the clip is, in the JPEG\'s own color', () {
      final command = ClipExport.frameCommand('/c.mp4', '/o.png', '/x.jpg',
          seconds: 1.5, color: 'in_color_matrix=bt709');
      expect(command, startsWith('-y -ss 1.500000 -i "/c.mp4"'));
      expect(command, contains('scale=iw:ih:in_color_matrix=bt709'));
      expect(command, contains('-frames:v 1'));
    });
  });

  group('naming', () {
    ThrowVideo video({String athlete = 'Ana Diaz', double? distance}) =>
        ThrowVideo(
          id: 'v',
          path: '/v.mp4',
          event: ThrowEvent.discus,
          implementKg: 1,
          importedAt: DateTime(2026, 11, 4, 15),
          athlete: athlete,
          distance: distance,
        );

    test('a file is named for whose throw it is and when', () {
      expect(shareName(video()), 'Ana Diaz - Discus 1 kg - 2026-11-04');
      expect(shareName(video(athlete: '')), 'Discus 1 kg - 2026-11-04');
      // Nothing a file system would refuse.
      expect(shareName(video(athlete: 'A/B: "C"?')),
          'AB C - Discus 1 kg - 2026-11-04');
    });

    test('the caption says how far it went', () {
      expect(shareCaption(video(distance: 52.18)),
          'Ana Diaz · Discus · 1 kg · 52.18 m');
    });

    test('a restore says what came back', () {
      expect(
          restoredMessage(const RestoreResult(values: {}, added: {
            'throwlab.videos': 12,
            'throwlab.marks': 1,
            'throwlab.meets': 4,
          })),
          'Restored 12 clips, 1 mark and 4 meets.');
      expect(restoredMessage(const RestoreResult(values: {}, added: {})),
          'Everything in that backup is already on this phone.');
    });
  });

  group('offered', () {
    late Directory temp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('throwlab_share');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    Future<void> mount(
            WidgetTester tester, Future<Object?> Function(BuildContext) body) =>
        tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>(
          create: (_) => VideoLibrary(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => body(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ));

    testWidgets('the throw sheet hands Share to the screen that has more',
        (tester) async {
      var shared = 0;
      final video = testVideo(temp);
      await mount(
          tester,
          (context) => showThrowActions(context, video, onShare: () async {
                shared++;
              }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('throw-share')));
      await tester.pumpAndSettle();
      expect(shared, 1);
    });

    testWidgets('with drawings on the frame, all three ways are offered',
        (tester) async {
      final video = testVideo(temp);
      await mount(
          tester,
          (context) => shareThrow(context, video,
              drawing: drawing([
                ArrowAnnotation(const Color(0xFFFFFFFF), 3,
                    const Offset(0.1, 0.1), const Offset(0.5, 0.5)),
              ]),
              pixels: const Size(1920, 1080),
              duration: const Duration(seconds: 5)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Clip with drawings'), findsOneWidget);
      expect(find.text('This frame with drawings'), findsOneWidget);
      expect(find.text('Clip'), findsOneWidget);
      expect(find.text('As filmed, without the drawings.'), findsOneWidget);
    });

    testWidgets('with nothing drawn, there are no drawings to offer',
        (tester) async {
      final video = testVideo(temp);
      await mount(
          tester,
          (context) => shareThrow(context, video,
              drawing: drawing(const []),
              pixels: const Size(1920, 1080),
              duration: const Duration(seconds: 5)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Clip with drawings'), findsNothing);
      expect(find.text('This frame'), findsOneWidget);
      expect(find.text('As filmed.'), findsOneWidget);
    });
  });
}
