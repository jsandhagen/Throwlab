/// The research half of the coach's notebook: what the literature says
/// about coaching the throws, written for a coach to act on.
///
/// Each entry is one finding a coach can use, not a paper: what was found,
/// what to do with it on the field, and the published work it stands on.
/// Entries are shipped with the app rather than written by the coach, and
/// every one carries its sources, so nothing here is a claim the coach
/// cannot follow back to where it came from.
library;

import 'throw_event.dart';

/// What an entry is about, which is how the research tab is browsed.
enum ResearchTopic {
  technique('Technique', 'Positions, sequencing and the release'),
  strength('Strength & power', 'Lifting, jumping and transfer to the throw'),
  training('Training design', 'Periodization, volume and the season'),
  implementWeight('Implements', 'Heavy, light and overweight throwing'),
  biomechanics('Biomechanics', 'Release speed, angle and height'),
  coaching('Coaching & cues', 'Feedback, attention and motor learning'),
  recovery('Recovery & injury', 'Load, soreness and staying healthy'),
  competition('Competition', 'Warm-up, attempts and the day itself');

  const ResearchTopic(this.label, this.blurb);

  final String label;
  final String blurb;
}

/// How firmly an entry's sources back it — said plainly, so a coach can
/// tell a settled finding from one interesting study.
enum EvidenceLevel {
  /// Several studies, or a review of them, agree.
  strong('Well supported'),

  /// A study or two, or experts agreeing on what the data suggest.
  moderate('Some support'),

  /// Early, small, or mostly the practice of good coaches.
  emerging('Emerging');

  const EvidenceLevel(this.label);

  final String label;
}

/// One published source behind an entry.
class Citation {
  const Citation({
    required this.authors,
    required this.year,
    required this.title,
    this.source,
    this.doi,
    this.url,
  });

  /// As cited: "Bartlett, R. M." or "Linthorne, N. P., & Weetman, G.".
  final String authors;
  final int year;
  final String title;

  /// Where it was published — a journal, a book, a federation's journal.
  final String? source;
  final String? doi;
  final String? url;

  /// Where to read it: the DOI's resolver when there is one.
  String? get link => doi != null ? 'https://doi.org/$doi' : url;

  /// The line it is listed as, in a short author–date form.
  String get reference {
    final out = StringBuffer('$authors ($year). $title.');
    if (source != null) out.write(' $source.');
    return out.toString();
  }
}

/// One finding, and what a coach does with it.
class ResearchEntry {
  const ResearchEntry({
    required this.id,
    required this.title,
    required this.topic,
    required this.summary,
    required this.takeaways,
    required this.tips,
    required this.citations,
    this.events = const {},
    this.evidence = EvidenceLevel.moderate,
  });

  final String id;
  final String title;
  final ResearchTopic topic;

  /// The events it applies to; empty for an entry about the throws as a
  /// whole.
  final Set<ThrowEvent> events;

  /// What the research found, in a short paragraph.
  final String summary;

  /// The findings, one line each.
  final List<String> takeaways;

  /// What to do with them at practice.
  final List<String> tips;

  final List<Citation> citations;
  final EvidenceLevel evidence;

  bool appliesTo(ThrowEvent? event) =>
      event == null || events.isEmpty || events.contains(event);

  bool matches(String query) {
    final wanted = query.trim().toLowerCase();
    if (wanted.isEmpty) return true;
    return [
      title,
      summary,
      ...takeaways,
      ...tips,
      for (final citation in citations) citation.reference,
    ].any((text) => text.toLowerCase().contains(wanted));
  }
}
