import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/video_optimizer.dart';

void main() {
  group('ImplementSpec', () {
    test('javelin reference is its length', () {
      final spec = ThrowEvent.javelin.specFor(Gender.men);
      expect(spec.referenceLabel, 'Length');
      expect(spec.minSize, 2.6);
      expect(spec.maxSize, 2.7);
      expect(spec.nominalSize, closeTo(2.65, 1e-9));
    });

    test('every event/gender combination has a positive size range', () {
      for (final event in ThrowEvent.values) {
        for (final gender in Gender.values) {
          final spec = event.specFor(gender);
          expect(spec.minSize, greaterThan(0));
          expect(spec.maxSize, greaterThanOrEqualTo(spec.minSize));
        }
      }
    });

    test('women\'s discus is smaller than men\'s', () {
      expect(ThrowEvent.discus.specFor(Gender.women).nominalSize,
          lessThan(ThrowEvent.discus.specFor(Gender.men).nominalSize));
    });
  });

  group('ThrowVideo', () {
    test('survives a JSON round trip', () {
      final video = ThrowVideo(
        id: '42',
        path: '/videos/throw.mp4',
        event: ThrowEvent.discus,
        gender: Gender.women,
        importedAt: DateTime.parse('2026-06-11T10:30:00'),
        fps: 240,
        note: 'PB attempt',
        athlete: 'Sam',
        thumbnailPath: '/thumbs/42.jpg',
      );
      final restored = ThrowVideo.fromJson(video.toJson());
      expect(restored.id, video.id);
      expect(restored.path, video.path);
      expect(restored.event, video.event);
      expect(restored.gender, video.gender);
      expect(restored.importedAt, video.importedAt);
      expect(restored.fps, video.fps);
      expect(restored.note, video.note);
      expect(restored.athlete, video.athlete);
      expect(restored.thumbnailPath, video.thumbnailPath);
    });

    test('defaults fps to 30 when missing from stored JSON', () {
      final restored = ThrowVideo.fromJson({
        'id': '1',
        'path': '/v.mp4',
        'event': 'shotPut',
        'gender': 'men',
        'importedAt': '2026-06-11T10:30:00',
      });
      expect(restored.fps, 30);
      expect(restored.note, '');
      expect(restored.athlete, '');
      expect(restored.thumbnailPath, isNull);
    });

    test('captureFps round-trips and defaults to fps when missing', () {
      final slowMo = ThrowVideo(
        id: '2',
        path: '/v.mp4',
        event: ThrowEvent.javelin,
        gender: Gender.women,
        importedAt: DateTime.parse('2026-06-11T10:30:00'),
        fps: 30,
        captureFps: 240,
      );
      expect(ThrowVideo.fromJson(slowMo.toJson()).captureFps, 240);

      final legacy = ThrowVideo.fromJson({
        'id': '3',
        'path': '/v.mp4',
        'event': 'javelin',
        'gender': 'men',
        'importedAt': '2026-06-11T10:30:00',
        'fps': 120,
      });
      expect(legacy.captureFps, 120);
    });

    test('scrub frame details round-trip', () {
      final video = ThrowVideo(
        id: '4',
        path: '/v.mp4',
        event: ThrowEvent.discus,
        gender: Gender.women,
        importedAt: DateTime.parse('2026-06-11T10:30:00'),
        fps: 60,
        scrubFramesDir: '/frames/4',
        scrubFrameCount: 300,
        scrubFrameStride: 2,
        scrubFrameLongSide: 1440,
        scrubFramesVersion: VideoOptimizer.scrubFramesVersion,
      );
      final restored = ThrowVideo.fromJson(video.toJson());
      expect(restored.scrubFramesDir, '/frames/4');
      expect(restored.scrubFrameCount, 300);
      expect(restored.scrubFrameStride, 2);
      expect(restored.scrubFrameLongSide, 1440);
      expect(restored.scrubFramesVersion, VideoOptimizer.scrubFramesVersion);
    });

    test('clips stored before scrub frames report none, at no resolution',
        () {
      final legacy = ThrowVideo.fromJson({
        'id': '5',
        'path': '/v.mp4',
        'event': 'discus',
        'gender': 'women',
        'importedAt': '2026-06-11T10:30:00',
        'fps': 60,
      });
      expect(legacy.scrubFramesDir, isNull);
      expect(legacy.scrubFrameCount, 0);
      expect(legacy.scrubFrameStride, 1);
      expect(legacy.scrubFrameLongSide, 0);
      // Version 0 < current, so opening the clip re-extracts.
      expect(legacy.scrubFramesVersion, 0);
      expect(legacy.scrubFramesVersion,
          lessThan(VideoOptimizer.scrubFramesVersion));
      // Same for the video the stills are drawn over: a clip stored before
      // the playback copy carried a recipe is due to be re-made, otherwise
      // its square-pixel stills would keep covering a non-square video.
      expect(legacy.playbackVersion, 0);
      expect(
          legacy.playbackVersion, lessThan(VideoOptimizer.playbackVersion));
    });

    test('a current playback copy survives a round trip and is not re-made',
        () {
      final video = ThrowVideo(
        id: '7',
        path: '/v.mp4',
        event: ThrowEvent.discus,
        gender: Gender.women,
        importedAt: DateTime.parse('2026-06-11T10:30:00'),
        playbackVersion: VideoOptimizer.playbackVersion,
      );
      final restored = ThrowVideo.fromJson(video.toJson());
      expect(restored.playbackVersion, VideoOptimizer.playbackVersion);
      expect(restored.playbackVersion,
          isNot(lessThan(VideoOptimizer.playbackVersion)));
    });

    test('stills from an older recipe are due for re-extraction', () {
      // Full resolution, but extracted before the aspect-ratio fix: the
      // version is what flags it, not the pixel count.
      final old = ThrowVideo.fromJson({
        'id': '6',
        'path': '/v.mp4',
        'event': 'discus',
        'gender': 'women',
        'importedAt': '2026-06-11T10:30:00',
        'fps': 60,
        'scrubFramesDir': '/frames/6',
        'scrubFrameCount': 300,
        'scrubFrameLongSide': VideoOptimizer.scrubFrameMax,
        'scrubFramesVersion': 2,
      });
      expect(old.scrubFrameLongSide, VideoOptimizer.scrubFrameMax);
      expect(old.scrubFramesVersion,
          lessThan(VideoOptimizer.scrubFramesVersion));
    });
  });
}
