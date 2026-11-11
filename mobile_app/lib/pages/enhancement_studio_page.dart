import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/backend_api.dart';
import '../services/project_storage.dart';
import '../services/library_storage.dart';
import 'audio_studio_page.dart';

class EnhancementStudioPage extends StatefulWidget {
  const EnhancementStudioPage({super.key});

  @override
  State<EnhancementStudioPage> createState() => _EnhancementStudioPageState();
}

class _EnhancementStudioPageState extends State<EnhancementStudioPage> {
  List<Map<String, dynamic>> _videoTools = [];
  List<Map<String, dynamic>> _audioTools = [];
  List<String> _videoOperations = [];
  List<String> _audioOperations = [];
  String _mode = 'Video';
  String? _assetName;
  File? _videoFile;
  String? _selectedProfile;
  String _upscaleMediaType = 'Video';
  int _upscaleScale = 4;
  String? _upscaleModel;
  bool _artifactIsImage = false;
  String? _projectId;
  String? _assetId;
  String? _jobId;
  String? _artifactUrl;
  String? _jobError;
  String? _previewError;
  String? _saveWarning;
  String _jobStatus = 'idle';
  String _jobStep = '';
  int _progress = 0;
  bool _busy = false;
  VideoPlayerController? _player;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRuntime();
  }

  Future<void> _loadRuntime() async {
    try {
      final results = await Future.wait([
        BackendApi.getProviders(capability: 'enhancement'),
        BackendApi.getProviders(capability: 'audio_processing'),
        BackendApi.getCapabilities(),
      ]);
      List<String> operationsFor(String id) {
        final matching = results[2].where((item) => item['id'] == id);
        return matching.isEmpty
            ? const []
            : List<String>.from(
                matching.first['mobile_job_operations'] as List? ?? const [],
              );
      }

      if (!mounted) return;
      setState(() {
        _videoTools = results[0];
        _audioTools = results[1];
        _videoOperations = operationsFor('enhancement');
        _audioOperations = operationsFor('audio_processing');
        _selectedProfile = _profiles.firstOrNull;
        _upscaleModel = _upscaleModels.firstOrNull;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickAsset() async {
    final result = await FilePicker.pickFiles(
      type: _mode == 'Video'
          ? FileType.video
          : _mode == 'Audio'
          ? FileType.audio
          : _upscaleMediaType == 'Image'
          ? FileType.image
          : FileType.video,
    );
    if (!mounted || result.isEmpty) return;
    await _player?.dispose();
    _player = null;
    setState(() {
      _assetName = result.first.name;
      _videoFile = _mode != 'Audio' && result.first.path != null
          ? File(result.first.path!)
          : null;
      _artifactUrl = null;
      _jobError = null;
      _previewError = null;
      _saveWarning = null;
    });
  }

  Map<String, dynamic>? get _colorGradeTool =>
      _videoTools.where((tool) => tool['tool_id'] == 'color_grade').firstOrNull;

  List<String> get _profiles {
    final schema = _colorGradeTool?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    final profileSchema = properties is Map ? properties['profile'] : null;
    final values = profileSchema is Map ? profileSchema['enum'] : null;
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  Map<String, dynamic>? get _upscaleTool =>
      _videoTools.where((tool) => tool['tool_id'] == 'upscale').firstOrNull;

  Map<String, dynamic> get _upscaleProperties {
    final schema = _upscaleTool?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    return properties is Map ? Map<String, dynamic>.from(properties) : const {};
  }

  List<int> get _upscaleScales {
    final values = _upscaleProperties['scale']?['enum'];
    return values is List
        ? values
              .map((value) => int.tryParse(value.toString()))
              .whereType<int>()
              .toList()
        : const [];
  }

  List<String> get _upscaleModels {
    final values = _upscaleProperties['model']?['enum'];
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  bool get _canGrade =>
      !_busy &&
      _mode == 'Video' &&
      _videoFile != null &&
      _colorGradeTool?['status'] == 'available' &&
      _videoOperations.contains('color_grade') &&
      _profiles.contains(_selectedProfile);

  bool get _canUpscale =>
      !_busy &&
      _mode == 'Upscale' &&
      _videoFile != null &&
      _upscaleTool?['status'] == 'available' &&
      _videoOperations.contains('upscale') &&
      _upscaleScales.contains(_upscaleScale);

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _runColorGrade() async {
    final file = _videoFile;
    final profile = _selectedProfile;
    if (file == null || profile == null || !_canGrade) return;
    setState(() {
      _busy = true;
      _jobError = null;
      _jobStatus = 'preparing';
      _jobStep = 'Creating project';
      _progress = 0;
      _artifactUrl = null;
    });
    try {
      final project = await BackendApi.createProject(
        name: 'Color grade · ${_assetName ?? 'Video'}',
      );
      _projectId = project['id']?.toString();
      if (_projectId == null || _projectId!.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      if (!mounted) return;
      setState(() => _jobStep = 'Uploading source video');
      final asset = await BackendApi.uploadVideoAsset(
        projectId: _projectId!,
        file: file,
      );
      _assetId = asset['id']?.toString();
      if (_assetId == null || _assetId!.isEmpty) {
        throw const FormatException('Backend returned no video asset ID.');
      }
      await LibraryStorage.upsertRemoteAsset(
        id: _assetId!,
        name: asset['name']?.toString() ?? file.uri.pathSegments.last,
        type: 'video',
        projectId: _projectId!,
        remoteUrl: BackendApi.resolveApiUrl(asset['file_url'].toString()),
        mimeType: asset['mime_type']?.toString(),
      );
      final created = await BackendApi.createColorGradeJob(
        projectId: _projectId!,
        assetId: _assetId!,
        profile: profile,
      );
      _jobId = created['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no job ID.');
      }
      if (mounted) {
        setState(() {
          _jobStatus = created['status']?.toString() ?? 'queued';
          _jobStep = created['current_step']?.toString() ?? 'queued';
          _progress = (created['progress'] as num?)?.toInt() ?? 0;
        });
      }
      var job = created;
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 10)) {
        final status = job['status']?.toString() ?? 'running';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        job = await BackendApi.getJob(_jobId!);
        if (mounted) {
          setState(() {
            _jobStatus = job['status']?.toString() ?? 'running';
            _jobStep = job['current_step']?.toString() ?? 'processing';
            _progress = (job['progress'] as num?)?.toInt() ?? _progress;
          });
        }
      }
      if (job['status'] != 'completed') {
        throw FormatException(
          job['error']?.toString() ?? 'Color grade job did not complete.',
        );
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final video = artifacts
          .where(
            (item) => item['type'] == 'video' && item['download_url'] != null,
          )
          .firstOrNull;
      if (video == null) {
        throw const FormatException('The completed job has no video artifact.');
      }
      final url = BackendApi.resolveApiUrl(video['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: video['id'].toString(),
        name: 'Color graded · ${video['metadata']?['profile'] ?? 'video'}',
        type: 'video',
        projectId: _projectId!,
        remoteUrl: url,
        mimeType: video['mime_type']?.toString(),
      );
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      String? previewError;
      var previewReady = false;
      try {
        await controller.initialize();
        previewReady = true;
      } catch (error) {
        previewError = 'Artifact is ready, but video preview failed: $error';
        await controller.dispose();
      }
      if (!mounted) {
        if (previewReady) await controller.dispose();
        return;
      }
      try {
        await ProjectStorage.saveProject(
          id: _projectId,
          projectId: _projectId,
          title: 'Color grade · ${_assetName ?? 'Video'}',
          prompt: '',
          style: profile,
          duration: '${video['metadata']?['duration'] ?? ''}s',
          assetCount: 2,
          status: 'Completed',
          videoUrl: url,
          jobId: _jobId,
          mode: 'Color Grade',
          resolution: 'Source',
        );
      } catch (error) {
        _saveWarning =
            'Artifact is ready, but local project indexing failed: $error';
      }
      if (!mounted) {
        if (previewReady) await controller.dispose();
        return;
      }
      await _player?.dispose();
      _player = previewReady ? controller : null;
      setState(() {
        _artifactUrl = url;
        _previewError = previewError;
        _jobStatus = 'completed';
        _jobStep = 'Artifact ready';
        _progress = 100;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _jobError = error.toString().replaceFirst('Exception: ', '');
        _jobStatus = 'failed';
        _jobStep = 'Failed';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runUpscale() async {
    final file = _videoFile;
    if (file == null || !_canUpscale) return;
    final isImage = _upscaleMediaType == 'Image';
    setState(() {
      _busy = true;
      _jobError = null;
      _previewError = null;
      _jobStatus = 'preparing';
      _jobStep = 'Creating project';
      _progress = 0;
      _artifactUrl = null;
    });
    await _player?.dispose();
    _player = null;
    try {
      final project = await BackendApi.createProject(
        name: 'Upscale · ${_assetName ?? 'Media'}',
      );
      _projectId = project['id']?.toString();
      if (_projectId == null || _projectId!.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      if (mounted) setState(() => _jobStep = 'Uploading source');
      final asset = await BackendApi.uploadMediaAsset(
        projectId: _projectId!,
        file: file,
      );
      _assetId = asset['id']?.toString();
      if (_assetId == null || _assetId!.isEmpty) {
        throw const FormatException('Backend returned no source asset ID.');
      }
      await LibraryStorage.upsertRemoteAsset(
        id: _assetId!,
        name:
            asset['name']?.toString() ??
            _assetName ??
            file.uri.pathSegments.last,
        type: isImage ? 'image' : 'video',
        projectId: _projectId!,
        remoteUrl: BackendApi.resolveApiUrl(asset['file_url'].toString()),
        mimeType: asset['mime_type']?.toString(),
      );
      final created = await BackendApi.createUpscaleJob(
        projectId: _projectId!,
        assetId: _assetId!,
        parameters: {
          'provider_tool_id': _upscaleTool?['tool_id']?.toString(),
          'scale': _upscaleScale,
          if (_upscaleModel != null) 'model_id': _upscaleModel,
        },
      );
      _jobId = created['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no upscale job ID.');
      }
      var job = created;
      final timeout = Stopwatch()..start();
      while (timeout.elapsed < const Duration(minutes: 20)) {
        final status = job['status']?.toString() ?? 'queued';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        if (mounted) {
          setState(() {
            _jobStatus = status;
            _jobStep = job['current_step']?.toString() ?? 'processing';
            _progress = (job['progress'] as num?)?.toInt() ?? _progress;
          });
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await BackendApi.getJob(_jobId!);
      }
      if (job['status'] != 'completed') {
        if (job['status'] != 'failed' && job['status'] != 'cancelled') {
          throw FormatException('Upscale is still processing. Job ID: $_jobId');
        }
        throw FormatException(job['error']?.toString() ?? 'upscale_failed');
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final artifact = artifacts
          .where((item) => item['type'] == (isImage ? 'image' : 'video'))
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException(
          'Completed upscale job has no matching media artifact.',
        );
      }
      final url = BackendApi.resolveApiUrl(artifact['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: '$_upscaleScale× upscaled · ${_assetName ?? 'media'}',
        type: isImage ? 'image' : 'video',
        projectId: _projectId!,
        remoteUrl: url,
        mimeType: artifact['mime_type']?.toString(),
      );
      VideoPlayerController? controller;
      String? previewError;
      if (!isImage) {
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
        try {
          await controller.initialize();
        } catch (error) {
          previewError = 'Video artifact is ready, but preview failed: $error';
          await controller.dispose();
          controller = null;
        }
      }
      if (!mounted) {
        await controller?.dispose();
        return;
      }
      setState(() {
        _player = controller;
        _artifactIsImage = isImage;
        _artifactUrl = url;
        _previewError = previewError;
        _jobStatus = 'completed';
        _jobStep = 'Artifact ready';
        _progress = 100;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _jobError = error.toString().replaceFirst('Exception: ', '');
          _jobStatus = 'failed';
          _jobStep = 'Failed';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _tools =>
      _mode == 'Audio' ? _audioTools : _videoTools;

  List<String> get _operations =>
      _mode == 'Audio' ? _audioOperations : _videoOperations;

  String get _status {
    if (_loading) return 'Loading OpenMontage enhancement tools.';
    if (_error != null) return 'Enhancement registry unavailable: $_error';
    if (_tools.isEmpty) {
      return 'No matching OpenMontage enhancement tools are registered.';
    }
    if (!_tools.any((tool) => tool['status'] == 'available')) {
      return 'Enhancement tools are unavailable on this backend.';
    }
    if (_operations.isEmpty) {
      return 'Tools are registered, but enhancement jobs are not exposed by the mobile API.';
    }
    return 'Available operations: ${_operations.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Enhancement Studio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Video',
                  icon: Icon(Icons.movie_outlined),
                  label: Text('Video'),
                ),
                ButtonSegment(
                  value: 'Audio',
                  icon: Icon(Icons.graphic_eq_outlined),
                  label: Text('Audio'),
                ),
                ButtonSegment(
                  value: 'Upscale',
                  icon: Icon(Icons.hd_outlined),
                  label: Text('Upscale'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) async {
                await _player?.dispose();
                _player = null;
                if (!mounted) return;
                setState(() {
                  _mode = value.first;
                  _assetName = null;
                  _videoFile = null;
                  _artifactUrl = null;
                  _artifactIsImage = false;
                });
              },
            ),
            if (_mode == 'Upscale') ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Video', label: Text('Video')),
                  ButtonSegment(value: 'Image', label: Text('Image')),
                ],
                selected: {_upscaleMediaType},
                onSelectionChanged: (value) async {
                  await _player?.dispose();
                  _player = null;
                  if (!mounted) return;
                  setState(() {
                    _upscaleMediaType = value.first;
                    _assetName = null;
                    _videoFile = null;
                    _artifactUrl = null;
                    _artifactIsImage = false;
                  });
                },
              ),
            ],
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: Text(_status),
                subtitle: const Text(
                  'Tool state comes from the OpenMontage registry; job support is checked separately.',
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              _mode == 'Video'
                  ? 'Input Video'
                  : _mode == 'Upscale'
                  ? 'Input $_upscaleMediaType'
                  : 'Input Audio',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickAsset,
              icon: Icon(
                _mode == 'Video' || _mode == 'Upscale'
                    ? Icons.video_file_outlined
                    : Icons.audio_file_outlined,
              ),
              label: Text(
                _assetName ??
                    'Choose ${_mode == 'Upscale' ? _upscaleMediaType.toLowerCase() : _mode.toLowerCase()} file',
              ),
            ),
            if (_assetName != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _mode == 'Video'
                      ? 'The selected video uploads to the project when you apply Color Grade.'
                      : _mode == 'Upscale'
                      ? 'The selected media uploads to the project when you run the OpenMontage upscaler.'
                      : 'Audio upload and enhancement jobs are not connected.',
                ),
              ),
            if (_mode == 'Upscale') ...[
              const SizedBox(height: 12),
              if (_upscaleScales.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: _upscaleScales.contains(_upscaleScale)
                      ? _upscaleScale
                      : _upscaleScales.first,
                  decoration: const InputDecoration(
                    labelText: 'Upscale factor',
                    border: OutlineInputBorder(),
                  ),
                  items: _upscaleScales
                      .map(
                        (scale) => DropdownMenuItem(
                          value: scale,
                          child: Text('$scale×'),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _upscaleScale = value ?? _upscaleScale,
                        ),
                ),
              if (_upscaleModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _upscaleModels.contains(_upscaleModel)
                      ? _upscaleModel
                      : _upscaleModels.first,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                  items: _upscaleModels
                      .map(
                        (model) =>
                            DropdownMenuItem(value: model, child: Text(model)),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _upscaleModel = value),
                ),
              ],
            ],
            const SizedBox(height: 14),
            Text('OpenMontage Tools', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_tools.isEmpty && !_loading)
              const Card(
                child: ListTile(
                  title: Text('No tools registered for this media type.'),
                ),
              )
            else
              ..._tools.map((tool) {
                final name = tool['tool_id']?.toString() ?? 'Tool';
                final available = tool['status'] == 'available';
                final operations = List<String>.from(
                  tool['operations'] as List? ?? const [],
                );
                return Card(
                  child: ExpansionTile(
                    leading: Icon(
                      available
                          ? Icons.check_circle_outline
                          : Icons.cloud_off_outlined,
                    ),
                    title: Text(name),
                    subtitle: Text(
                      '${tool['status'] ?? 'unknown'} · ${operations.join(', ')}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [_schemaOptions(tool)],
                  ),
                );
              }),
            if (_busy || _jobStatus != 'idle') ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Job $_jobStatus · $_progress%'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _progress / 100),
                      const SizedBox(height: 6),
                      Text(_jobStep),
                      if (_jobId != null) SelectableText('Job ID: $_jobId'),
                      if (_projectId != null)
                        SelectableText('Project ID: $_projectId'),
                      if (_jobError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _jobError!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (_saveWarning != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_saveWarning!),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_artifactIsImage && _artifactUrl != null)
              Card(
                child: Column(
                  children: [
                    Image.network(
                      _artifactUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Image artifact is saved, but the preview could not be loaded.',
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('Upscaled image artifact'),
                      subtitle: Text(_artifactUrl!),
                    ),
                  ],
                ),
              )
            else if (_player case final player?)
              Card(
                child: Column(
                  children: [
                    if (player.value.isInitialized)
                      AspectRatio(
                        aspectRatio: player.value.aspectRatio,
                        child: VideoPlayer(player),
                      )
                    else
                      const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ListTile(
                      leading: IconButton(
                        onPressed: player.value.isInitialized
                            ? () => setState(() {
                                player.value.isPlaying
                                    ? player.pause()
                                    : player.play();
                              })
                            : null,
                        icon: Icon(
                          player.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      title: Text(
                        _mode == 'Upscale'
                            ? 'Upscaled video artifact'
                            : 'Color graded video artifact',
                      ),
                      subtitle: Text(_artifactUrl ?? ''),
                    ),
                  ],
                ),
              )
            else if (_previewError != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.video_file_outlined),
                  title: Text(
                    _mode == 'Upscale'
                        ? 'Upscaled video artifact'
                        : 'Color graded video artifact',
                  ),
                  subtitle: Text(_previewError!),
                  trailing: _artifactUrl == null
                      ? null
                      : const Icon(Icons.check_circle_outline),
                ),
              )
            else
              Card(
                child: SizedBox(
                  height: 150,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.compare_outlined,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        const Text('Before / After Preview'),
                        const SizedBox(height: 4),
                        const Text('No enhanced artifact is available yet.'),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            if (_mode != 'Audio')
              FilledButton.icon(
                onPressed: _mode == 'Video'
                    ? (_canGrade ? _runColorGrade : null)
                    : _mode == 'Upscale'
                    ? (_canUpscale ? _runUpscale : null)
                    : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_outlined),
                label: Text(
                  _busy
                      ? (_mode == 'Upscale'
                            ? 'Upscaling Media...'
                            : 'Processing Color Grade...')
                      : _mode == 'Upscale' &&
                            _videoOperations.contains('upscale') &&
                            _upscaleTool?['status'] == 'available'
                      ? 'Upscale $_upscaleMediaType'
                      : _videoOperations.contains('color_grade') &&
                            _colorGradeTool?['status'] == 'available'
                      ? 'Apply Color Grade'
                      : 'Apply Enhancement · Coming Soon',
                ),
              ),
            if (_mode == 'Audio')
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioStudioPage(),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Audio Studio'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _schemaOptions(Map<String, dynamic> tool) {
    if (tool['tool_id'] == 'color_grade') {
      if (_profiles.isEmpty) {
        return const ListTile(
          title: Text('No color profile is advertised by this tool.'),
        );
      }
      return DropdownButtonFormField<String>(
        initialValue: _profiles.contains(_selectedProfile)
            ? _selectedProfile
            : _profiles.first,
        decoration: const InputDecoration(
          labelText: 'Color Profile',
          border: OutlineInputBorder(),
        ),
        items: _profiles
            .map(
              (profile) => DropdownMenuItem(
                value: profile,
                child: Text(profile.replaceAll('_', ' ')),
              ),
            )
            .toList(),
        onChanged: tool['status'] == 'available'
            ? (value) => setState(() => _selectedProfile = value)
            : null,
      );
    }
    final schema = tool['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    if (properties is! Map || properties.isEmpty) {
      return const ListTile(
        title: Text('No user-configurable options declared.'),
      );
    }
    final entries = properties.entries.where((entry) {
      final value = entry.value;
      return value is Map && value['enum'] is List;
    });
    final widgets = entries.map((entry) {
      final values = (entry.value as Map)['enum'] as List;
      final options = values.map((value) => value.toString()).toList();
      if (options.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: entry.key.toString(),
            border: const OutlineInputBorder(),
          ),
          child: Text(options.join(' · ')),
        ),
      );
    }).toList();
    return widgets.isEmpty
        ? const ListTile(
            title: Text('Options are specified by the tool schema.'),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widgets,
          );
  }
}
