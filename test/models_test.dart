import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/video_optimizer.dart';

void main() {
  group('an implement named in pounds', () {
    test('is offered as its own weight, not folded into the nearest kilo', () {
      final twelve = ThrowEvent.shotPut.implements
          .firstWhere((spec) => spec.weightKg == 5.44);
      expect(twelve.weightLabel, '12 lb');
      // A best is per implement, so it has to be distinct from the 5 kg.
      expect(ThrowEvent.shotPut.implements.map((s) => s.weightKg),
          containsAll([5.44, 5]));
    });

    test('is what a weight in pounds resolves to', () {
      expect(ThrowEvent.shotPut.specFor(12 * 0.45359237).weightKg, 5.44);
    });

    test('is not how the high school discus is named', () {
      // A 1.6 kg discus is called a 1.6 everywhere it is thrown, never a
      // 3.5 lb, so it keeps its metric weight where the shot does not.
      final sixteen = ThrowEvent.discus.implements
          .firstWhere((spec) => spec.weightKg == 1.6);
      expect(sixteen.weightLabel, '1.6 kg');
      // Its own weight, distinct from the 1.5 kg it is shelled from.
      expect(ThrowEvent.discus.implements.map((s) => s.weightKg),
          containsAll([1.75, 1.6, 1.5]));
      expect(ThrowEvent.discus.specFor(1.6).weightKg, 1.6);
      // And what a sheet naming it in pounds resolves to.
      expect(ThrowEvent.discus.specFor(3.5 * 0.45359237).weightKg, 1.6);
    });

    test('leaves the metric implements naming themselves in kilos', () {
      expect(ThrowEvent.shotPut.specFor(7.26).weightLabel, '7.26 kg');
      expect(ThrowEvent.javelin.specFor(0.6).weightLabel, '600 g');
    });
  });

  test('a throw stored as metres still reads as meters', () {
    // Spelled the British way before the app settled on American English.
    // Nothing migrates it: the fallback every fromJson already had names
    // the same unit it was written as.
    final mark = ThrowMark.fromJson({
      'id': 'm1',
      'athlete': 'Ana Diaz',
      'event': 'discus',
      'implementKg': 1,
      'distance': 41.2,
      'distanceUnit': 'metres',
      'achievedOn': DateTime(2026, 5, 1).toIso8601String(),
    });
    expect(mark.distanceUnit, DistanceUnit.meters);
    expect(mark.distance, 41.2);
  });

  group('ImplementSpec', () {
    test('javelin reference is its length', () {
      final spec = ThrowEvent.javelin.specFor(0.8);
      expect(spec.referenceLabel, 'Length');
      expect(spec.minSize, 2.6);
      expect(spec.maxSize, 2.7);
      expect(spec.nominalSize, closeTo(2.65, 1e-9));
    });

    test('every implement of every event has a positive size range', () {
      for (final event in ThrowEvent.values) {
        expect(event.implements, isNotEmpty);
        for (final spec in event.implements) {
          expect(spec.weightKg, greaterThan(0));
          expect(spec.minSize, greaterThan(0));
          expect(spec.maxSize, greaterThanOrEqualTo(spec.minSize));
          expect(spec.usedBy, isNotEmpty);
        }
      }
    });

    test('an event lists its implements heaviest first, each weight once', () {
      for (final event in ThrowEvent.values) {
        final weights = [for (final spec in event.implements) spec.weightKg];
        expect(weights, weights.toSet().toList());
        expect(weights,
            orderedEquals([...weights]..sort((a, b) => b.compareTo(a))));
        expect(event.defaultImplement, event.implements.first);
      }
    });

    test('a lighter implement is a smaller one', () {
      // What the whole change is for: the reference dimension follows the
      // weight, so an M60's 5 kg shot isn't measured as a 7.26 kg one.
      expect(ThrowEvent.shotPut.specFor(5).nominalSize,
          lessThan(ThrowEvent.shotPut.specFor(7.26).nominalSize));
      expect(ThrowEvent.discus.specFor(1).nominalSize,
          lessThan(ThrowEvent.discus.specFor(2).nominalSize));
      expect(ThrowEvent.javelin.specFor(0.6).nominalSize,
          lessThan(ThrowEvent.javelin.specFor(0.8).nominalSize));
    });

    test('a weight off the list falls back to the nearest one thrown', () {
      // A hand-edited store, or a spec table that changed under an old
      // import: still calibrate, don't crash.
      expect(ThrowEvent.shotPut.specFor(7.257).weightKg, 7.26);
      expect(ThrowEvent.discus.specFor(0).weightKg, 0.75);
      expect(ThrowEvent.hammer.specFor(99).weightKg, 7.26);
    });

    test('a hammer head is the shot of the same weight', () {
      for (final hammer in ThrowEvent.hammer.implements) {
        final shot = ThrowEvent.shotPut.specFor(hammer.weightKg);
        expect(shot.weightKg, hammer.weightKg);
        expect(hammer.minSize, shot.minSize);
        expect(hammer.maxSize, shot.maxSize);
      }
    });

    test('weights read the way they are spoken about', () {
      expect(ThrowEvent.shotPut.specFor(7.26).weightLabel, '7.26 kg');
      expect(ThrowEvent.discus.specFor(1).weightLabel, '1 kg');
      expect(ThrowEvent.discus.specFor(1.75).weightLabel, '1.75 kg');
      expect(ThrowEvent.javelin.specFor(0.6).weightLabel, '600 g');
    });
  });

  group('ThrowVideo', () {
    test('survives a JSON round trip', () {
      final video = ThrowVideo(
        id: '42',
        path: '/videos/throw.mp4',
        event: ThrowEvent.discus,
        implementKg: 1,
        importedAt: DateTime.parse('2026-06-11T10:30:00'),
        fps: 240,
        note: 'PB attempt',
        athlete: 'Sam',
        distance: 58.42,
        distanceUnit: DistanceUnit.feet,
        thumbnailPath: '/thumbs/42.jpg',
      );
      final restored = ThrowVideo.fromJson(video.toJson());
      expect(restored.id, video.id);
      expect(restored.path, video.path);
      expect(restored.event, video.event);
      expect(restored.importedAt, video.importedAt);
      expect(restored.fps, video.fps);
      expect(restored.note, video.note);
      expect(restored.athlete, video.athlete);
      expect(restored.distance, video.distance);
      expect(restored.implementKg, video.implementKg);
      expect(restored.distanceUnit, DistanceUnit.feet);
      expect(restored.thumbnailPath, video.thumbnailPath);
    });

    test('a throw stored as men or women migrates to that implement', () {
      ThrowVideo stored(String event, String gender) => ThrowVideo.fromJson({
            'id': '1',
            'path': '/v.mp4',
            'event': event,
            'gender': gender,
            'importedAt': '2026-06-11T10:30:00',
          });
      expect(stored('shotPut', 'men').implementKg, 7.26);
      expect(stored('shotPut', 'women').implementKg, 4);
      expect(stored('discus', 'men').implementKg, 2);
      expect(stored('discus', 'women').implementKg, 1);
      expect(stored('hammer', 'women').implementKg, 4);
      expect(stored('javelin', 'men').implementKg, 0.8);
      expect(stored('javelin', 'women').implementKg, 0.6);
      // And the migrated weight is one the event is actually thrown at.
      expect(stored('discus', 'women').implementSpec.nominalSize,
          closeTo(0.181, 1e-9));
    });

    test('a distance with no stored unit is meters', () {
      final restored = ThrowVideo.fromJson({
        'id': '1',
        'path': '/v.mp4',
        'event': 'javelin',
        'implementKg': 0.8,
        'importedAt': '2026-06-11T10:30:00',
        'distance': 58.42,
      });
      expect(restored.distanceUnit, DistanceUnit.meters);
    });

    test('has no distance until one is recorded', () {
      final restored = ThrowVideo.fromJson({
        'id': '1',
        'path': '/v.mp4',
        'event': 'javelin',
        'gender': 'men',
        'importedAt': '2026-06-11T10:30:00',
      });
      expect(restored.distance, isNull);
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
        implementKg: 1,
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
        implementKg: 1,
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

    test('clips stored before scrub frames report none, at no resolution', () {
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
      expect(legacy.playbackVersion, lessThan(VideoOptimizer.playbackVersion));
    });

    test('a current playback copy survives a round trip and is not re-made',
        () {
      final video = ThrowVideo(
        id: '7',
        path: '/v.mp4',
        event: ThrowEvent.discus,
        implementKg: 1,
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
      expect(
          old.scrubFramesVersion, lessThan(VideoOptimizer.scrubFramesVersion));
    });
  });
}
