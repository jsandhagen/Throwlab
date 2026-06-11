import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/video_library.dart';
import 'analysis_screen.dart';
import 'comparison_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _importVideo(BuildContext context) async {
    final library = context.read<VideoLibrary>();
    final picked =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final details = await showDialog<({ThrowEvent event, Gender gender})>(
      context: context,
      builder: (context) => const _ImportDialog(),
    );
    if (details == null) return;

    final video = ThrowVideo(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      path: picked.path,
      event: details.event,
      gender: details.gender,
      importedAt: DateTime.now(),
    );
    await library.add(video);
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnalysisScreen(video: video)),
      );
    }
  }

  Future<void> _startComparison(BuildContext context) async {
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
    if (selection != null && selection.length == 2 && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComparisonScreen(
              videoA: selection[0], videoB: selection[1]),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ThrowLab'),
        actions: [
          IconButton(
            tooltip: 'Compare two throws',
            icon: const Icon(Icons.compare),
            onPressed: () => _startComparison(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Consumer<VideoLibrary>(
        builder: (context, library, _) {
          if (!library.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (library.videos.isEmpty) {
            return const _EmptyState();
          }
          return ListView.builder(
            itemCount: library.videos.length,
            itemBuilder: (context, index) {
              final video = library.videos[index];
              return ListTile(
                leading: CircleAvatar(child: Icon(video.event.icon)),
                title: Text(
                    '${video.event.label} · ${video.gender.label}'),
                subtitle: Text(
                  '${video.importedAt.toLocal().toString().substring(0, 16)}'
                  '${video.note.isEmpty ? '' : ' — ${video.note}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'note') {
                      final note = await _editNote(context, video.note);
                      if (note != null) {
                        video.note = note;
                        await library.update(video);
                      }
                    } else if (action == 'delete') {
                      await library.remove(video.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'note', child: Text('Edit note')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AnalysisScreen(video: video)),
                ),
              );
            },
          );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.video_library),
        label: const Text('Import throw'),
        onPressed: () => _importVideo(context),
      ),
    );
  }

  Future<String?> _editNote(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              hintText: 'e.g. "PB attempt, slight headwind"'),
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
            const Icon(Icons.sports_martial_arts, size: 72),
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

  @override
  Widget build(BuildContext context) {
    final spec = _event.specFor(_gender);
    return AlertDialog(
      title: const Text('Throw details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          onPressed: () =>
              Navigator.pop(context, (event: _event, gender: _gender)),
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
