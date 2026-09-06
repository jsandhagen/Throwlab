import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/app_updater.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
import '../utils/time_format.dart';
import '../widgets/throw_motifs.dart';
import 'analysis_screen.dart';
import 'comparison_screen.dart';

enum LibraryGrouping { athlete, event, date }

/// The app's angular silhouette: two opposite corners cut, the other two
/// left square. Shared by the search field, the grouping bar, the cards and
/// the section tiles so the screen reads as one shape language.
ShapeBorder angularShape(double cut, {BorderSide side = BorderSide.none}) =>
    BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(cut),
        bottomRight: Radius.circular(cut),
      ),
    );

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _availableBuild;
  LibraryGrouping _grouping = LibraryGrouping.athlete;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  /// Groups the user opened into the full-width list; the rest stay as
  /// horizontal shelves.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    AppUpdater.checkForUpdate().then((build) {
      if (mounted && build != null) {
        setState(() => _availableBuild = build);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _installUpdate() async {
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Downloading update'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) =>
              LinearProgressIndicator(value: value),
        ),
      ),
    );
    try {
      await AppUpdater.downloadAndInstall((p) => progress.value = p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _importVideo() async {
    final library = context.read<VideoLibrary>();
    final picked =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final details = await showDialog<
        ({ThrowEvent event, Gender gender, String athlete})>(
      context: context,
      builder: (context) => const _ImportDialog(),
    );
    if (details == null || !mounted) return;

    // Re-encode for instant frame seeks; this is the slow part of importing.
    final encodeProgress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Optimizing video'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<double?>(
              valueListenable: encodeProgress,
              builder: (context, value, _) =>
                  LinearProgressIndicator(value: value),
            ),
            const SizedBox(height: 16),
            const Text('Re-encoding for instant frame-by-frame '
                'scrubbing. Long or high-fps clips take a few minutes.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: VideoOptimizer.cancel,
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    // Probe the original file: the re-encode preserves frame timing but
    // drops the slow-mo capture-fps metadata tag.
    final rates = await VideoOptimizer.probeFrameRates(picked.path);
    final path = await VideoOptimizer.optimizeForScrubbing(
      picked.path,
      id,
      onProgress: (p) => encodeProgress.value = p,
    );
    final thumbnail = await VideoOptimizer.extractThumbnail(path, id);
    if (mounted) Navigator.pop(context);

    final video = ThrowVideo(
      id: id,
      path: path,
      event: details.event,
      gender: details.gender,
      importedAt: DateTime.now(),
      recordedAt: rates?.recordedAt,
      fps: rates?.playback ?? 30,
      captureFps: rates?.capture,
      athlete: details.athlete,
      thumbnailPath: thumbnail,
    );
    await library.add(video);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnalysisScreen(video: video)),
      );
    }
  }

  Future<void> _startComparison() async {
    final library = context.read<VideoLibrary>();
    final videos = library.videos;
    if (videos.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Import at least two throws to compare.')));
      return;
    }
    final selection = await showDialog<List<ThrowVideo>>(
      context: context,
      builder: (context) => _ComparePickerDialog(videos: videos),
    );
    if (selection != null && selection.length == 2 && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComparisonScreen(
              videoA: selection[0], videoB: selection[1]),
        ),
      );
    }
  }

  /// Throws matching the search box: athlete, event, gender, or note.
  List<ThrowVideo> _filtered(List<ThrowVideo> videos) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return videos;
    return [
      for (final video in videos)
        if ('${video.athlete} ${video.event.label} ${video.gender.label} '
                '${video.note}'
            .toLowerCase()
            .contains(query))
          video,
    ];
  }

  /// Groups by the active dimension, newest group first, and sorts each
  /// group's throws newest first.
  Map<String, List<ThrowVideo>> _grouped(List<ThrowVideo> videos) {
    final map = <String, List<ThrowVideo>>{};
    for (final video in videos) {
      final key = switch (_grouping) {
        LibraryGrouping.athlete => _athleteName(video),
        LibraryGrouping.event => video.event.label,
        LibraryGrouping.date =>
          formatShortDate(video.displayDate.toLocal()),
      };
      map.putIfAbsent(key, () => []).add(video);
    }
    for (final group in map.values) {
      group.sort((a, b) => b.displayDate.compareTo(a.displayDate));
    }
    final keys = map.keys.toList()
      ..sort((a, b) => map[b]!.first.displayDate
          .compareTo(map[a]!.first.displayDate));
    return {for (final k in keys) k: map[k]!};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon/logo.png', height: 32),
            const SizedBox(width: 10),
            const Text('ThrowLab',
                style: TextStyle(
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Compare two throws',
            icon: const Icon(Icons.compare),
            onPressed: _startComparison,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_availableBuild != null)
              MaterialBanner(
                leading: const Icon(Icons.system_update),
                content: const Text('A new version of ThrowLab is ready.'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _availableBuild = null),
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    onPressed: _installUpdate,
                    child: const Text('Update'),
                  ),
                ],
              ),
            Expanded(
              child: Consumer<VideoLibrary>(
                builder: (context, library, _) {
                  if (!library.isLoaded) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final content = library.videos.isEmpty
                      ? const _EmptyState()
                      : _library(library);
                  if (library.storageError == null) return content;
                  return Column(
                    children: [
                      _StorageErrorBanner(error: library.storageError!),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        shape: angularShape(16),
        icon: const Icon(Icons.video_library),
        label: const Text('Import throw'),
        onPressed: _importVideo,
      ),
    );
  }

  Widget _library(VideoLibrary library) {
    final filtered = _filtered(library.videos);
    final groups = _grouped(filtered);
    return Stack(
      children: [
        // The sector, sweeping across behind the whole library.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SectorBackdropPainter(
                  color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        Column(
      children: [
        // The count follows the search, so it always describes what's shown.
        _header(filtered.length),
        Expanded(
          child: groups.isEmpty
              ? _NoMatches(query: _query.trim())
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 120),
                  children: [
                    for (final entry in groups.entries)
                      _section(entry.key, entry.value),
                  ],
                ),
        ),
      ],
        ),
      ],
    );
  }

  /// Search field over the grouping bar — one quiet block above the shelves.
  Widget _header(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchField(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _GroupingBar(
                  value: _grouping,
                  onChanged: _setGrouping,
                ),
              ),
              // Only worth the width while a search is narrowing things down.
              if (_query.trim().isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  '$count throw${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant.withOpacity(0.7)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _setGrouping(LibraryGrouping grouping) {
    if (grouping == _grouping) return;
    setState(() {
      _grouping = grouping;
      _expanded.clear();
    });
  }

  Widget _searchField() {
    final scheme = Theme.of(context).colorScheme;
    final focused = _searchFocus.hasFocus;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: angularShape(
          14,
          side: BorderSide(
            color: focused
                ? scheme.primary.withOpacity(0.7)
                : scheme.outlineVariant.withOpacity(0.35),
            width: focused ? 1.4 : 1,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withOpacity(0.42),
            scheme.surfaceContainerHighest.withOpacity(0.14),
          ],
        ),
      ),
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 15),
        cursorColor: scheme.primary,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search throws',
          hintStyle: TextStyle(
              fontSize: 15, color: scheme.onSurfaceVariant.withOpacity(0.7)),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: scheme.onSurfaceVariant.withOpacity(0.8)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  iconSize: 18,
                  splashRadius: 18,
                  icon: const Icon(Icons.close_rounded),
                  color: scheme.onSurfaceVariant,
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: const EdgeInsets.fromLTRB(0, 13, 12, 13),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _section(String key, List<ThrowVideo> videos) {
    final theme = Theme.of(context);
    final accent = switch (_grouping) {
      LibraryGrouping.athlete => _athleteColor(key),
      LibraryGrouping.event => _eventColor(videos.first.event),
      LibraryGrouping.date => theme.colorScheme.primary,
    };
    final expanded = _expanded.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (!_expanded.remove(key)) _expanded.add(key);
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
            child: Row(
              children: [
                _sectionTile(key, videos, accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, letterSpacing: 0.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sectionSubtitle(videos),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final video in videos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _card(video),
                    ),
                  ),
              ],
            ),
          )
        else
          SizedBox(
            // Roughly 16:9 so a frame keeps its shape, wide enough that the
            // next card peeks in and the shelf reads as scrollable.
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: videos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  SizedBox(width: 288, child: _card(videos[index])),
            ),
          ),
      ],
    );
  }

  /// The date is already the title when grouping by date, so name the
  /// athletes there instead of repeating it.
  String _sectionSubtitle(List<ThrowVideo> videos) {
    final count = '${videos.length} throw${videos.length == 1 ? '' : 's'}';
    if (_grouping != LibraryGrouping.date) {
      return '$count · ${formatShortDate(videos.first.displayDate.toLocal())}';
    }
    final names = {for (final video in videos) _athleteName(video)}.toList();
    final shown = names.length > 2
        ? '${names.take(2).join(', ')} +${names.length - 2}'
        : names.join(', ');
    final weekday = weekdayName(videos.first.displayDate.toLocal());
    return '$weekday · $count · $shown';
  }

  Widget _sectionTile(String key, List<ThrowVideo> videos, Color accent) {
    final date = videos.first.displayDate.toLocal();
    final content = switch (_grouping) {
      LibraryGrouping.athlete => Text(
          _initials(key),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      LibraryGrouping.event =>
        Icon(videos.first.event.icon, color: Colors.white, size: 22),
      LibraryGrouping.date => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${date.day}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.05,
                    fontWeight: FontWeight.w700)),
            Text(monthAbbreviation(date).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 8.5,
                    height: 1.2,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600)),
          ],
        ),
    };
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: angularShape(13,
            side: BorderSide(color: accent.withOpacity(0.55))),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.85), accent.withOpacity(0.28)],
        ),
      ),
      child: content,
    );
  }

  Widget _card(ThrowVideo video) {
    // Say what the shelf it sits in doesn't already say.
    final title = switch (_grouping) {
      LibraryGrouping.athlete =>
        '${video.event.label} · ${video.gender.label}',
      LibraryGrouping.event =>
        '${_athleteName(video)} · ${video.gender.label}',
      LibraryGrouping.date => '${_athleteName(video)} · ${video.event.label}',
    };
    return _ThrowCard(
      video: video,
      title: title,
      accent: _eventColor(video.event),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnalysisScreen(video: video)),
      ),
      onAction: (action) => _cardAction(action, video),
    );
  }

  Future<void> _cardAction(String action, ThrowVideo video) async {
    final library = context.read<VideoLibrary>();
    if (action == 'note') {
      final note = await _editText(context, 'Note', video.note,
          'e.g. "PB attempt, slight headwind"');
      if (note != null) {
        video.note = note;
        await library.update(video);
      }
    } else if (action == 'athlete') {
      final name =
          await _editText(context, 'Athlete', video.athlete, 'e.g. "Sam"');
      if (name != null) {
        video.athlete = name.trim();
        await library.update(video);
      }
    } else if (action == 'delete') {
      await library.remove(video.id);
    }
  }

  Color _eventColor(ThrowEvent event) => switch (event) {
        ThrowEvent.shotPut => Colors.orangeAccent,
        ThrowEvent.discus => Colors.greenAccent,
        ThrowEvent.hammer => Colors.purpleAccent,
        ThrowEvent.javelin => Colors.lightBlueAccent,
      };

  String _athleteName(ThrowVideo video) =>
      video.athlete.isEmpty ? 'Unassigned' : video.athlete;

  /// A stable per-athlete accent so the same name keeps the same color.
  Color _athleteColor(String name) {
    const palette = [
      Color(0xFF4FC3F7),
      Color(0xFF4DB6AC),
      Color(0xFFFFB74D),
      Color(0xFFBA68C8),
      Color(0xFF81C784),
      Color(0xFFF06292),
    ];
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return '${words.first[0]}${words[1][0]}'.toUpperCase();
  }

  Future<String?> _editText(BuildContext context, String title,
      String current, String hint) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
  }
}

