import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/app_updater.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
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

  @override
  void initState() {
    super.initState();
    AppUpdater.checkForUpdate().then((build) {
      if (mounted && build != null) {
        setState(() => _availableBuild = build);
      }
    });
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

  Color _eventColor(ThrowEvent event) => switch (event) {
        ThrowEvent.shotPut => Colors.orangeAccent,
        ThrowEvent.discus => Colors.greenAccent,
        ThrowEvent.hammer => Colors.purpleAccent,
        ThrowEvent.javelin => Colors.lightBlueAccent,
      };

  Map<String, List<ThrowVideo>> _grouped(List<ThrowVideo> videos) {
    final map = <String, List<ThrowVideo>>{};
    for (final video in videos) {
      final key = _grouping == LibraryGrouping.athlete
          ? (video.athlete.isEmpty ? 'Unassigned' : video.athlete)
          : video.event.label;
      map.putIfAbsent(key, () => []).add(video);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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

  Widget _libraryList(VideoLibrary library) {
    final groups = _grouped(library.videos);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<LibraryGrouping>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: LibraryGrouping.athlete,
                  icon: Icon(Icons.person),
                  label: Text('By athlete')),
              ButtonSegment(
                  value: LibraryGrouping.event,
                  icon: Icon(Icons.category),
                  label: Text('By event')),
            ],
            selected: {_grouping},
            onSelectionChanged: (selection) =>
                setState(() => _grouping = selection.first),
          ),
        ),
        for (final entry in groups.entries)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: true,
              shape: const Border(),
              leading: Icon(_grouping == LibraryGrouping.athlete
                  ? Icons.person
                  : entry.value.first.event.icon),
              title: Text(entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${entry.value.length} '
                  'throw${entry.value.length == 1 ? '' : 's'}'),
              children: [
                for (final video in entry.value) _videoTile(context, video),
              ],
            ),
          ),
      ],
    );
  }

  Widget _videoTile(BuildContext context, ThrowVideo video) {
    final library = context.read<VideoLibrary>();
    final title = _grouping == LibraryGrouping.athlete
        ? '${video.event.label} · ${video.gender.label}'
        : '${video.athlete.isEmpty ? 'Unassigned' : video.athlete} '
            '· ${video.gender.label}';
    return ListTile(
      leading: _thumbnail(video),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${video.importedAt.toLocal().toString().substring(0, 16)}'
        '${video.note.isEmpty ? '' : ' — ${video.note}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'note') {
            final note = await _editText(
                context, 'Note', video.note,
                'e.g. "PB attempt, slight headwind"');
            if (note != null) {
              video.note = note;
              await library.update(video);
            }
          } else if (action == 'athlete') {
            final name = await _editText(
                context, 'Athlete', video.athlete, 'e.g. "Sam"');
            if (name != null) {
              video.athlete = name.trim();
              await library.update(video);
            }
          } else if (action == 'delete') {
            await library.remove(video.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'athlete', child: Text('Set athlete')),
          PopupMenuItem(value: 'note', child: Text('Edit note')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnalysisScreen(video: video)),
      ),
    );
  }

  Widget _thumbnail(ThrowVideo video) {
    final color = _eventColor(video.event);
    final path = video.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path),
            width: 72, height: 48, fit: BoxFit.cover),
      );
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.18),
      child: Icon(video.event.icon, color: color),
    );
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
