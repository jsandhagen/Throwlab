/// The coach's notebook: the coach's own pages, about whatever they decide
/// is worth keeping — a drill progression, the cue that finally worked, a
/// throw to show the group, a link to a lecture — rather than about one
/// athlete the way a training note is.
///
/// A page is the same list of blocks a training note is, drawn by the same
/// editor, plus the blocks that point at things: a throw from the library,
/// an athlete, a meet, a web page or video. Pages are filed into sections the
/// coach names and orders, and a page can be pinned to the top.
library;

import 'training_note.dart';

/// A shelf in the notebook, named by the coach. Pages refer to it by [id],
/// so renaming a section moves nothing.
class NotebookSection {
  NotebookSection({required this.id, required this.name});

  final String id;
  String name;

  NotebookSection copy() => NotebookSection(id: id, name: name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory NotebookSection.fromJson(Map<String, dynamic> json) =>
      NotebookSection(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );
}

/// One page of the notebook.
class NotebookPage implements NoteDocument {
  NotebookPage({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title = '',
    this.sectionId,
    this.pinned = false,
    List<NoteBlock>? blocks,
  }) : blocks = blocks ?? [];

  @override
  final String id;

  final DateTime createdAt;
  DateTime updatedAt;

  @override
  String title;

  /// The section it is filed in; null for a page in no section, which is
  /// where a page goes when its section is deleted.
  String? sectionId;

  /// Pinned pages lead the list, whatever was edited since.
  bool pinned;

  @override
  List<NoteBlock> blocks;

  @override
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    for (final block in blocks) {
      if (block.isText && block.text.trim().isNotEmpty) {
        return stripMarkers(block.text.trim());
      }
    }
    return 'Untitled page';
  }

  /// The line under the title in a list: the next thing the page says, or
  /// holds.
  String get preview {
    var seenTitleLine = title.trim().isNotEmpty;
    for (final block in blocks) {
      if (block.isBlank || block.isDivider) continue;
      if (!seenTitleLine && block.isText) {
        seenTitleLine = true;
        continue;
      }
      final line = blockSummary(block);
      if (line.isNotEmpty) return line;
    }
    return '';
  }

  /// How many of each embedded thing the page holds — the icons a card in
  /// the list carries, so a page full of throws reads as one.
  Map<NoteBlockKind, int> get embedCounts {
    final counts = <NoteBlockKind, int>{};
    for (final block in blocks) {
      if (block.isEmbed || block.isImage) {
        counts[block.kind] = (counts[block.kind] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Whether [query] turns up anywhere on the page — its title, its words,
  /// its captions, or a link's address.
  bool matches(String query) {
    final wanted = query.trim().toLowerCase();
    if (wanted.isEmpty) return true;
    if (title.toLowerCase().contains(wanted)) return true;
    for (final block in blocks) {
      if (stripMarkers(block.text).toLowerCase().contains(wanted)) return true;
      if ((block.url ?? '').toLowerCase().contains(wanted)) return true;
      if (block.kind == NoteBlockKind.athlete &&
          (block.ref ?? '').toLowerCase().contains(wanted)) {
        return true;
      }
    }
    return false;
  }

  @override
  NotebookPage copy() => NotebookPage(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        title: title,
        sectionId: sectionId,
        pinned: pinned,
        blocks: [for (final block in blocks) block.copy()],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'title': title,
        'sectionId': sectionId,
        'pinned': pinned,
        'blocks': [for (final block in blocks) block.toJson()],
      };

  factory NotebookPage.fromJson(Map<String, dynamic> json) => NotebookPage(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.parse(json['createdAt'] as String),
        title: json['title'] as String? ?? '',
        sectionId: json['sectionId'] as String?,
        pinned: json['pinned'] as bool? ?? false,
        blocks: [
          for (final block in (json['blocks'] as List<dynamic>? ?? []))
            NoteBlock.fromJson(block as Map<String, dynamic>),
        ],
      );
}
