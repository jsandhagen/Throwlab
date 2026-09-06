import 'throw_event.dart';
import 'throw_video.dart';

/// A throw that was measured but never filmed.
///
/// Most of an athlete's results are like this: six attempts at a meet, one
/// phone, and the throw that mattered was the one nobody had the camera up
/// for. A record book that only counts what was recorded is wrong about
/// what the athlete has actually done, so a mark carries the same fields a
/// best is judged on — who, what event, what weight, how far, when — and
/// competes with the filmed throws on equal terms.
class ThrowMark implements ThrowResult {
  ThrowMark({
    required this.id,
    required this.athlete,
    required this.event,
    required this.implementKg,
    required this.distance,
    required this.achievedOn,
    this.distanceUnit = DistanceUnit.metres,
    this.note = '',
  });

  @override
  final String id;

  @override
  String athlete;

  @override
  ThrowEvent event;

  @override
  double implementKg;

  /// Metres. Never null — an unmeasured mark is not a mark, it is a memory.
  @override
  double distance;

  @override
  DistanceUnit distanceUnit;

  /// The day it was thrown. Typed in rather than inferred, because these
  /// are usually entered weeks after the meet.
  DateTime achievedOn;

  @override
  DateTime get displayDate => achievedOn;

  /// Where it happened, or anything else worth remembering about it —
  /// 'County Champs, final' is the usual shape.
  String note;

  ImplementSpec get implementSpec => event.specFor(implementKg);

  Map<String, dynamic> toJson() => {
        'id': id,
        'athlete': athlete,
        'event': event.name,
        'implementKg': implementKg,
        'distance': distance,
        'distanceUnit': distanceUnit.name,
        'achievedOn': achievedOn.toIso8601String(),
        'note': note,
      };

  factory ThrowMark.fromJson(Map<String, dynamic> json) => ThrowMark(
        id: json['id'] as String,
        athlete: json['athlete'] as String? ?? '',
        event: ThrowEvent.values.byName(json['event'] as String),
        implementKg: (json['implementKg'] as num).toDouble(),
        distance: (json['distance'] as num).toDouble(),
        distanceUnit:
            DistanceUnit.values.asNameMap()[json['distanceUnit'] as String? ?? ''] ??
                DistanceUnit.metres,
        achievedOn: DateTime.parse(json['achievedOn'] as String),
        note: json['note'] as String? ?? '',
      );
}
