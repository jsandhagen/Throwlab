import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/app_updater.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
import '../widgets/athlete_picker.dart';
import '../widgets/event_glyph.dart';
import '../widgets/throw_actions.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';
import 'comparison_screen.dart';
import 'group_screen.dart';

enum LibraryGrouping { athlete, event }

/// Throws nobody is attached to yet. Kept as one heading so they are easy
/// to find and tag, and pinned last so housekeeping never sits above the
/// athletes actually being coached.
const _unassigned = 'Unassigned';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int? _availableBuild;

  /// A build the user tapped "Later" on: hidden until a still-newer build
  /// shows up, so re-checks don't re-nag about the same one.
  int? _dismissedBuild;
  LibraryGrouping _grouping = LibraryGrouping.athlete;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdate();
  }

  @override
  void dispose() {
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on every return to the foreground: the one-shot check at launch
    // misses builds published while the app was open or backgrounded, and
    // covers a launch where the network wasn't ready yet.
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final build = await AppUpdater.checkForUpdate();
    if (!mounted || build == null) return;
    setState(() => _availableBuild = build);
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

    // Re-encode for instant frame seeks, then pre-extract frames for smooth
    // scrubbing; this is the slow part of importing.
    final encodeProgress = ValueNotifier<double?>(null);
    final stage = ValueNotifier<String>(
        'Re-encoding for instant frame-by-frame scrubbing. Long or '
        'high-fps clips take a few minutes.');
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
            ValueListenableBuilder<String>(
              valueListenable: stage,
              builder: (context, text, _) => Text(text),
            ),
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
    final fps = rates?.playback ?? 30;
    final path = await VideoOptimizer.optimizeForScrubbing(
      picked.path,
      id,
      onProgress: (p) => encodeProgress.value = p,
    );
    stage.value = 'Extracting frames for smooth scrubbing…';
    encodeProgress.value = null;
    final frames = await VideoOptimizer.extractScrubFrames(
      path,
      id,
      fps,
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
      fps: fps,
      captureFps: rates?.capture,
      athlete: details.athlete,
      thumbnailPath: thumbnail,
      scrubFramesDir: frames?.dir,
      scrubFrameCount: frames?.count ?? 0,
      scrubFrameStride: frames?.stride ?? 1,
      scrubFrameLongSide:
          frames != null ? VideoOptimizer.scrubFrameMax : 0,
      scrubFramesVersion:
          frames != null ? VideoOptimizer.scrubFramesVersion : 0,
      // Only a copy we made carries the current geometry; when the encode
      // failed the original file stands in and still needs remaking.
      playbackVersion:
          path == picked.path ? 0 : VideoOptimizer.playbackVersion,
    );
    await library.add(video);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisScreen(
              video: video, siblings: _siblingsOf(library, video)),
        ),
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

  /// The throws shown alongside [video] in the library — its group under
  /// the current grouping. Handed to the analysis screen so paging through
  /// a session matches what the coach was just looking at.
  List<ThrowVideo> _siblingsOf(VideoLibrary library, ThrowVideo video) {
    for (final group in _grouped(library.videos).values) {
      if (group.any((sibling) => sibling.id == video.id)) return group;
    }
    return [video];
  }

  /// The library split into headings, each newest first, with the headings
  /// themselves ordered by whoever threw most recently.
  ///
  /// Alphabetical order sounds tidier but buries the session you filmed an
  /// hour ago under whichever athlete's name starts with an A, and drops
  /// "Unassigned" into the middle of the names.
  Map<String, List<ThrowVideo>> _grouped(List<ThrowVideo> videos) {
    final map = <String, List<ThrowVideo>>{};
    for (final video in videos) {
      final key = _grouping == LibraryGrouping.athlete
          ? (video.athlete.isEmpty ? _unassigned : video.athlete)
          : video.event.label;
      map.putIfAbsent(key, () => []).add(video);
    }
    for (final group in map.values) {
      group.sort((a, b) => b.displayDate.compareTo(a.displayDate));
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a == _unassigned) return 1;
        if (b == _unassigned) return -1;
        return map[b]!.first.displayDate.compareTo(map[a]!.first.displayDate);
      });
    return {for (final k in keys) k: map[k]!};
  }

  /// Throws matching the search box: who threw it, what it is, or the note.
  List<ThrowVideo> _matching(List<ThrowVideo> videos) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return videos;
    return videos.where((video) {
      final haystack = '${video.athlete} ${video.event.label} '
          '${video.gender.label} ${video.note}';
      return haystack.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.displayDate.compareTo(a.displayDate));
  }

  /// What a card says about a throw, given what its heading already said.
  String _cardTitle(ThrowVideo video) =>
      _grouping == LibraryGrouping.athlete
          ? '${video.event.label} · ${video.gender.label}'
          : '${video.athlete.isEmpty ? _unassigned : video.athlete} '
              '· ${video.gender.label}';

  void _openThrow(ThrowVideo video, List<ThrowVideo> siblings) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(video: video, siblings: siblings),
      ),
    );
  }

  void _openGroup(String heading, List<ThrowVideo> videos) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupScreen(
          title: heading,
          videoIds: [for (final video in videos) video.id],
          titleFor: _cardTitle,
        ),
      ),
    );
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
            if (_availableBuild != null &&
                _availableBuild != _dismissedBuild)
              MaterialBanner(
                leading: const Icon(Icons.system_update),
                content: const Text('A new version of ThrowLab is ready.'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _dismissedBuild = _availableBuild),
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
                      : _libraryList(library);
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

  /// Search first, then the grouping switch, then the shelves. The two
  /// controls stay put while the shelves scroll: a search box that scrolls
  /// away is one you have to hunt for exactly when the library is long
  /// enough to need it.
  Widget _libraryList(VideoLibrary library) {
    final searching = _query.trim().isNotEmpty;
    final matches = _matching(library.videos);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SearchBar(
            controller: _search,
            hintText: 'Search athletes, events, notes',
            leading: const Icon(Icons.search),
            trailing: [
              if (searching)
                IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
            ],
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (!searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<LibraryGrouping>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: LibraryGrouping.athlete,
                    icon: Icon(Icons.person),
                    label: Text('By athlete')),
                ButtonSegment(
                    value: LibraryGrouping.event,
                    icon: EventGlyph(ThrowEvent.javelin, size: 18),
                    label: Text('By event')),
              ],
              selected: {_grouping},
              onSelectionChanged: (selection) =>
                  setState(() => _grouping = selection.first),
            ),
          ),
        Expanded(
          child: searching ? _results(matches) : _shelves(matches),
        ),
      ],
    );
  }

  /// A flat grid of whatever matched, newest first — searching is looking
  /// for one throw, so headings would only get in the way.
  Widget _results(List<ThrowVideo> matches) {
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Nothing matches "${_query.trim()}".',
              textAlign: TextAlign.center),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final video = matches[index];
        return ThrowCard(
          video: video,
          // A search crosses headings, so the card has to say whose it is
          // whichever grouping is selected.
          title: '${video.athlete.isEmpty ? _unassigned : video.athlete} '
              '· ${video.event.label}',
          onTap: () => _openThrow(video, matches),
          onLongPress: () => showThrowActions(context, video),
        );
      },
    );
  }

  /// One horizontal shelf per heading, newest throw first.
  ///
  /// The library used to be a column of always-expanded groups, so five
  /// athletes with fifteen throws each was a seventy-five row scroll and
  /// no athlete could be seen without pushing the others off the screen.
  /// A shelf costs one row whatever it holds, and the card cut off at the
  /// right edge is what says there are more.
  Widget _shelves(List<ThrowVideo> videos) {
    final groups = _grouped(videos);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: [
        for (final entry in groups.entries) _shelf(entry.key, entry.value),
      ],
    );
  }

  Widget _shelf(String heading, List<ThrowVideo> videos) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openGroup(heading, videos),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                _headingAvatar(heading, videos.first),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(heading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${videos.length} throw'
                        '${videos.length == 1 ? '' : 's'} · '
                        '${shortThrowDate(videos.first.displayDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        SizedBox(
          // 132px card => an 82px still plus two lines; the rest is slack
          // for a large text-scale setting.
          height: 138,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: videos.length,
            separatorBuilder: (context, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final video = videos[index];
              return SizedBox(
                width: 132,
                child: ThrowCard(
                  video: video,
                  title: _cardTitle(video),
                  onTap: () => _openThrow(video, videos),
                  onLongPress: () => showThrowActions(context, video),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _headingAvatar(String heading, ThrowVideo first) {
    if (_grouping == LibraryGrouping.event) {
      return EventGlyph(first.event, color: eventColor(first.event));
    }
    final scheme = Theme.of(context).colorScheme;
    if (heading == _unassigned) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        _initials(heading),
        style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
            fontSize: 13),
      ),
    );
  }

  /// "Sam Okoye" → "SO", "Sam" → "SA". Only ever two characters, so the
  /// avatar stays a circle whatever the name.
  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final one = parts.first;
      return (one.length >= 2 ? one.substring(0, 2) : one).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
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
  String _athlete = '';

  @override
  Widget build(BuildContext context) {
    final spec = _event.specFor(_gender);
    return AlertDialog(
      title: const Text('Throw details'),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AthletePicker(
            known: context.read<VideoLibrary>().knownAthletes,
            value: _athlete,
            onChanged: (name) => setState(() => _athlete = name),
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
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, (
            event: _event,
            gender: _gender,
            athlete: _athlete.trim(),
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

  /// Once one throw is picked the list narrows to its event: comparing a
  /// javelin release against a shot put says nothing, and the narrowing is
  /// what makes a long library usable on the second pick.
  ThrowEvent? get _event => _selected.isEmpty ? null : _selected.first.event;

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final shown = event == null
        ? widget.videos
        : widget.videos.where((video) => video.event == event).toList();
    return AlertDialog(
      title: Text(event == null
          ? 'Pick two throws'
          : 'Pick another ${event.label.toLowerCase()} throw'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final video in shown)
              CheckboxListTile(
                value: _selected.contains(video),
                secondary: ThrowThumbnail(video),
                title: Text(throwTitle(video)),
                subtitle: Text(throwSubtitle(video),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
