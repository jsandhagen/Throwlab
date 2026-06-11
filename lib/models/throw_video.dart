import 'throw_event.dart';

/// An imported throw recording plus the metadata needed to analyze it.
class ThrowVideo {
  ThrowVideo({
    required this.id,
    required this.path,
    required this.event,
    required this.gender,
    required this.importedAt,
    this.fps = 30,
    double? captureFps,
    this.note = '',
    this.athlete = '',
    this.thumbnailPath,
  }) : captureFps = captureFps ?? fps;

  final String id;
  final String path;
  final ThrowEvent event;
  final Gender gender;
  final DateTime importedAt;

  /// Container/playback frame rate, probed from metadata on import.
  /// Drives frame-step size and frame numbering.
  double fps;

  /// Real recorded frame rate — the physics time base. Slow-mo clips often
  /// play at 30 fps while each stored frame represents 1/240 s of real
  /// time; equals [fps] for normal clips.
  double captureFps;

  String note;

  /// Who threw it; empty when not assigned to anyone.
  String athlete;

  /// Still frame extracted on import; null for videos imported before
  /// thumbnails existed or when extraction failed.
  String? thumbnailPath;

  ImplementSpec get implementSpec => event.specFor(gender);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'event': event.name,
        'gender': gender.name,
        'importedAt': importedAt.toIso8601String(),
        'fps': fps,
        'captureFps': captureFps,
        'note': note,
        'athlete': athlete,
        'thumbnailPath': thumbnailPath,
      };

  factory ThrowVideo.fromJson(Map<String, dynamic> json) => ThrowVideo(
        id: json['id'] as String,
        path: json['path'] as String,
        event: ThrowEvent.values.byName(json['event'] as String),
        gender: Gender.values.byName(json['gender'] as String),
        importedAt: DateTime.parse(json['importedAt'] as String),
        fps: (json['fps'] as num?)?.toDouble() ?? 30,
        captureFps: (json['captureFps'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
        athlete: json['athlete'] as String? ?? '',
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}
