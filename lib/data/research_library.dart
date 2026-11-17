import '../models/research.dart';

/// The research the coach's notebook ships with.
///
/// Empty for now, deliberately: the tab, the topics, the filters and the
/// page an entry opens on are all built, and entries go in here as they are
/// written against their sources. Every entry must carry real citations —
/// a DOI wherever the work has one — because the whole worth of this tab is
/// that a coach can follow any line in it back to where it came from.
///
/// An entry looks like this:
///
/// ```dart
/// ResearchEntry(
///   id: 'release-speed-dominates',
///   title: 'Release speed matters most',
///   topic: ResearchTopic.biomechanics,
///   events: {ThrowEvent.shotPut},
///   evidence: EvidenceLevel.strong,
///   summary: '…',
///   takeaways: ['…'],
///   tips: ['…'],
///   citations: [
///     Citation(
///       authors: '…',
///       year: 0,
///       title: '…',
///       source: '…',
///       doi: '…',
///     ),
///   ],
/// ),
/// ```
const List<ResearchEntry> researchLibrary = [];
