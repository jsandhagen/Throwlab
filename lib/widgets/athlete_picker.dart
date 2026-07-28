import 'package:flutter/material.dart';

/// Picks who threw it: tap a name already in the library, or type a new one.
/// Names accumulate as throws are imported, so after the first clip for an
/// athlete their name is a single tap rather than something to retype.
///
/// The tapped chip and the text field are the same value — typing a name
/// that matches an existing athlete highlights their chip, and tapping the
/// highlighted chip clears the field.
class AthletePicker extends StatefulWidget {
  const AthletePicker({
    super.key,
    required this.known,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  /// Athletes already in the library, most recent first.
  final List<String> known;

  final String value;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<AthletePicker> createState() => _AthletePickerState();
}

class _AthletePickerState extends State<AthletePicker> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isSelected(String name) =>
      name.toLowerCase() == widget.value.trim().toLowerCase();

  void _select(String name) {
    // Tapping the highlighted name clears it, so a clip can be left
    // unassigned without reaching for the keyboard to delete the text.
    final next = _isSelected(name) ? '' : name;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Athlete',
            hintText: widget.known.isEmpty
                ? 'Who threw it (optional)'
                : 'Tap a name below, or type a new one',
          ),
          onChanged: (text) {
            // Rebuild so a typed name lights up its chip.
            setState(() {});
            widget.onChanged(text);
          },
        ),
        if (widget.known.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Bounded so a long roster scrolls instead of pushing the dialog's
          // buttons off screen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in widget.known)
                    FilterChip(
                      label: Text(name),
                      selected: _isSelected(name),
                      onSelected: (_) => _select(name),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
