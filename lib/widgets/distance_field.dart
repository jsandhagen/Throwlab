import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/throw_video.dart';
import 'throw_card.dart';

/// How far it went, in whichever unit the meet measured in.
///
/// One unit at a time, picked by the m / ft switch under the boxes. Two
/// boxes side by side, one per unit, asked a coach to look for the right
/// one every time — and a US meet never measures in meters, so half the
/// sheet was a box nobody there would ever type in. The other unit is
/// always shown underneath, converted, for the coach checking a mark against
/// a sheet printed in it.
///
/// Feet are feet *and* inches, two boxes, because that is how the mark is
/// called across the sector and printed on the program: '191-08' is a
/// hundred and ninety-one feet eight inches, and nobody has ever worked it
/// out as 191.67 to type it in. The inches take a quarter ('6.25'), and
/// the feet box still takes the whole mark the way a sheet writes it
/// ('191-08') for anybody who types it that way.
///
/// Which unit is used is remembered (`throwlab.distanceUnit`) — a coach
/// works in one or the other all season — except when a distance is
/// already there, which opens in the unit it was entered in: that is what
/// the throw remembers, and editing it must not quietly convert it.
class DistanceField extends StatefulWidget {
  const DistanceField({
    super.key,
    required this.meters,
    this.unit,
    required this.onChanged,
    this.autofocus = false,
  });

  final double? meters;

  /// The unit [meters] was entered in. Ignored when there is no distance
  /// yet: an empty field opens in the unit the coach last used.
  final DistanceUnit? unit;

  /// Null meters means the distance was cleared — a foul, or one not
  /// measured yet. Also called when only the unit changes, so what is
  /// saved is in the unit on screen.
  final void Function(double? meters, DistanceUnit unit) onChanged;

  final bool autofocus;

  static const _prefKey = 'throwlab.distanceUnit';

  /// The unit a new distance is typed in, as last read from storage. Held
  /// here so a sheet opens in the right unit on its first frame rather
  /// than flicking over from meters once the read lands.
  static DistanceUnit preferred = DistanceUnit.meters;

  /// Reads the remembered unit. Called at startup and again by every field
  /// as it opens; storage is allowed to fail, and meters is a fine place to
  /// land when it does.
  static Future<DistanceUnit> loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      preferred = DistanceUnit.values.asNameMap()[prefs.getString(_prefKey)] ??
          DistanceUnit.meters;
    } catch (_) {}
    return preferred;
  }

  static Future<void> _remember(DistanceUnit unit) async {
    preferred = unit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, unit.name);
    } catch (_) {
      // Not worth telling anyone about: the field still switched.
    }
  }

  @override
  State<DistanceField> createState() => _DistanceFieldState();
}

class _DistanceFieldState extends State<DistanceField> {
  late DistanceUnit _unit = widget.meters == null
      ? DistanceField.preferred
      : widget.unit ?? DistanceUnit.meters;
  late double? _value = widget.meters;

  final _meters = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _metersFocus = FocusNode();
  final _feetFocus = FocusNode();

