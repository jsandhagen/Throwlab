import 'package:flutter/material.dart';

import '../models/throw_video.dart';
import 'throw_card.dart';

/// How far it went, in whichever unit the meet measured in.
///
/// Two boxes side by side, each showing the other's number converted: type
/// 58.42 in meters and 191.67 appears in feet. Which box was typed in is
/// what the throw remembers, so a distance measured in feet reads back in
/// feet rather than as its metric equivalent.
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
  late final TextEditingController _feet = TextEditingController(
      text: widget.meters == null ? '' : _text(widget.meters! / metersPerFoot));

  static String _text(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  @override
  void dispose() {
    _meters.dispose();
    _feet.dispose();
    super.dispose();
  }

  void _typedMeters(String text) {
    final meters = parseDistanceValue(text);
    // Setting a controller's text doesn't fire its onChanged, so writing
    // the conversion into the other box can't bounce back into this one.
    _feet.text = meters == null ? '' : _text(meters / metersPerFoot);
    widget.onChanged(meters, DistanceUnit.meters);
  }

  void _typedFeet(String text) {
    final feet = parseFeet(text);
    _meters.text = feet == null ? '' : _text(feet * metersPerFoot);
    widget.onChanged(
        feet == null ? null : feet * metersPerFoot, DistanceUnit.feet);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
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
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _feet,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _typedFeet,
            decoration: const InputDecoration(
              labelText: 'Feet',
              hintText: '191-08',
              suffixText: 'ft',
            ),
          ),
        ),
      ],
    );
  }
}
