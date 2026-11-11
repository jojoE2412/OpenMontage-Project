import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/project_storage.dart';
import '../services/video_trim_service.dart';
import '../services/backend_api.dart';
import '../services/library_storage.dart';

class VideoTrimStudioPage extends StatefulWidget {
  const VideoTrimStudioPage({
    super.key,
    this.title = 'New Video',
    this.prompt = '',
    this.duration = '30s',
    this.projectId,
    this.service = const BackendVideoTrimService(),
  });

  final String title;
  final String prompt;
  final String duration;
  final String? projectId;
  final VideoTrimService service;

  @override
  State<VideoTrimStudioPage> createState() => _VideoTrimStudioPageState();
}

class _VideoTrimStudioPageState extends State<VideoTrimStudioPage> {
  final _startController = TextEditingController(text: '0');
  final _endController = TextEditingController();
  File? _videoFile;
  List<Map<String, dynamic>> _projectVideos = [];
  Map<String, dynamic>? _selectedProjectVideo;
  String? _projectId;
  String? _assetId;
  String? _jobId;
  String? _error;
  String? _artifactUrl;
  String _status = 'Available';
  String _currentStep = 'Choose a local video to start';
  double? _videoDuration;
  RangeValues _trimRange = const RangeValues(0, 1);
  int _progress = 0;
  bool _busy = false;
  bool _canReuseProject = false;
  bool _projectAssetsLoading = false;
  bool _cropAvailable = false;
  List<String> _cropAspects = [];
  String _editOperation = 'trim';
  String _cropAspect = 'portrait';
  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _loadCropSupport();
    if (widget.projectId != null) {
      _projectAssetsLoading = true;
      _loadProjectVideos();
    }
  }

  Future<void> _loadProjectVideos() async {
    try {
      final assets = await BackendApi.getProjectAssets(widget.projectId!);
      if (!mounted) return;
      setState(() {
        _projectAssetsLoading = false;
        _canReuseProject = true;
        _projectVideos = assets
            .where((asset) => asset['type'] == 'video')
            .toList();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _projectAssetsLoading = false;
          _canReuseProject = false;
        });
      }
    }
  }

  Future<void> _loadCropSupport() async {
    try {
      final results = await Future.wait([
        BackendApi.getProviders(capability: 'video_post'),
        BackendApi.getCapabilities(),
      ]);
      final tool = results[0]
          .where((item) => item['tool_id'] == 'auto_reframe')
          .firstOrNull;
      final capability = results[1]
          .where((item) => item['id'] == 'video_post')
          .firstOrNull;
      final schema = tool?['input_schema'];
      final properties = schema is Map ? schema['properties'] : null;
      final aspect = properties is Map ? properties['target_aspect'] : null;
      final values = aspect is Map ? aspect['enum'] : null;
      final operations = List<String>.from(
        capability?['mobile_job_operations'] as List? ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _cropAvailable =
            tool?['status'] == 'available' &&
            operations.contains('crop') &&
            values is List &&
            values.isNotEmpty;
        _cropAspects = values is List
            ? values.map((value) => value.toString()).toList()
            : [];
        if (!_cropAspects.contains(_cropAspect) && _cropAspects.isNotEmpty) {
          _cropAspect = _cropAspects.first;
        }
        if (!_cropAvailable && _editOperation == 'crop') {
          _editOperation = 'trim';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cropAvailable = false;
          _cropAspects = [];
        });
      }
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.pickFile(type: FileType.video);
    if (!mounted || result == null) return;
    final path = result.path;
    if (path == null || path.isEmpty) {
      setState(() => _error = 'Could not read the selected video file.');
      return;
    }
    await _player?.dispose();
    final file = File(path);
    final localPlayer = VideoPlayerController.file(file);
    try {
      await localPlayer.initialize();
    } catch (_) {
      await localPlayer.dispose();
      if (!mounted) return;
      setState(() => _error = 'Could not preview this video on the device.');
      return;
    }
    final duration = localPlayer.value.duration.inMilliseconds / 1000;
    setState(() {
      _videoFile = file;
      _selectedProjectVideo = null;
      _assetId = null;
      _player = localPlayer;
      _jobId = null;
      _artifactUrl = null;
      _videoDuration = duration;
      _trimRange = RangeValues(0, duration);
      _endController.text = duration.toStringAsFixed(2);
      _progress = 0;
      _status = 'Available';
      _currentStep = 'Video selected — ready to upload';
      _error = null;
    });
  }

  Future<void> _pickProjectVideo() async {
    final asset = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose a project video')),
            if (_projectVideos.isEmpty)
              const ListTile(
                title: Text('This project has no video assets yet.'),
              ),
            ..._projectVideos.map(
              (item) => ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: Text(item['name']?.toString() ?? 'Video'),
                subtitle: Text('${item['duration'] ?? 'Unknown'} s'),
                onTap: () => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      ),
    );
    if (asset == null || !mounted) return;
    final rawUrl = asset['file_url']?.toString();
    final assetId = asset['id']?.toString();
    if (rawUrl == null ||
        rawUrl.isEmpty ||
        assetId == null ||
        assetId.isEmpty) {
      setState(
        () => _error =
            'The selected project video has no playable asset URL or ID.',
      );
      return;
    }
    await _player?.dispose();
    final player = VideoPlayerController.networkUrl(
      Uri.parse(BackendApi.resolveApiUrl(rawUrl)),
    );
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() => _error = 'Could not preview this project video.');
      }
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    final duration =
        (asset['duration'] as num?)?.toDouble() ??
        player.value.duration.inMilliseconds / 1000;
    setState(() {
      _videoFile = null;
      _selectedProjectVideo = asset;
      _assetId = assetId;
      _player = player;
      _videoDuration = duration;
      _trimRange = RangeValues(0, duration);
      _startController.text = '0';
      _endController.text = duration.toStringAsFixed(2);
      _jobId = null;
      _artifactUrl = null;
      _progress = 0;
      _status = 'Available';
      _currentStep = 'Project video selected — ready to edit';
      _error = null;
    });
  }

  Future<void> _trimVideo() async {
    final file = _videoFile;
    final start = double.tryParse(_startController.text.trim());
    final end = double.tryParse(_endController.text.trim());
    final isTrim = _editOperation == 'trim';
    if (_projectAssetsLoading) {
      setState(() => _error = 'Loading project assets. Try again in a moment.');
      return;
    }
    if (file == null && _assetId == null) {
      setState(
        () => _error = 'Choose a video file or a video from this project.',
      );
      return;
    }
    if (isTrim && (start == null || end == null || start < 0 || end <= start)) {
      setState(() => _error = 'Enter a valid start and end time in seconds.');
      return;
    }
    if (isTrim && _videoDuration != null && end! > _videoDuration!) {
      setState(() => _error = 'End time exceeds the video duration.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Processing';
      _progress = 0;
      _currentStep = 'Preparing project';
    });
    try {
      final project = widget.projectId == null || !_canReuseProject
          ? await widget.service.createProject(widget.title)
          : <String, dynamic>{'id': widget.projectId};
      _projectId = project['id']?.toString();
      if (_projectId == null || _projectId!.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }

      Map<String, dynamic> asset;
      if (file != null) {
        setState(() => _currentStep = 'Uploading video');
        asset = await widget.service.uploadVideo(_projectId!, file);
        _assetId = asset['id']?.toString();
        _videoDuration = (asset['duration'] as num?)?.toDouble();
      } else {
        asset = _selectedProjectVideo!;
        setState(() => _currentStep = 'Using existing project video');
      }
      if (_assetId == null || _assetId!.isEmpty) {
        throw const FormatException('Backend returned no asset ID.');
      }
      await LibraryStorage.upsertRemoteAsset(
        id: _assetId!,
        name:
            asset['name']?.toString() ?? file?.uri.pathSegments.last ?? 'Video',
        type: 'video',
        projectId: _projectId!,
        remoteUrl: widget.service.resolveUrl(asset['file_url'].toString()),
        mimeType: asset['mime_type']?.toString(),
      );
      if (isTrim && _videoDuration != null && end! > _videoDuration!) {
        throw FormatException(
          'End time exceeds the uploaded video duration (${_videoDuration!.toStringAsFixed(2)} seconds).',
        );
      }

      final created = isTrim
          ? await widget.service.createTrimJob(
              projectId: _projectId!,
              assetId: _assetId!,
              start: start!,
              end: end!,
            )
          : await widget.service.createCropJob(
              projectId: _projectId!,
              assetId: _assetId!,
              targetAspect: _cropAspect,
            );
      _jobId = created['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no job ID.');
      }
      if (mounted) {
        setState(() {
          _status = created['status']?.toString() ?? 'queued';
          _progress = (created['progress'] as num?)?.toInt() ?? 0;
          _currentStep = created['current_step']?.toString() ?? 'queued';
        });
      }

      final timeout = Stopwatch()..start();
      Map<String, dynamic> job = created;
      while (timeout.elapsed < const Duration(minutes: 10)) {
        if (!mounted) return;
        if (job['status'] == 'completed' ||
            job['status'] == 'failed' ||
            job['status'] == 'cancelled') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        job = await widget.service.getJob(_jobId!);
        if (mounted) {
          setState(() {
            _status = job['status']?.toString() ?? 'running';
            _progress = (job['progress'] as num?)?.toInt() ?? _progress;
            _currentStep = job['current_step']?.toString() ?? _currentStep;
          });
        }
      }
      if (job['status'] != 'completed') {
        throw FormatException(
          job['error']?.toString() ??
              (job['status'] == 'failed'
                  ? 'Video trim failed.'
                  : 'Timed out while waiting for the backend job.'),
        );
      }

      final artifacts = await widget.service.getArtifacts(_jobId!);
      final video = artifacts.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['type'] == 'video' && item?['download_url'] != null,
        orElse: () => null,
      );
      if (video == null) {
        throw const FormatException('The completed job has no video artifact.');
      }
      final rawUrl = video['download_url'].toString();
      final resolvedUrl = widget.service.resolveUrl(rawUrl);
      await LibraryStorage.upsertRemoteAsset(
        id: video['id'].toString(),
        name: 'Edited video · ${video['metadata']?['format'] ?? 'mp4'}',
        type: 'video',
        projectId: _projectId!,
        remoteUrl: resolvedUrl,
        mimeType: video['mime_type']?.toString(),
      );
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
      );
      await controller.initialize();
      await _player?.dispose();
      _player = controller;

      await ProjectStorage.saveProject(
        id: _projectId,
        projectId: _projectId,
        title: widget.title,
        prompt: widget.prompt,
        style: isTrim ? 'Video Trim' : 'Video Crop',
        duration: isTrim
            ? '${(end! - start!).toStringAsFixed(1)}s'
            : '${_videoDuration?.toStringAsFixed(1) ?? ''}s',
        assetCount: 1,
        status: 'Completed',
        videoUrl: resolvedUrl,
        jobId: _jobId,
        mode: isTrim ? 'Trim' : 'Crop',
        resolution: 'Source',
      );
      if (mounted) {
        setState(() {
          _artifactUrl = resolvedUrl;
          _status = 'completed';
          _progress = 100;
          _currentStep = 'Artifact ready';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'failed';
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = _videoDuration ?? 1.0;
    final start = _trimRange.start.clamp(0.0, duration);
    final end = _trimRange.end.clamp(start, duration);
    return Scaffold(
      appBar: AppBar(title: const Text('Video Editor')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed:
              _busy ||
                  _projectAssetsLoading ||
                  (_videoFile == null && _assetId == null)
              ? null
              : _trimVideo,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(_editOperation == 'trim' ? 'Apply Trim' : 'Apply Crop'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Editing Studio',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              _statusBadge(theme),
            ],
          ),
          const SizedBox(height: 12),
          _preview(theme),
          if (_editOperation == 'trim') ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Timeline', style: theme.textTheme.titleMedium),
                Text(_formatTime(duration), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            _timeline(theme, start, end, duration),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _secondsField(
                    _startController,
                    'Start',
                    onChanged: (value) => _updateRange(start: value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _secondsField(
                    _endController,
                    'End',
                    onChanged: (value) => _updateRange(end: value),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text('Tools', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _toolPalette(theme),
          if (_editOperation == 'crop') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _cropAspect,
              decoration: const InputDecoration(
                labelText: 'Target aspect ratio',
              ),
              items: _cropAspects
                  .map(
                    (aspect) => DropdownMenuItem(
                      value: aspect,
                      child: Text(switch (aspect) {
                        'portrait' => 'Portrait 9:16',
                        'square' => 'Square 1:1',
                        'landscape' => 'Landscape 16:9',
                        'cinematic' => 'Cinematic 21:9',
                        'vertical_4_5' => 'Portrait 4:5',
                        _ => aspect,
                      }),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _cropAspect = value);
                    },
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(
                      _videoFile == null ? 'Choose Video' : 'Change Video',
                    ),
                  ),
                  if (_canReuseProject && _projectVideos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickProjectVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(
                        _selectedProjectVideo == null
                            ? 'Choose from This Project'
                            : 'Change Project Video',
                      ),
                    ),
                  ],
                  if (_projectAssetsLoading) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    const Text('Loading project videos...'),
                  ],
                  if (_selectedProjectVideo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _selectedProjectVideo!['name']?.toString() ??
                          'Project video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_videoFile != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _videoFile!.uri.pathSegments.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_videoDuration != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${_videoDuration!.toStringAsFixed(2)} s',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    !_canReuseProject
                        ? 'Choose a local video to begin editing.'
                        : 'Choose a local video or reuse a video already in this project.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (widget.projectId != null &&
              !_projectAssetsLoading &&
              !_canReuseProject)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Project is not available on the backend'),
                subtitle: Text(
                  'This saved project cannot accept backend edits. Continuing will create a new backend project.',
                ),
              ),
            ),
          if (_busy || _jobId != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Status: $_status',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (_busy)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _progress.clamp(0, 100) / 100,
                    ),
                    const SizedBox(height: 8),
                    Text('$_progress% · $_currentStep'),
                    if (_jobId != null)
                      Text('Job ${_jobId!}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          if (_artifactUrl != null)
            Text(
              '${_editOperation == 'trim' ? 'Trimmed' : 'Cropped'} result loaded from the OpenMontage artifact.',
              style: theme.textTheme.bodySmall,
            ),
          if (_artifactUrl != null)
            SelectableText(
              'Result: $_artifactUrl',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _secondsField(
    TextEditingController controller,
    String label, {
    ValueChanged<double>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (text) {
      final value = double.tryParse(text);
      if (value != null) onChanged?.call(value);
    },
    decoration: InputDecoration(labelText: label, suffixText: 's'),
  );

  void _updateRange({double? start, double? end}) {
    final duration = _videoDuration ?? 1.0;
    final nextStart = (start ?? _trimRange.start).clamp(0.0, duration);
    final nextEnd = (end ?? _trimRange.end).clamp(0.0, duration);
    if (nextEnd <= nextStart) return;
    setState(() => _trimRange = RangeValues(nextStart, nextEnd));
  }

  Widget _statusBadge(ThemeData theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _status,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _preview(ThemeData theme) {
    final player = _player;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: player?.value.aspectRatio ?? 16 / 9,
        child: player == null
            ? Center(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickVideo,
                  icon: const Icon(Icons.add),
                  label: const Text('Add video'),
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: VideoPlayer(player)),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      player.value.isPlaying ? player.pause() : player.play();
                    }),
                    iconSize: 36,
                    icon: Icon(
                      player.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  if (_busy)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: VideoProgressIndicator(
                      player,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: theme.colorScheme.primary,
                        bufferedColor: Colors.white54,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _timeline(ThemeData theme, double start, double end, double max) =>
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatTime(start), style: theme.textTheme.labelMedium),
                Text(_formatTime(end), style: theme.textTheme.labelMedium),
              ],
            ),
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: List.generate(
                      7,
                      (_) => Expanded(
                        child: Container(
                          height: 38,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.movie,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: .5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  RangeSlider(
                    values: RangeValues(start, end),
                    min: 0,
                    max: max,
                    onChanged: _busy || (_videoFile == null && _assetId == null)
                        ? null
                        : (value) => setState(() {
                            _trimRange = value;
                            _startController.text = value.start.toStringAsFixed(
                              2,
                            );
                            _endController.text = value.end.toStringAsFixed(2);
                          }),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  'OUT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _toolPalette(ThemeData theme) {
    final tools = <(String, IconData, bool)>[
      ('Trim', Icons.content_cut, true),
      ('Split', Icons.call_split, false),
      ('Crop', Icons.crop, _cropAvailable),
      ('Speed', Icons.speed, false),
      ('Text', Icons.title, false),
      ('Audio', Icons.music_note, false),
      ('Subtitle', Icons.subtitles_outlined, false),
      ('Filter', Icons.tune, false),
      ('Transition', Icons.swap_horiz, false),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.65,
      children: tools.map((tool) {
        final selected = tool.$1.toLowerCase() == _editOperation;
        return InkWell(
          onTap: tool.$3
              ? () => setState(() => _editOperation = tool.$1.toLowerCase())
              : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: .12)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tool.$2,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 3),
                Text(tool.$1, style: theme.textTheme.labelMedium),
                if (!tool.$3)
                  Text(
                    'Coming Soon',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTime(double seconds) {
    final centiseconds = (seconds * 100).round();
    final minutes = centiseconds ~/ 6000;
    final remaining = centiseconds % 6000;
    return '$minutes:${(remaining ~/ 100).toString().padLeft(2, '0')}.${(remaining % 100).toString().padLeft(2, '0')}';
  }
}

// ignore: unused_element
class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.schedule, size: 16),
    label: Text('$label · Coming Soon'),
  );
}
