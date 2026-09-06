import 'package:flutter/material.dart';

import '../models/training_note.dart';

/// A text field that draws its own emphasis as you type.
///
/// The markers stay in the string — the cursor has to be able to sit next
/// to them, and the note has to survive being stored as text — but the
/// words between them are already bold, italic or underlined, and the
/// markers themselves are drawn faintly so they read as punctuation rather
/// than as syntax.
class NoteTextController extends TextEditingController {
  NoteTextController({super.text, required this.markerColor});

  final Color markerColor;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      style: style,
      // The spans concatenate back to exactly `text`, markers included, so
      // selection offsets still land where the user put them.
      children: inlineSpans(
        text,
        base: style,
        markerStyle: (style ?? const TextStyle())
            .copyWith(color: markerColor, fontWeight: FontWeight.w400),
      ),
    );
  }
}

/// A note's line, drawn rather than edited: markers gone, emphasis applied.
class NoteRichText extends StatelessWidget {
  const NoteRichText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(children: inlineSpans(text, base: base)),
      style: base,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
