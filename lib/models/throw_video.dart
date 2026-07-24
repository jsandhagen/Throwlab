import 'throw_event.dart';

/// An imported throw recording plus the metadata needed to analyze it.
class ThrowVideo {
  ThrowVideo({
    required this.id,
    required this.path,
    required this.event,
    required this.gender,
    required this.importedAt,
    this.recordedAt,
    this.fps = 30,
    double? captureFps,
    this.note = '',
    this.athlete = '',
    this.thumbnailPath,
    this.scrubFramesDir,
    this.scrubFrameCount = 0,
    this.scrubFrameStride = 1,
  }) : captureFps = captureFps ?? fps;

  final String id;
  final String path;
  final ThrowEvent event;
  final Gender gender;
  final DateTime importedAt;

  /// When the camera recorded the clip (from the file's creation_time
  /// metadata, UTC); null when the tag was absent or for old imports.
  final DateTime? recordedAt;

  /// The date shown for this throw: the recording time when known,
  /// otherwise the import time.
  DateTime get displayDate => recordedAt ?? importedAt;

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

  /// Directory of pre-extracted scrub frames (JPEGs) shown during dragging
  /// for smooth, format-independent scrubbing; null for old imports or when
  /// extraction was skipped/failed (the app then falls back to seeking).
  String? scrubFramesDir;

  /// Number of extracted scrub frames; 0 when none.
  int scrubFrameCount;

  /// Every Nth source frame was extracted, to cap disk use on long clips;
  /// 1 means every frame is available.
  int scrubFrameStride;

  ImplementSpec get implementSpec => event.specFor(gender);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'event': event.name,
        'gender': gender.name,
        'importedAt': importedAt.toIso8601String(),
        'recordedAt': recordedAt?.toIso8601String(),
        'fps': fps,
        'captureFps': captureFps,
        'note': note,
        'athlete': athlete,
        'thumbnailPath': thumbnailPath,
        'scrubFramesDir': scrubFramesDir,
        'scrubFrameCount': scrubFrameCount,
        'scrubFrameStride': scrubFrameStride,
      };

  factory ThrowVideo.fromJson(Map<String, dynamic> json) => ThrowVideo(
        id: json['id'] as String,
        path: json['path'] as String,
        event: ThrowEvent.values.byName(json['event'] as String),
        gender: Gender.values.byName(json['gender'] as String),
        importedAt: DateTime.parse(json['importedAt'] as String),
        recordedAt: json['recordedAt'] == null
            ? null
            : DateTime.tryParse(json['recordedAt'] as String),
        fps: (json['fps'] as num?)?.toDouble() ?? 30,
        captureFps: (json['captureFps'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
        athlete: json['athlete'] as String? ?? '',
        thumbnailPath: json['thumbnailPath'] as String?,
        scrubFramesDir: json['scrubFramesDir'] as String?,
        scrubFrameCount: (json['scrubFrameCount'] as num?)?.toInt() ?? 0,
        scrubFrameStride: (json['scrubFrameStride'] as num?)?.toInt() ?? 1,
      );
}