/// The three ways to slice the library, as one connected bar: a slanted
/// block slides under the active section and the dividers lean with it.
class _GroupingBar extends StatelessWidget {
  const _GroupingBar({required this.value, required this.onChanged});

  final LibraryGrouping value;
  final ValueChanged<LibraryGrouping> onChanged;

  static const _segments = [
    (LibraryGrouping.athlete, Icons.person_outline, 'Athlete'),
    (LibraryGrouping.event, Icons.sports_score_outlined, 'Event'),
    (LibraryGrouping.date, Icons.event_outlined, 'Date'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index =
        _segments.indexWhere((segment) => segment.$1 == value).toDouble();
    return SizedBox(
      height: 44,
      child: TweenAnimationBuilder<double>(
        // Only `end` matters after the first build: changing it slides the
        // block from wherever it is to the segment just tapped.
        tween: Tween<double>(begin: index, end: index),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, position, child) => CustomPaint(
          painter: _GroupingBarPainter(
            position: position,
            count: _segments.length,
            surface: scheme.surfaceContainerHighest,
            accent: scheme.primary,
            outline: scheme.outlineVariant,
          ),
          child: child,
        ),
        child: Row(
          children: [
            for (final (grouping, icon, label) in _segments)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(grouping),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 15,
                          color: grouping == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 0.2,
                          color: grouping == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: grouping == value
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupingBarPainter extends CustomPainter {
  const _GroupingBarPainter({
    required this.position,
    required this.count,
    required this.surface,
    required this.accent,
    required this.outline,
  });

  /// Which segment the block sits on; fractional while it slides.
  final double position;
  final int count;
  final Color surface;
  final Color accent;
  final Color outline;

  static const double _cut = 12;

  /// The slanted edges lean at the sector's half-angle — the same 17.46°
  /// the legal sector opens from the circle.
  double _lean(Size size) => size.height / 2 * sectorLean;

  /// Same two-corner cut as [angularShape], drawn by hand so the fill,
  /// the block and the dividers can all be clipped to it.
  Path _silhouette(Size size) => Path()
    ..moveTo(_cut, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - _cut)
    ..lineTo(size.width - _cut, size.height)
    ..lineTo(0, size.height)
    ..lineTo(0, _cut)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bar = _silhouette(size);

    canvas.save();
    canvas.clipPath(bar);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface.withOpacity(0.42), surface.withOpacity(0.14)],
        ).createShader(rect),
    );

    final lean = _lean(size);
    final segment = size.width / count;
    final left = position * segment;
    // A parallelogram, leaning right, one segment wide.
    final block = Path()
      ..moveTo(left + lean, 0)
      ..lineTo(left + segment + lean, 0)
      ..lineTo(left + segment - lean, size.height)
      ..lineTo(left - lean, size.height)
      ..close();
    canvas.drawPath(
      block,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.34), accent.withOpacity(0.10)],
        ).createShader(block.getBounds()),
    );
    canvas.drawPath(
      block,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withOpacity(0.45),
    );
    // Bright underline along the block's slanted foot.
    canvas.drawLine(
      Offset(left - lean, size.height - 1),
      Offset(left + segment - lean, size.height - 1),
      Paint()
        ..strokeWidth = 2
        ..color = accent.withOpacity(0.85),
    );