  /// Whether the coach has typed or switched since it opened, after which
  /// a remembered unit arriving late must not move anything.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _fill(_value);
    if (widget.meters == null) {
      DistanceField.loadPreference().then((unit) {
        if (!mounted || _touched || unit == _unit) return;
        final hadFocus = _metersFocus.hasFocus || _feetFocus.hasFocus;
        setState(() => _unit = unit);
        if (hadFocus) _focusFirst();
      });
    }
  }

  @override
  void dispose() {
    _meters.dispose();
    _feet.dispose();
    _inches.dispose();
    _metersFocus.dispose();
    _feetFocus.dispose();
    super.dispose();
  }

  /// Writes [meters] into the boxes of the unit on screen. Setting a
  /// controller's text doesn't fire its onChanged, so nothing bounces.
  void _fill(double? meters) {
    if (meters == null) {
      _meters.text = _feet.text = _inches.text = '';
      return;
    }
    _meters.text = meters.toStringAsFixed(2);
    final (feet, inches) = feetAndInches(meters);
    _feet.text = '$feet';
    _inches.text = _inchesText(inches);
  }

  static String _inchesText(double inches) => inches == inches.roundToDouble()
      ? inches.toStringAsFixed(0)
      : inches.toStringAsFixed(2);

  void _focusFirst() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_unit == DistanceUnit.feet ? _feetFocus : _metersFocus)
            .requestFocus();
      });

  void _typedMeters(String text) {
    _touched = true;
    setState(() => _value = parseDistanceValue(text));
    widget.onChanged(_value, DistanceUnit.meters);
  }

  void _typedFeet(String _) {
    _touched = true;
    setState(() => _value = _readFeet());
    widget.onChanged(_value, DistanceUnit.feet);
  }

  /// The two feet boxes as one mark. The feet box on its own may hold the
  /// whole of it ('191-08'); with inches beside it, it has to be whole feet.
  double? _readFeet() {
    final feetText = _feet.text.trim();
    final inchesText = _inches.text.trim();
    if (inchesText.isEmpty) {
      final feet = parseFeet(feetText);
      return feet == null ? null : feet * metersPerFoot;
    }
    final inches = parseDistanceValue(inchesText);
    if (inches == null || inches >= 12) return null;
    final feet = feetText.isEmpty ? 0 : int.tryParse(feetText);
    if (feet == null || feet < 0) return null;
    return (feet + inches / 12) * metersPerFoot;
  }

  String? get _inchesError {
    final inches = parseDistanceValue(_inches.text);
    return inches != null && inches >= 12 ? 'Under 12' : null;
  }

  void _switchTo(DistanceUnit unit) {
    if (unit == _unit) return;
    _touched = true;
    setState(() {
      _unit = unit;
      _fill(_value);
    });
    DistanceField._remember(unit);
    widget.onChanged(_value, unit);
    _focusFirst();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feet = _unit == DistanceUnit.feet;
    final value = _value;
    // The mark in the other unit, for checking it against a sheet printed
    // in that one. Said as a meet says it, so feet are '191-08'.
    final converted = value == null
        ? null
        : feet
            ? formatDistance(value)
            : formatDistance(value, DistanceUnit.feet);
    const number = TextInputType.numberWithOptions(decimal: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (feet)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('feet'),
                  controller: _feet,
                  focusNode: _feetFocus,
                  autofocus: widget.autofocus,
                  keyboardType: number,
                  textInputAction: TextInputAction.next,
                  onChanged: _typedFeet,
                  decoration: const InputDecoration(
                    labelText: 'Feet',
                    hintText: '191',
                    suffixText: 'ft',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('inches'),
                  controller: _inches,
                  keyboardType: number,
                  onChanged: _typedFeet,
                  decoration: InputDecoration(
                    labelText: 'Inches',
                    hintText: '8',
                    suffixText: 'in',
                    errorText: _inchesError,
                  ),
                ),
              ),
            ],
          )
        else
          TextField(
            key: const ValueKey('meters'),
            controller: _meters,
            focusNode: _metersFocus,
            autofocus: widget.autofocus,
            keyboardType: number,
            onChanged: _typedMeters,
            decoration: const InputDecoration(
              labelText: 'Meters',
              hintText: '58.42',
              suffixText: 'm',
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Always there, and at the size of the number typed: both
            // units are read at a glance, and a readout that only appears
            // once something is typed is one nobody knows to look for.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feet ? 'In meters' : 'In feet',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    converted ?? '—',
                    key: const ValueKey('converted'),
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: converted == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            SegmentedButton<DistanceUnit>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                    value: DistanceUnit.meters,
                    label: Text('m'),
                    tooltip: 'Meters'),
                ButtonSegment(
                    value: DistanceUnit.feet,
                    label: Text('ft'),
                    tooltip: 'Feet and inches'),
              ],
              selected: {_unit},
              onSelectionChanged: (chosen) => _switchTo(chosen.single),
            ),
          ],
        ),
      ],
    );
  }
}
