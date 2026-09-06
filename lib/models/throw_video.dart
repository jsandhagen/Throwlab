import 'throw_event.dart';

/// Throws imported before implements were picked by weight stored a gender
/// instead. Those clips were thrown with the senior implement for it, which
/// is what the old two-way choice meant.
double _legacyWeight(ThrowEvent event, String? gender) {
  final women = gender == 'women';
  return switch (event) {
    ThrowEvent.shotPut => women ? 4 : 7.26,
    ThrowEvent.discus => women ? 1 : 2,
    ThrowEvent.hammer => women ? 4 : 7.26,
    ThrowEvent.javelin => women ? 0.6 : 0.8,
  };
}

/// An imported throw recording plus the metadata needed to analyze it.
class ThrowVideo {
  ThrowVideo({
    required this.id,
    required this.path,
    required this.event,
    required this.implementKg,
    required this.importedAt,
    this.recordedAt,
    this.fps = 30,
    double? captureFps,
    this.note = '',
    this.athlete = '',
    this.distance,
    this.thumbnailPath,
    this.scrubFramesDir,
    this.scrubFrameCount = 0,
    this.scrubFrameStride = 1,
    this.scrubFrameLongSide = 0,
    this.scrubFramesVersion = 0,
    this.playbackVersion = 0,
  }) : captureFps = captureFps ?? fps;

  final String id;

  /// The file the app plays: the optimized copy when one was made, otherwise
  /// the imported original. Reassigned when the copy is re-made under a newer
  /// recipe.
  String path;
  final ThrowEvent event;
  /// What the implement weighs, in kilograms. Fixes the dimensions the
  /// analyzer calibrates against — see [ImplementSpec].
  double implementKg;
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

  /// How far it went, in metres; null until someone records it. The one
  /// number a throw is actually judged by, so it leads on the card.
  double? distance;

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

  /// Longest-side pixels the scrub frames were extracted at; 0 for clips
  /// from before this was recorded.
  int scrubFrameLongSide;

  /// Which extraction recipe produced the stills. Bumped whenever their
  /// resolution or geometry changes, so clips extracted by an older recipe
  /// re-extract on open instead of scrubbing at the wrong size or shape.
  /// See VideoOptimizer.scrubFramesVersion.
  int scrubFramesVersion;

  /// Which recipe produced the playback copy. Bumped when its geometry
  /// changes, so a clip encoded by an older one is re-made rather than left
  /// disagreeing with the stills drawn over it.
  /// See VideoOptimizer.playbackVersion.
  int playbackVersion;

  ImplementSpec get implementSpec => event.specFor(implementKg);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'event': event.name,
        'implementKg': implementKg,
        'importedAt': importedAt.toIso8601String(),
        'recordedAt': recordedAt?.toIso8601String(),
        'fps': fps,
        'captureFps': captureFps,
        'note': note,
        'athlete': athlete,
        'distance': distance,
        'thumbnailPath': thumbnailPath,
        'scrubFramesDir': scrubFramesDir,
        'scrubFrameCount': scrubFrameCount,
        'scrubFrameStride': scrubFrameStride,
        'scrubFrameLongSide': scrubFrameLongSide,
        'scrubFramesVersion': scrubFramesVersion,
        'playbackVersion': playbackVersion,
      };

  factory ThrowVideo.fromJson(Map<String, dynamic> json) => ThrowVideo(
        id: json['id'] as String,
        path: json['path'] as String,
        event: ThrowEvent.values.byName(json['event'] as String),
        implementKg: (json['implementKg'] as num?)?.toDouble() ??
            _legacyWeight(
              ThrowEvent.values.byName(json['event'] as String),
              json['gender'] as String?,
            ),
        importedAt: DateTime.parse(json['importedAt'] as String),
        recordedAt: json['recordedAt'] == null
            ? null
            : DateTime.tryParse(json['recordedAt'] as String),
        fps: (json['fps'] as num?)?.toDouble() ?? 30,
        captureFps: (json['captureFps'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
        athlete: json['athlete'] as String? ?? '',
        distance: (json['distance'] as num?)?.toDouble(),
        thumbnailPath: json['thumbnailPath'] as String?,
        scrubFramesDir: json['scrubFramesDir'] as String?,
        scrubFrameCount: (json['scrubFrameCount'] as num?)?.toInt() ?? 0,
        scrubFrameStride: (json['scrubFrameStride'] as num?)?.toInt() ?? 1,
        scrubFrameLongSide:
            (json['scrubFrameLongSide'] as num?)?.toInt() ?? 0,
        scrubFramesVersion:
            (json['scrubFramesVersion'] as num?)?.toInt() ?? 0,
        playbackVersion: (json['playbackVersion'] as num?)?.toInt() ?? 0,
      );
}