    for (var i = 1; i < count; i++) {
      final x = i * segment;
      // Fade a divider out as the block slides up against it.
      final gap = [(x - left).abs(), (x - left - segment).abs()]
              .reduce((a, b) => a < b ? a : b) /
          segment;
      final opacity = 0.16 + gap.clamp(0.0, 1.0) * 0.4;
      final top = Offset(x + lean, 8);
      final bottom = Offset(x - lean, size.height - 8);
      canvas.drawLine(
        top,
        bottom,
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              outline.withOpacity(0),
              outline.withOpacity(opacity),
              outline.withOpacity(0),
            ],
          ).createShader(Rect.fromPoints(top, bottom)),
      );
    }
    canvas.restore();

    canvas.drawPath(
      bar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(_GroupingBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.surface != surface ||
      old.accent != accent ||
      old.outline != outline;
}

/// A large thumbnail with the throw's details laid over the bottom of the
/// frame, the way a video library reads best.
class _ThrowCard extends StatelessWidget {
  const _ThrowCard({
    required this.video,
    required this.title,
    required this.accent,
    required this.onTap,
    required this.onAction,
  });

  final ThrowVideo video;
  final String title;
  final Color accent;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      formatShortDate(video.displayDate.toLocal()),
      if (video.note.isNotEmpty) video.note,
    ].join(' · ');
    final slowMo = video.captureFps > video.fps + 1;

    return Material(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: angularShape(18),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _thumbnail(),
            // Scrims: keep the overlaid text and controls readable whatever
            // the frame is — bright sky at the top, grass or runway below.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.3],
                  colors: [Color(0x73000000), Colors.transparent],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            // A wash of the event's color across the cut corner — texture,
            // and a second read on which event this is.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  stops: const [0, 0.55],
                  colors: [accent.withOpacity(0.26), Colors.transparent],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (slowMo)
              Positioned(
                left: 12,
                top: 12,
                child: _Badge(
                    label: '${video.captureFps.round()} fps',
                    icon: Icons.slow_motion_video),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: PopupMenuButton<String>(
                tooltip: 'Throw options',
                icon: const Icon(Icons.more_vert,
                    color: Colors.white, shadows: [
                  Shadow(color: Colors.black54, blurRadius: 6),
                ]),
                onSelected: onAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'athlete', child: Text('Set athlete')),
                  PopupMenuItem(value: 'note', child: Text('Edit note')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x59000000),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final path = video.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    // No still frame (older imports, or extraction failed): fall back to an
    // event-tinted panel so the shelf keeps its rhythm.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.35), accent.withOpacity(0.08)],
        ),
      ),
      child: Center(
        child: Icon(video.event.icon,
            size: 44, color: Colors.white.withOpacity(0.7)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x8A000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No throws match "$query"',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Search by athlete, event, gender, or note text.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageErrorBanner extends StatelessWidget {
  const _StorageErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Storage unavailable — the library won\'t survive a '
                'restart. ($error)',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // The sector the throws will land in, opening down the screen.
        Positioned.fill(
          child: CustomPaint(
            painter: SectorPainter(color: scheme.primary, opacity: 0.75),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/icon/logo.png', width: 140),
                const SizedBox(height: 16),
                Text('No throws yet',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Film side-on: tripod at 90° to the throwing direction, '
                  'perpendicular to the flight path. Then import the clip '
                  'here for slow-motion breakdown, drawing, and comparison.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  ThrowEvent _event = ThrowEvent.shotPut;
  Gender _gender = Gender.men;
  final TextEditingController _athlete = TextEditingController();

  @override
  void dispose() {
    _athlete.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _event.specFor(_gender);
    return AlertDialog(
      title: const Text('Throw details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _athlete,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Athlete',
              hintText: 'Who threw it (optional)',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThrowEvent>(
            value: _event,
            decoration: const InputDecoration(labelText: 'Event'),
            items: [
              for (final event in ThrowEvent.values)
                DropdownMenuItem(value: event, child: Text(event.label)),
            ],
            onChanged: (event) =>
                setState(() => _event = event ?? _event),
          ),
          const SizedBox(height: 12),
          SegmentedButton<Gender>(
            segments: [
              for (final gender in Gender.values)
                ButtonSegment(value: gender, label: Text(gender.label)),
            ],
            selected: {_gender},
            onSelectionChanged: (selection) =>
                setState(() => _gender = selection.first),
          ),
          const SizedBox(height: 12),
          Text(
            'Calibration: ${spec.referenceLabel.toLowerCase()} '
            '${spec.minSize >= 1 ? '${spec.minSize}–${spec.maxSize} m' : '${(spec.minSize * 1000).round()}–${(spec.maxSize * 1000).round()} mm'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, (
            event: _event,
            gender: _gender,
            athlete: _athlete.text.trim(),
          )),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _ComparePickerDialog extends StatefulWidget {
  const _ComparePickerDialog({required this.videos});

  final List<ThrowVideo> videos;

  @override
  State<_ComparePickerDialog> createState() => _ComparePickerDialogState();
}

class _ComparePickerDialogState extends State<_ComparePickerDialog> {
  final List<ThrowVideo> _selected = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick two throws'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final video in widget.videos)
              CheckboxListTile(
                value: _selected.contains(video),
                title: Text(
                    '${video.athlete.isEmpty ? '' : '${video.athlete} · '}'
                    '${video.event.label} · ${video.gender.label}'),
                subtitle: Text(video.importedAt
                    .toLocal()
                    .toString()
                    .substring(0, 16)),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    if (_selected.length < 2) _selected.add(video);
                  } else {
                    _selected.remove(video);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _selected.length == 2
              ? () => Navigator.pop(context, _selected)
              : null,
          child: const Text('Compare'),
        ),
      ],
    );
  }
}
