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
import 'analysis_screen.dart';
import 'comparison_screen.dart';

enum LibraryGrouping { athlete, event }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _availableBuild;
  LibraryGrouping _grouping = LibraryGrouping.athlete;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Groups the user opened into the full-width list; the rest stay as
  /// horizontal shelves.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    AppUpdater.checkForUpdate().then((build) {
      if (mounted && build != null) {
        setState(() => _availableBuild = build);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
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
      final key = _grouping == LibraryGrouping.athlete
          ? (video.athlete.isEmpty ? 'Unassigned' : video.athlete)
          : video.event.label;
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
        icon: const Icon(Icons.video_library),
        label: const Text('Import throw'),
        onPressed: _importVideo,
      ),
    );
  }

  Widget _library(VideoLibrary library) {
    final filtered = _filtered(library.videos);
    final groups = _grouped(filtered);
    return Column(
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
    );
  }

  /// Search field and grouping chips — one quiet block above the shelves.
  Widget _header(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchField(),
          const SizedBox(height: 12),
          Row(
            children: [
              _GroupChip(
                icon: Icons.person_outline,
                label: 'By athlete',
                selected: _grouping == LibraryGrouping.athlete,
                onTap: () => _setGrouping(LibraryGrouping.athlete),
              ),
              const SizedBox(width: 8),
              _GroupChip(
                icon: Icons.sports_score_outlined,
                label: 'By event',
                selected: _grouping == LibraryGrouping.event,
                onTap: () => _setGrouping(LibraryGrouping.event),
              ),
              const Spacer(),
              Text(
                '$count throw${count == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7)),
              ),
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
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _query = value),
      style: const TextStyle(fontSize: 15),
      cursorColor: scheme.primary,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(0.35),
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
        border: border(Colors.transparent, 0),
        enabledBorder: border(scheme.outlineVariant.withOpacity(0.35), 1),
        focusedBorder: border(scheme.primary.withOpacity(0.7), 1.4),
      ),
    );
  }

  Widget _section(String key, List<ThrowVideo> videos) {
    final theme = Theme.of(context);
    final byAthlete = _grouping == LibraryGrouping.athlete;
    final accent = byAthlete
        ? _athleteColor(key)
        : _eventColor(videos.first.event);
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
                _sectionAvatar(key, videos.first, accent),
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
                        '${videos.length} throw'
                        '${videos.length == 1 ? '' : 's'} · '
                        '${formatShortDate(videos.first.displayDate.toLocal())}',
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

  Widget _sectionAvatar(String key, ThrowVideo first, Color accent) {
    if (_grouping == LibraryGrouping.event) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(first.event.icon, color: accent, size: 22),
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.9), accent.withOpacity(0.55)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(key),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _card(ThrowVideo video) {
    final byAthlete = _grouping == LibraryGrouping.athlete;
    final title = byAthlete
        ? '${video.event.label} · ${video.gender.label}'
        : '${video.athlete.isEmpty ? 'Unassigned' : video.athlete}'
            ' · ${video.gender.label}';
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

/// One of the two library grouping choices. A filled tint reads as the
/// active one without the weight of a bordered segmented control.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? scheme.primary.withOpacity(0.45)
                  : scheme.outlineVariant.withOpacity(0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      borderRadius: BorderRadius.circular(20),
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
    return Center(
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
              'perpendicular to the flight path. Then import the clip here '
              'for slow-motion breakdown, drawing, and comparison.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
