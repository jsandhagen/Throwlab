/// Training notes: what a coach actually writes down between sessions.
///
/// A note is a list of typed blocks rather than one blob of text, because
/// that is the shape coaching notes come in — a heading, a couple of cues,
/// a checklist for next week, a photo of a position with a line about what
/// is wrong with it. Blocks also mean the editor can act on one paragraph
/// without a rich-text document model behind it.
///
/// Emphasis inside a block is written with markers (`**bold**`, `*italic*`,
/// `__underline__`) that the editor's toolbar types for you. Keeping the
/// text a plain string is what lets a note survive JSON, a search, and
/// being read back by a future version that draws it differently — and the
/// editor styles it live, so nobody has to think in markers.
library;

import 'package:flutter/material.dart';

/// What a block is. The kind decides how it is drawn and what the editor
/// does when you press Enter in it.
///
/// The kinds after [image] are the coach's notebook's: a training note never
/// makes one, but a note is drawn by the same editor, so they are one enum.
/// New kinds go on the end — the stored name is what is read back, so the
/// order is free, but the end is where a reader looks for what came later.
enum NoteBlockKind {
  heading,
  paragraph,
  bullet,
  numbered,
  checklist,
  image,

  /// A boxed line that stands out from the page — the cue that matters.
  callout,

  /// A rule across the page. Holds no text.
  divider,

  /// A throw from the library, by [NoteBlock.ref] (its id).
  clip,

  /// An athlete, by [NoteBlock.ref] (their name, as throws are tagged).
  athlete,

  /// A meet, by [NoteBlock.ref] (its id).
  meet,

  /// A web page or video somewhere else, by [NoteBlock.url].
  link,
}

/// The kinds that point at something rather than holding words: drawn as a
/// card, with [NoteBlock.text] as the caption under it.
const embedKinds = {
  NoteBlockKind.clip,
  NoteBlockKind.athlete,
  NoteBlockKind.meet,
  NoteBlockKind.link,
};

class NoteBlock {
  NoteBlock({
    required this.id,
    this.kind = NoteBlockKind.paragraph,
    this.text = '',
    this.checked = false,
    this.imagePath,
    this.ref,
    this.url,
  });

  final String id;
  NoteBlockKind kind;

  /// The block's words — or, for an image, its caption.
  String text;

  /// Checklist blocks only; ignored by every other kind.
  bool checked;

  /// The picture, copied into the app's own storage so it survives the
  /// gallery being tidied up. Null for every kind but [NoteBlockKind.image].
  String? imagePath;

  /// What an embed points at inside the app — a throw's id, an athlete's
  /// name, a meet's id. Null for every kind that holds its own content.
  String? ref;

  /// Where a [NoteBlockKind.link] goes. Null for every other kind.
  String? url;

  bool get isImage => kind == NoteBlockKind.image;
  bool get isEmbed => embedKinds.contains(kind);
  bool get isDivider => kind == NoteBlockKind.divider;

  /// Whether the block is typed into directly, as a line of words. A
  /// picture or an embed is typed into too, but only as its caption.
  bool get isText => !isImage && !isEmbed && !isDivider;

  /// Whether this block holds nothing at all — an empty paragraph left
  /// behind, which the note's preview should skip over.
  bool get isBlank =>
      text.trim().isEmpty &&
      imagePath == null &&
      ref == null &&
      url == null &&
      !isDivider;

  NoteBlock copy() => NoteBlock(
        id: id,
        kind: kind,
        text: text,
        checked: checked,
        imagePath: imagePath,
        ref: ref,
        url: url,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'checked': checked,
        'imagePath': imagePath,
        if (ref != null) 'ref': ref,
        if (url != null) 'url': url,
      };

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
        id: json['id'] as String,
        // An unknown kind from a newer version reads as a paragraph rather
        // than taking the whole note down with it.
        kind: NoteBlockKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
            NoteBlockKind.paragraph,
        text: json['text'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        imagePath: json['imagePath'] as String?,
        ref: json['ref'] as String?,
        url: json['url'] as String?,
      );
}

/// What the note editor writes into: a title over a list of blocks. A
/// training note is one, and so is a page of the coach's notebook — the
/// same editor draws both, so a coach learns it once.
abstract class NoteDocument {
  String get id;
  String get title;
  set title(String value);
  List<NoteBlock> get blocks;
  String get displayTitle;
  NoteDocument copy();
}

/// A block as one plain line — for a list's preview line, where a picture
/// or an embed has no words of its own to show.
String blockSummary(NoteBlock block) {
  final caption = stripMarkers(block.text.trim());
  if (block.isText || caption.isNotEmpty) return caption;
  return switch (block.kind) {
    NoteBlockKind.image => 'Picture',
    NoteBlockKind.clip => 'A throw',
    NoteBlockKind.athlete => block.ref ?? 'An athlete',
    NoteBlockKind.meet => 'A meet',
    NoteBlockKind.link => block.url ?? 'A link',
    _ => '',
  };
}

