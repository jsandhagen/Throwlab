import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The page something is handed over on: paste it, or open the PDF it came
/// in.
///
/// Shared by the two imports — a season off a fixture list and a field off
/// a heat sheet — because they take the same two things in the same two
/// ways, and a coach should not have to learn it twice.
class ImportSource extends StatelessWidget {
  const ImportSource({
    super.key,
    required this.controller,
    required this.blurb,
    required this.hint,
    required this.onRead,
    required this.onOpenPdf,
    this.busy = false,
    this.problem,
  });

  final TextEditingController controller;

  /// What kind of page this is expecting, in a sentence.
  final String blurb;

  /// A couple of lines of one, shown in the empty field.
  final String hint;

  final VoidCallback onRead;
  final VoidCallback onOpenPdf;
  final bool busy;

  /// What went wrong with the last thing handed over, in words a coach can
  /// act on. Kept on the page rather than flashed in a snack bar: it is the
  /// answer to "why is nothing happening", and it has to still be there
  /// when they look.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              blurb,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: hint,
                ),
              ),
            ),
            if (problem != null) ...[
              const SizedBox(height: 12),
              ImportProblem(problem!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onOpenPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Open a PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onRead,
                    icon: const Icon(Icons.search),
                    label: const Text('Read it'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Why the last thing handed over came to nothing.
class ImportProblem extends StatelessWidget {
  const ImportProblem(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_outlined,
              size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

/// Picks a PDF and hands back its bytes, or null if nobody picked one.
typedef PdfReader = Future<Uint8List?> Function();
