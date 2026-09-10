import 'package:flutter/material.dart';

import '../models/throw_video.dart';
import 'throw_card.dart';

/// How far it went, in whichever unit the meet measured in.
///
/// Meters on one side, feet *and* inches on the other, each showing the
/// other's number converted: type 58.42 in meters and 191 ft 8 in appears
/// beside it. Feet and inches get a box each because a phone's number
/// keyboard has no dash — "191-08" cannot be typed on one, which is why the
/// old single feet box could not be filled at a track. Which side was typed
/// in is what the throw remembers, so a distance measured in feet reads back
/// in feet rather than as its metric equivalent.
class DistanceField extends StatefulWidget {
  const DistanceField({
    super.key,
    required this.meters,
    required this.unit,
    required this.onChanged,
    this.autofocus = false,
  });

  final double? meters;
  final DistanceUnit unit;

  /// Null meters means the distance was cleared — a foul, or one not
  /// measured yet.
  final void Function(double? meters, DistanceUnit unit) onChanged;

  final bool autofocus;

  @override
  State<DistanceField> createState() => _DistanceFieldState();
}

class _DistanceFieldState extends State<DistanceField> {
  late final TextEditingController _meters =
      TextEditingController(text: _text(widget.meters));
  late final TextEditingController _feet =
      TextEditingController(text: _imperial(widget.meters).$1);
  late final TextEditingController _inches =
      TextEditingController(text: _imperial(widget.meters).$2);

  static String _text(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  /// Meters as a (whole feet, inches) pair for the two boxes. A conversion
  /// rarely lands on a whole inch, so inches carry one decimal — and a
  /// trailing ".0" is dropped, since a coach reads "8" as eight inches.
  static (String, String) _imperial(double? meters) {
    if (meters == null) return ('', '');
    final totalFeet = meters / metersPerFoot;
    final feet = totalFeet.floor();
    final inches = (totalFeet - feet) * 12;
    final text = inches.toStringAsFixed(1);
    return (
      feet.toString(),
      text.endsWith('.0') ? text.substring(0, text.length - 2) : text,
    );
  }

  @override
  void dispose() {
    _meters.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  void _typedMeters(String text) {
    final meters = parseDistanceValue(text);
    // Setting a controller's text doesn't fire its onChanged, so writing
    // the conversion into the other boxes can't bounce back into this one.
    final (feet, inches) = _imperial(meters);
    _feet.text = feet;
    _inches.text = inches;
    widget.onChanged(meters, DistanceUnit.meters);
  }

  /// Fired by either imperial box — the throw's distance is feet and inches
  /// read together, so a change to one is recomputed against the other.
  void _typedImperial(String _) {
    final feet = parseDistanceValue(_feet.text);
    final inches = parseDistanceValue(_inches.text);
    // Both boxes empty clears the throw's distance; a value in either is a
    // measurement, with the empty box read as zero.
    if (feet == null && inches == null) {
      _meters.text = '';
      widget.onChanged(null, DistanceUnit.feet);
      return;
    }
    final meters = ((feet ?? 0) + (inches ?? 0) / 12) * metersPerFoot;
    _meters.text = _text(meters);
    widget.onChanged(meters, DistanceUnit.feet);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _meters,
            autofocus: widget.autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _typedMeters,
            decoration: const InputDecoration(
              labelText: 'Meters',
              hintText: '58.42',
              suffixText: 'm',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _feet,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _typedImperial,
            decoration: const InputDecoration(
              labelText: 'Feet',
              hintText: '191',
              suffixText: 'ft',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _inches,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _typedImperial,
            decoration: const InputDecoration(
              labelText: 'Inches',
              hintText: '8',
              suffixText: 'in',
            ),
          ),
        ),
      ],
    );
  }
}