/// One training note, belonging to one athlete.
class TrainingNote implements NoteDocument {
  TrainingNote({
    required this.id,
    required this.athlete,
    required this.createdAt,
    required this.updatedAt,
    this.title = '',
    List<NoteBlock>? blocks,
  }) : blocks = blocks ?? [];

  @override
  final String id;

  /// Who it is about. Matched the way athletes are matched everywhere else:
  /// case-insensitively, on the trimmed name.
  String athlete;

  final DateTime createdAt;
  DateTime updatedAt;

  @override
  String title;
  @override
  List<NoteBlock> blocks;

  /// What the note is called in a list. An untitled note is named by its
  /// first line, the way a notes app does, so it is still recognizable.
  @override
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    for (final block in blocks) {
      if (block.text.trim().isNotEmpty) return stripMarkers(block.text.trim());
    }
    return 'Untitled note';
  }

  /// The line under the title in a list: the next thing the note says.
  String get preview {
    var seenTitleLine = title.trim().isNotEmpty;
    for (final block in blocks) {
      if (block.isBlank) continue;
      if (!seenTitleLine) {
        seenTitleLine = true;
        continue;
      }
      if (block.isImage) {
        return block.text.trim().isEmpty
            ? 'Picture'
            : stripMarkers(block.text.trim());
      }
      return stripMarkers(block.text.trim());
    }
    return '';
  }

  int get pictureCount => blocks.where((block) => block.isImage).length;

  /// Every checklist item, and how many are ticked — the one summary worth
  /// having, since a note's checklist is a plan for the next session.
  ({int done, int total}) get checklist {
    var done = 0;
    var total = 0;
    for (final block in blocks) {
      if (block.kind != NoteBlockKind.checklist) continue;
      total++;
      if (block.checked) done++;
    }
    return (done: done, total: total);
  }

  @override
  TrainingNote copy() => TrainingNote(
        id: id,
        athlete: athlete,
        createdAt: createdAt,
        updatedAt: updatedAt,
        title: title,
        blocks: [for (final block in blocks) block.copy()],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'athlete': athlete,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'title': title,
        'blocks': [for (final block in blocks) block.toJson()],
      };

  factory TrainingNote.fromJson(Map<String, dynamic> json) => TrainingNote(
        id: json['id'] as String,
        athlete: json['athlete'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.parse(json['createdAt'] as String),
        title: json['title'] as String? ?? '',
        blocks: [
          for (final block in (json['blocks'] as List<dynamic>? ?? []))
            NoteBlock.fromJson(block as Map<String, dynamic>),
        ],
      );
}

/// The emphasis markers, longest first — order matters to the scanner,
/// which would otherwise read the first `*` of `**` as an italic toggle.
const _markers = ['**', '__', '*'];

/// One run of text and the emphasis in force over it.
class InlineRun {
  const InlineRun(this.text,
      {this.bold = false, this.italic = false, this.underline = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// True for the markers themselves, which the editor draws faintly so
  /// they stay out of the way of the words.
  bool get isMarker => _markers.contains(text);
}

/// Splits [text] into runs, toggling emphasis at each marker.
///
/// A toggle scanner rather than a matched-pairs parser: nesting falls out
/// of it for free, and an unclosed marker styles the rest of the line
/// instead of failing to render — which is what you want while someone is
/// halfway through typing one.
List<InlineRun> inlineRuns(String text, {bool keepMarkers = false}) {
  final runs = <InlineRun>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;
  var underline = false;

  void flush() {
    if (buffer.isEmpty) return;
    runs.add(InlineRun(buffer.toString(),
        bold: bold, italic: italic, underline: underline));
    buffer.clear();
  }

  for (var i = 0; i < text.length;) {
    final marker =
        _markers.firstWhere((m) => text.startsWith(m, i), orElse: () => '');
    if (marker.isEmpty) {
      buffer.write(text[i]);
      i++;
      continue;
    }
    flush();
    if (keepMarkers) {
      runs.add(
          InlineRun(marker, bold: bold, italic: italic, underline: underline));
    }
    switch (marker) {
      case '**':
        bold = !bold;
      case '__':
        underline = !underline;
      default:
        italic = !italic;
    }
    i += marker.length;
  }
  flush();
  return runs;
}

/// The text with its markers removed — for previews, and anywhere a note is
/// shown as one plain line.
String stripMarkers(String text) =>
    [for (final run in inlineRuns(text)) run.text].join();

/// [text] as styled spans on top of [base].
///
/// [markerStyle] draws the markers themselves; pass it in the editor, where
/// they have to stay in the string for the cursor to make sense, and leave
/// it null everywhere the note is only being read.
List<InlineSpan> inlineSpans(
  String text, {
  TextStyle? base,
  TextStyle? markerStyle,
}) =>
    [
      for (final run in inlineRuns(text, keepMarkers: markerStyle != null))
        TextSpan(
          text: run.text,
          style: run.isMarker
              ? markerStyle
              : (base ?? const TextStyle()).copyWith(
                  fontWeight: run.bold ? FontWeight.w700 : null,
                  fontStyle: run.italic ? FontStyle.italic : null,
                  decoration: run.underline ? TextDecoration.underline : null,
                ),
        ),
    ];
