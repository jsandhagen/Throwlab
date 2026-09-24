import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/services/video_optimizer.dart';
import 'package:throwlab/utils/frame_seeker.dart';
import 'package:throwlab/utils/frame_timing.dart';
import 'package:throwlab/utils/zoom_detail.dart';
import 'package:throwlab/widgets/detail_still.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

Duration _us(num microseconds) => Duration(microseconds: microseconds.round());

void main() {
  group('visibleCanvasRect', () {
    test('unzoomed, the whole letterboxed canvas is on screen', () {
      final rect = visibleCanvasRect(
        viewport: const Size(800, 600),
        canvas: const Size(800, 450),
        zoom: 1,
        offset: Offset.zero,
      );
      expect(rect, const Rect.fromLTWH(0, 0, 800, 450));
    });

    test('zoomed into a corner, it is that corner of the canvas', () {
      // 4x about the viewport's corner, panned so the stage point (400, 300)
      // — the canvas's middle, since it is centered — sits at the top left.
      final rect = visibleCanvasRect(
        viewport: const Size(800, 600),
        canvas: const Size(800, 450),
        zoom: 4,
        offset: const Offset(-1600, -1200),
      )!;
      expect(rect.left, closeTo(400, 1e-9));
      expect(rect.top, closeTo(225, 1e-9));
      expect(rect.width, closeTo(200, 1e-9));
      expect(rect.height, closeTo(150, 1e-9));
    });

    test('the letterbox bands are not part of it', () {
      // Zoomed onto the band above a wide clip: only the top of the canvas.
      final rect = visibleCanvasRect(
        viewport: const Size(800, 600),
        canvas: const Size(800, 450),
        zoom: 2,
        offset: Offset.zero,
      )!;
      expect(rect, const Rect.fromLTWH(0, 0, 400, 225));
    });
  });

  group('detailCropFor', () {
    test('a frame being shrunk or barely grown is left to the GPU', () {
      expect(
        detailCropFor(
          frameWidth: 2560,
          frameHeight: 1440,
          visible: const Rect.fromLTWH(0, 0, 1, 1),
          magnification: 0.9,
        ),
        isNull,
      );
      expect(
        detailCropFor(
          frameWidth: 2560,
          frameHeight: 1440,
          visible: const Rect.fromLTWH(0, 0, 1, 1),
          magnification: kDetailMinMagnification - 0.01,
        ),
        isNull,
      );
    });

    test('an unzoomed portrait clip on a phone is left to the GPU', () {
      // A portrait playback copy is 810 wide, so a 1080-wide screen shows it
      // at 1.33x before anybody pinches: nothing a render would improve.
      expect(
        detailCropFor(
          frameWidth: 810,
          frameHeight: 1440,
          visible: const Rect.fromLTWH(0, 0, 1, 1),
          magnification: 1080 / 810,
        ),
        isNull,
      );
    });

    test('the crop widens outwards to even pixels and is placed by them', () {
      final crop = detailCropFor(
        frameWidth: 2560,
        frameHeight: 1440,
        // 1000.4..1321.1 across, 600.9..781.3 down.
        visible: const Rect.fromLTRB(
            1000.4 / 2560, 600.9 / 1440, 1321.1 / 2560, 781.3 / 1440),
        magnification: 3,
      )!;
      expect(crop.x, 1000);
      expect(crop.y, 600);
      expect(crop.x + crop.width, 1322);
      expect(crop.y + crop.height, 782);
      expect(crop.x.isEven && crop.y.isEven, isTrue);
      expect(crop.width.isEven && crop.height.isEven, isTrue);
      expect(crop.outWidth, crop.width * 3);
      expect(crop.outHeight, crop.height * 3);
      // Everything asked for is inside what was cut.
      expect(crop.normalized.left, lessThanOrEqualTo(1000.4 / 2560));
      expect(crop.normalized.right, greaterThanOrEqualTo(1321.1 / 2560));
    });

    test('an edge already on the grid is not widened', () {
      final crop = detailCropFor(
        frameWidth: 2560,
        frameHeight: 1440,
        visible: const Rect.fromLTRB(
            1200 / 2560, 600 / 1440, 1520 / 2560, 780 / 1440),
        magnification: 4,
      )!;
      expect([crop.x, crop.y, crop.width, crop.height], [1200, 600, 320, 180]);
    });

    test('never runs past the frame', () {
      final crop = detailCropFor(
        frameWidth: 1080,
        frameHeight: 1920,
        visible: const Rect.fromLTRB(0.9, 0.95, 1, 1),
        magnification: 4,
      )!;
      expect(crop.x + crop.width, 1080);
      expect(crop.y + crop.height, 1920);
    });

    test('a huge ask is capped rather than decoded whole', () {
      final crop = detailCropFor(
        frameWidth: 2560,
        frameHeight: 1440,
        visible: const Rect.fromLTWH(0, 0, 0.5, 0.5),
        magnification: 3,
      )!;
      expect(crop.outWidth * crop.outHeight,
          lessThanOrEqualTo(kDetailMaxPixels * 1.01));
      expect(crop.outWidth / crop.outHeight, closeTo(1280 / 720, 0.01));
    });
  });

  group('detailTarget', () {
    const fps = 30.0;
    const frameUs = 1e6 / fps;
    final seek45 = _us(seekTargetSeconds(45 / fps, 1 / fps) * 1e6);

    test('a player seeked onto a frame is drawn at that same seek', () {
      final target = detailTarget(position: seek45, lastSeek: seek45, fps: fps);
      expect(target.at, seek45);
      expect(target.seek, isFalse);
    });

    test('a player reporting the frame\'s own timestamp is the same frame', () {
      final target =
          detailTarget(position: _us(45 * frameUs), lastSeek: seek45, fps: fps);
      expect(target.at, seek45);
      expect(target.seek, isFalse);
    });

    test('a player reporting whole milliseconds is the same frame', () {
      final target = detailTarget(
          position: Duration(milliseconds: seek45.inMilliseconds),
          lastSeek: seek45,
          fps: fps);
      expect(target.at, seek45);
    });

    test('paused out of playback, it is the frame reached, and a seek to it',
        () {
      // Three quarters of the way through frame 45: the player is showing
      // 45, and the nearest frame — 46 — would be the wrong one.
      final target = detailTarget(
          position: _us(45.75 * frameUs),
          lastSeek: const Duration(seconds: 0),
          fps: fps);
      expect(target.at, seek45);
      expect(target.seek, isTrue);
    });

    test('with nothing ever seeked, it reads the frame the same way', () {
      final target =
          detailTarget(position: _us(45.2 * frameUs), lastSeek: null, fps: fps);
      expect(target.at, seek45);
      expect(target.seek, isTrue);
    });
  });

  group('ZoomDetail', () {
    const crop = DetailCrop(
      frameWidth: 2560,
      frameHeight: 1440,
      x: 0,
      y: 0,
      width: 320,
      height: 180,
      outWidth: 960,
      outHeight: 540,
    );
    DetailJob job(int ms, [DetailCrop c = crop]) =>
        DetailJob(at: Duration(milliseconds: ms), crop: c);

    late ui.Image picture;
    setUpAll(() async => picture = await _image());

    test('a render is shown, and the same ask is not rendered twice', () async {
      final asked = <DetailJob>[];
      final detail = ZoomDetail((j) async {
        asked.add(j);
        return picture.clone();
      });
      detail.request(job(100));
      await pumpEventQueue();
      expect(detail.shown, job(100));
      expect(detail.image, isNotNull);
      detail.request(job(100));
      await pumpEventQueue();
      expect(asked, [job(100)]);
      detail.dispose();
    });

    test('a render for a frame that has gone is thrown away', () async {
      final detail = ZoomDetail((j) async {
        await Future<void>.delayed(Duration.zero);
        return picture.clone();
      });
      detail.request(job(100));
      detail.clear();
      await pumpEventQueue();
      expect(detail.image, isNull);
      expect(detail.shown, isNull);
      detail.dispose();
    });

    test('only the latest ask waits behind a render in flight', () async {
      final asked = <DetailJob>[];
      final detail = ZoomDetail((j) async {
        asked.add(j);
        await Future<void>.delayed(Duration.zero);
        return picture.clone();
      });
      const other = DetailCrop(
        frameWidth: 2560,
        frameHeight: 1440,
        x: 2,
        y: 0,
        width: 320,
        height: 180,
        outWidth: 960,
        outHeight: 540,
      );
      detail.request(job(100));
      detail.request(job(100, other));
      detail.request(job(200));
      await pumpEventQueue();
      expect(asked, [job(100), job(200)]);
      expect(detail.shown, job(200));
      detail.dispose();
    });

    test('a failed render leaves the soft frame, not an error', () async {
      final detail = ZoomDetail((j) async => throw StateError('no ffmpeg'));
      detail.request(job(100));
      await pumpEventQueue();
      expect(detail.image, isNull);
      detail.dispose();
    });
  });

  test('ffmpeg seeks before it opens the clip and crops before it scales', () {
    final command = VideoOptimizer.detailCommand(
      videoPath: '/clips/a.mp4',
      outPath: '/tmp/d.jpg',
      at: const Duration(microseconds: 1491667),
      crop: const DetailCrop(
        frameWidth: 2560,
        frameHeight: 1440,
        x: 1200,
        y: 600,
        width: 320,
        height: 180,
        outWidth: 1080,
        outHeight: 608,
      ),
      color: VideoOptimizer.jpegColorFilter(colorSpace: 'bt709'),
    );
    expect(command.indexOf('-ss 1.491667'),
        lessThan(command.indexOf('-i "/clips/a.mp4"')));
    expect(command, contains('scale=2560:1440,crop=320:180:1200:600:exact=1'));
    expect(command.indexOf('crop='), lessThan(command.indexOf('lanczos')));
    expect(command, contains('-frames:v 1'));
  });

  test('the zoomed picture is held inside the clip\'s own pixels', () {
    // Unclamped, lanczos overshoots: halos round every hard edge and colors
    // stronger than any in the clip. The clamp is what stops it, so it has
    // to be there, with no slack, and the color written after it — a JPEG's
    // numbers are not the clip's.
    final command = VideoOptimizer.detailCommand(
      videoPath: '/clips/a.mp4',
      outPath: '/tmp/d.jpg',
      at: Duration.zero,
      crop: const DetailCrop(
        frameWidth: 2560,
        frameHeight: 1440,
        x: 0,
        y: 0,
        width: 320,
        height: 180,
        outWidth: 1080,
        outHeight: 608,
      ),
      color: VideoOptimizer.jpegColorFilter(colorSpace: 'bt709'),
    );
    expect(command, contains('[lo]erosion,scale=1080:608:flags=bilinear'));
    expect(command, contains('[hi]dilation,scale=1080:608:flags=bilinear'));
    expect(command, contains('maskedclamp=undershoot=0:overshoot=0'));
    expect(
        command.indexOf('maskedclamp'),
        lessThan(command.indexOf('in_color_matrix=bt709:'
            'out_color_matrix=bt601:out_range=pc')));
    // No sharpening: in a phone's footage the finest thing on the frame is
    // the compression, and the clamp can't catch it inside its own range.
    expect(command, isNot(contains('unsharp')));
    expect(command, contains('[pic]scale=1080:608:flags=lanczos[sharp]'));
  });

  group('on the analysis screen', () {
    late Directory temp;
    late ui.Image picture;
    final asked = <DetailJob>[];

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('throwlab_detail');
      asked.clear();
    });
    tearDown(() {
      AnalysisScreen.debugRenderDetail = null;
      temp.deleteSync(recursive: true);
    });

    Future<void> mount(WidgetTester tester, {bool current = true}) async {
      picture = (await tester.runAsync(_image))!;
      AnalysisScreen.debugRenderDetail = (job) async {
        asked.add(job);
        return picture.clone();
      };
      final video = testVideo(temp);
      if (current) video.playbackVersion = VideoOptimizer.playbackVersion;
      await mountAnalysisScreen(tester,
          video: video,
          screen: const Size(800, 600),
          videoSize: const Size(1920, 1080));
    }

    ui.Image? drawn(WidgetTester tester) {
      final images = find.descendant(
          of: find.byType(DetailStill), matching: find.byType(RawImage));
      if (images.evaluate().isEmpty) return null;
      return tester.widget<RawImage>(images).image;
    }

    testWidgets('an unzoomed frame asks for nothing', (tester) async {
      await mount(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(asked, isEmpty);
      expect(drawn(tester), isNull);
    });

    testWidgets('a clip whose copy may be replaced under it stays soft',
        (tester) async {
      await mount(tester, current: false);
      await pinchOut(tester, const Offset(400, 300), 240);
      await tester.pump(const Duration(milliseconds: 500));
      expect(asked, isEmpty);
    });

    testWidgets('a zoomed frame is drawn sharp once the fingers stop',
        (tester) async {
      await mount(tester);
      await pinchOut(tester, const Offset(400, 300), 240);
      expect(asked, isEmpty, reason: 'nothing until the picture settles');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(asked, hasLength(1));
      final crop = asked.single.crop;
      expect(crop.frameWidth, 1920);
      expect(crop.frameHeight, 1080);
      // A piece of the frame, not the frame, drawn larger than the clip has
      // it: at about the screen's own pixels, which is no more than the
      // screen is wide.
      expect(crop.width, lessThan(1920 / 2));
      expect(crop.outWidth / crop.width,
          greaterThanOrEqualTo(kDetailMinMagnification));
      expect(crop.outWidth, lessThanOrEqualTo(800 + 8));
      expect(drawn(tester), isNotNull);
    });

    testWidgets('stepping to another frame takes the still down',
        (tester) async {
      await mount(tester);
      await pinchOut(tester, const Offset(400, 300), 240);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(drawn(tester), isNotNull);
      final first = asked.single.at;

      await tester.tap(find.byTooltip('Forward one frame'));
      await tester.pump();
      await tester.pump();
      expect(drawn(tester), isNull,
          reason: 'a still of the last frame over this one is a wrong frame');

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(asked, hasLength(2));
      expect(asked.last.at, greaterThan(first));
      expect(drawn(tester), isNotNull);
    });
  });

  group('FrameSeeker.lastTargetOf', () {
    late Directory temp;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('throwlab_seek');
      VideoPlayerPlatform.instance =
          FakeVideoPlayerPlatform(const Size(1920, 1080));
    });
    tearDown(() => temp.deleteSync(recursive: true));

    testWidgets('every seeker on one player shares it', (tester) async {
      final file = File('${temp.path}/clip.mp4')..writeAsBytesSync(<int>[0]);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      addTearDown(() {
        controller.dispose();
      });

      expect(FrameSeeker.lastTargetOf(controller), isNull);
      FrameSeeker(controller).seekTo(const Duration(milliseconds: 400));
      expect(FrameSeeker.lastTargetOf(controller),
          const Duration(milliseconds: 400));
      FrameSeeker(controller).seekTo(const Duration(milliseconds: 700));
      expect(FrameSeeker.lastTargetOf(controller),
          const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.white);
  return recorder.endRecording().toImage(4, 4);
}
