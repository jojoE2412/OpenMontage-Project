import 'package:flutter/material.dart';

import 'library_page.dart';
import 'projects_page.dart';
import 'video_trim_studio_page.dart';

class VideoEditorPage extends StatelessWidget {
  const VideoEditorPage({
    super.key,
    this.title = 'New Video',
    this.prompt = '',
    this.duration = '30s',
    this.projectId,
  });
  final String title;
  final String prompt;
  final String duration;
  final String? projectId;

  @override
  Widget build(BuildContext context) => VideoTrimStudioPage(
    title: title,
    prompt: prompt,
    duration: duration,
    projectId: projectId,
  );
}

@Deprecated('Use VideoEditorPage, which submits real Phase 1 trim jobs.')
class LegacyVideoEditorPreview extends StatefulWidget {
  const LegacyVideoEditorPreview({
    super.key,
    this.title = 'New Video',
    this.prompt = '',
    this.duration = '30s',
  });
  final String title;
  final String prompt;
  final String duration;

  @override
  State<LegacyVideoEditorPreview> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<LegacyVideoEditorPreview> {
  int _selectedClip = 0;
  bool _playing = false;
  double _position = .28;
  final List<String> _clips = ['Opening shot', 'Main scene', 'Closing shot'];
  static const _tools = <(String, IconData)>[
    ('Trim', Icons.content_cut),
    ('Split', Icons.vertical_split),
    ('Crop', Icons.crop),
    ('Speed', Icons.speed),
    ('Text', Icons.title),
    ('Audio', Icons.music_note),
    ('Subtitles', Icons.subtitles),
    ('Filter', Icons.color_lens),
    ('Transition', Icons.compare_arrows),
  ];

  void _tool(String name) {
    if (name == 'Split' && _clips.length < 6) {
      setState(() => _clips.insert(_selectedClip + 1, 'Split segment'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clip split in the local editor preview.'),
        ),
      );
      return;
    }
    if (name == 'Trim' && _clips.length > 1) {
      setState(() => _clips.removeAt(_selectedClip));
      setState(() => _selectedClip = _selectedClip.clamp(0, _clips.length - 1));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$name tool', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Preview controls are available in this local UI demo. Changes are not rendered to a video file.',
              ),
              if (name == 'Speed')
                const Slider(value: 1, min: .25, max: 2, onChanged: null),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _source() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LibraryPage()),
  );

  void _openProjects() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ProjectsPage()),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export is a preview in this demo.')),
          ),
          icon: const Icon(Icons.ios_share),
          label: const Text('Export'),
        ),
      ],
    ),
    body: widget.prompt.isEmpty
        ? SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: _emptyState(context),
            ),
          )
        : Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF17213A),
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF6678A8),
                                Color(0xFF293650),
                                Color(0xFFEDAC77),
                              ],
                            ),
                          ),
                          child: Center(
                            child: IconButton.filled(
                              onPressed: () =>
                                  setState(() => _playing = !_playing),
                              iconSize: 34,
                              icon: Icon(
                                _playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(_playing ? '00:08' : '00:08'),
                          Expanded(
                            child: Slider(
                              value: _position,
                              onChanged: (value) =>
                                  setState(() => _position = value),
                            ),
                          ),
                          Text(widget.duration),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Timeline',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 94,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _clips.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => GestureDetector(
                            onTap: () => setState(() => _selectedClip = index),
                            child: Container(
                              width: 150,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _selectedClip == index
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context).colorScheme.surface,
                                border: Border.all(
                                  color: _selectedClip == index
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.movie_outlined),
                                  const Spacer(),
                                  Text(
                                    _clips[index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Prompt',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.prompt.isEmpty
                            ? 'No prompt supplied.'
                            : widget.prompt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 112,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final tool in _tools)
                      SizedBox(
                        width: 82,
                        child: InkWell(
                          onTap: () => _tool(tool.$1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tool.$2),
                              const SizedBox(height: 6),
                              Text(
                                tool.$1,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );

  Widget _emptyState(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      Icon(
        Icons.movie_creation_outlined,
        size: 54,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 14),
      Text(
        'Start editing a video',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        'Import footage, choose an asset from your library, or open a project.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _source,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Video'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _source,
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Choose from Library'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _openProjects,
                icon: const Icon(Icons.folder_open),
                label: const Text('Use Project'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
