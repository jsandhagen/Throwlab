import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';

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
  });
}
