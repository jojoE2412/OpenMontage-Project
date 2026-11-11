import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/backend_api.dart';
import '../services/library_storage.dart';

class SubtitleStudioPage extends StatefulWidget {
  const SubtitleStudioPage({super.key});

  @override
  State<SubtitleStudioPage> createState() => _SubtitleStudioPageState();
}

class _SubtitleStudioPageState extends State<SubtitleStudioPage> {
  List<Map<String, dynamic>> _analysisTools = [];
  List<Map<String, dynamic>> _subtitleTools = [];
  List<String> _jobOperations = [];
  List<String> _analysisJobOperations = [];
  List<String> _videoPostOperations = [];
  List<String> _formats = [];
  final List<_CueEditor> _cues = [_CueEditor()];
  String _format = 'srt';
  bool _busy = false;
  String? _jobId;
  String? _jobStatus;
  String? _jobError;
  String? _subtitlePreview;
  String? _projectId;
  String? _sourceAssetId;
  String? _sourceName;
  String _transcriptionModel = 'base';
  String? _transcriptionLanguage;
  bool _diarize = false;
  String? _subtitleArtifactId;
  String? _burnJobStatus;
  String? _burnError;
  VideoPlayerController? _burnedVideo;
  bool _burning = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRuntime();
  }

  @override
  void dispose() {
    _burnedVideo?.dispose();
    for (final cue in _cues) {
      cue.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRuntime() async {
    try {
      final results = await Future.wait([
        BackendApi.getProviders(capability: 'analysis'),
        BackendApi.getProviders(capability: 'subtitle'),
        BackendApi.getCapabilities(),
      ]);
      final operations = results[2].where((item) => item['id'] == 'subtitle');
      final analysisCapability = results[2].where(
        (item) => item['id'] == 'analysis',
      );
      final videoPost = results[2].where((item) => item['id'] == 'video_post');
      final subtitleJobOperations = operations.isEmpty
          ? const <String>[]
          : List<String>.from(
              operations.first['mobile_job_operations'] as List? ?? const [],
            );
      final subtitleTool = results[1]
          .where((tool) => tool['tool_id'] == 'subtitle_gen')
          .firstOrNull;
      final analysisJobOperations = analysisCapability.isEmpty
          ? const <String>[]
          : List<String>.from(
              analysisCapability.first['mobile_job_operations'] as List? ??
                  const [],
            );
      final schema = subtitleTool?['input_schema'];
      final properties = schema is Map ? schema['properties'] : null;
      final formatSchema = properties is Map ? properties['format'] : null;
      final formatEnum = formatSchema is Map ? formatSchema['enum'] : null;
      final videoPostOperations = videoPost.isEmpty
          ? const <String>[]
          : List<String>.from(
              videoPost.first['mobile_job_operations'] as List? ?? const [],
            );
      if (!mounted) return;
      setState(() {
        _analysisTools = results[0];
        _subtitleTools = results[1];
        _jobOperations = subtitleJobOperations;
        _analysisJobOperations = analysisJobOperations;
        _videoPostOperations = videoPostOperations;
        _formats = formatEnum is List
            ? formatEnum
                  .map((value) => value.toString())
                  .where((value) => value == 'srt' || value == 'vtt')
                  .toList()
            : const [];
        if (_formats.contains('srt')) _format = 'srt';
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

  Map<String, dynamic>? get _transcriber => _analysisTools
      .where((tool) => tool['tool_id'] == 'transcriber')
      .firstOrNull;

  Map<String, dynamic>? get _subtitleGenerator => _subtitleTools
      .where((tool) => tool['tool_id'] == 'subtitle_gen')
      .firstOrNull;

  Map<String, dynamic> _properties(Map<String, dynamic>? tool) {
    final schema = tool?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    return properties is Map ? Map<String, dynamic>.from(properties) : const {};
  }

  bool get _canTranscribe =>
      !_loading &&
      !_busy &&
      _transcriber?['status'] == 'available' &&
      _analysisJobOperations.contains('transcribe');

  List<String> get _transcriptionModels {
    final schema = _transcriber?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    final model = properties is Map ? properties['model_size'] : null;
    final values = model is Map ? model['enum'] : null;
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  String get _availability {
    if (_loading) return 'Loading transcription and subtitle tools.';
    if (_error != null) return 'OpenMontage registry unavailable: $_error';
    if (_subtitleGenerator?['status'] != 'available') {
      return 'Subtitle generation tool is unavailable.';
    }
    if (_jobOperations.contains('generate')) {
      return _canTranscribe
          ? 'Automatic transcription is available. Timed cues can also be edited manually.'
          : 'Automatic transcription is unavailable through mobile jobs; enter timed cues manually. Subtitle formatting is available.';
    }
    return 'Subtitle generation is not exposed by the current OpenMontage runtime.';
  }

  List<Map<String, dynamic>>? get _segments {
    final result = <Map<String, dynamic>>[];
    for (final cue in _cues) {
      final text = cue.text.text.trim();
      final start = double.tryParse(cue.start.text.trim());
      final end = double.tryParse(cue.end.text.trim());
      if (text.isEmpty ||
          start == null ||
          end == null ||
          start < 0 ||
          end <= start) {
        return null;
      }
      result.add({'text': text, 'start': start, 'end': end});
    }
    return result.isEmpty ? null : result;
  }

  bool get _canGenerate =>
      !_loading &&
      !_busy &&
      _jobOperations.contains('generate') &&
      _formats.contains(_format) &&
      _segments != null;

  Future<void> _transcribe() async {
    if (!_canTranscribe) return;
    final picked = await FilePicker.pickFiles(type: FileType.video);
    if (!mounted || picked.isEmpty || picked.first.path == null) return;
    setState(() {
      _busy = true;
      _jobError = null;
      _jobStatus = 'uploading_video';
      _subtitlePreview = null;
    });
    try {
      final projectId =
          _projectId ??
          (await BackendApi.createProject(
            name: 'Video transcription',
          ))['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      final uploaded = await BackendApi.uploadMediaAsset(
        projectId: projectId,
        file: File(picked.first.path!),
      );
      final assetId = uploaded['id']?.toString();
      if (assetId == null || assetId.isEmpty) {
        throw const FormatException('Backend returned no source asset ID.');
      }
      await LibraryStorage.upsertRemoteAsset(
        id: assetId,
        name: uploaded['name']?.toString() ?? picked.first.name,
        type: 'video',
        projectId: projectId,
        remoteUrl: BackendApi.resolveApiUrl(uploaded['file_url'].toString()),
        mimeType: uploaded['mime_type']?.toString(),
      );
      _projectId = projectId;
      _sourceAssetId = assetId;
      _sourceName = uploaded['name']?.toString() ?? picked.first.name;
      final transcriber = _transcriber;
      var job = await BackendApi.createTranscriptionJob(
        projectId: projectId,
        assetId: assetId,
        parameters: {
          'provider_tool_id':
              transcriber?['tool_id']?.toString() ?? 'transcriber',
          'model_size': _transcriptionModel,
          if (_transcriptionLanguage?.trim().isNotEmpty == true)
            'language': _transcriptionLanguage!.trim(),
          if (_properties(transcriber).containsKey('diarize'))
            'diarize': _diarize,
        },
      );
      _jobId = job['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException(
          'Backend returned no transcription job ID.',
        );
      }
      final timeout = Stopwatch()..start();
      while (timeout.elapsed < const Duration(minutes: 30)) {
        final status = job['status']?.toString() ?? 'queued';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        if (mounted) setState(() => _jobStatus = status);
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await BackendApi.getJob(_jobId!);
      }
      if (job['status'] != 'completed') {
        if (job['status'] != 'failed' && job['status'] != 'cancelled') {
          throw FormatException(
            'Transcription is still processing. Job ID: $_jobId',
          );
        }
        throw FormatException(
          job['error']?.toString() ?? 'transcription_failed',
        );
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final transcript = artifacts
          .where((item) => item['type'] == 'transcript')
          .firstOrNull;
      if (transcript == null) {
        throw const FormatException(
          'Completed job has no transcript artifact.',
        );
      }
      final json = jsonDecode(
        await BackendApi.getArtifactText(transcript['id'].toString()),
      );
      final rawSegments = json is Map ? json['segments'] : null;
      if (rawSegments is! List || rawSegments.isEmpty) {
        throw const FormatException(
          'Transcription produced no timed speech segments.',
        );
      }
      final cues = <_CueEditor>[];
      for (final raw in rawSegments.whereType<Map>()) {
        final text = raw['text']?.toString().trim() ?? '';
        final start = (raw['start'] as num?)?.toDouble();
        final end = (raw['end'] as num?)?.toDouble();
        if (text.isEmpty || start == null || end == null || end <= start) {
          continue;
        }
        cues.add(_CueEditor(text: text, start: start, end: end));
      }
      if (cues.isEmpty) {
        throw const FormatException(
          'Transcription did not return usable subtitle cues.',
        );
      }
      for (final cue in _cues) {
        cue.dispose();
      }
      _cues
        ..clear()
        ..addAll(cues);
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _subtitlePreview = 'Transcript ready · ${cues.length} timed cues';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _jobStatus = 'failed';
          _jobError = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final segments = _segments;
    if (!_canGenerate || segments == null) {
      return;
    }
    setState(() {
      _busy = true;
      _jobError = null;
      _jobStatus = 'preparing';
      _subtitlePreview = null;
    });
    try {
      final projectId =
          _projectId ??
          (await BackendApi.createProject(
            name: 'Subtitle captions',
          ))['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      _projectId = projectId;
      var job = await BackendApi.createSubtitleGenerationJob(
        projectId: projectId,
        format: _format,
        segments: segments,
      );
      _jobId = job['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no job ID.');
      }
      if (mounted) {
        setState(() => _jobStatus = job['status']?.toString() ?? 'queued');
      }
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 2)) {
        final status = job['status']?.toString() ?? 'running';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        job = await BackendApi.getJob(_jobId!);
        if (mounted) {
          setState(() => _jobStatus = job['status']?.toString() ?? 'running');
        }
      }
      if (job['status'] != 'completed') {
        throw FormatException(
          job['error']?.toString() ?? 'Subtitle job did not complete.',
        );
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final artifact = artifacts
          .where((item) => item['type'] == 'subtitle' && item['id'] != null)
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException('Completed job has no subtitle artifact.');
      }
      final preview = await BackendApi.getArtifactText(
        artifact['id'].toString(),
      );
      _subtitleArtifactId = artifact['id'].toString();
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: 'Subtitles · ${_format.toUpperCase()}',
        type: 'subtitle',
        projectId: projectId,
        remoteUrl: BackendApi.resolveApiUrl(
          artifact['download_url'].toString(),
        ),
        mimeType: artifact['mime_type']?.toString(),
      );
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _subtitlePreview = preview;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _jobStatus = 'failed';
          _jobError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _burnSubtitles() async {
    final projectId = _projectId;
    final subtitleArtifactId = _subtitleArtifactId;
    if (_burning || projectId == null || subtitleArtifactId == null) return;
    var videoAssetId = _sourceAssetId;
    var sourceName = _sourceName;
    if (videoAssetId == null) {
      final picked = await FilePicker.pickFiles(type: FileType.video);
      if (!mounted || picked.isEmpty || picked.first.path == null) return;
      sourceName = picked.first.name;
      setState(() {
        _burning = true;
        _burnError = null;
        _burnJobStatus = 'uploading video';
      });
      try {
        final source = await BackendApi.uploadMediaAsset(
          projectId: projectId,
          file: File(picked.first.path!),
        );
        videoAssetId = source['id']?.toString();
        if (videoAssetId == null || videoAssetId.isEmpty) {
          throw const FormatException('Backend returned no video asset ID.');
        }
        await LibraryStorage.upsertRemoteAsset(
          id: videoAssetId,
          name: source['name']?.toString() ?? sourceName,
          type: 'video',
          projectId: projectId,
          remoteUrl: BackendApi.resolveApiUrl(source['file_url'].toString()),
          mimeType: source['mime_type']?.toString(),
        );
        _sourceAssetId = videoAssetId;
        _sourceName = sourceName;
      } catch (error) {
        if (mounted) {
          setState(() {
            _burning = false;
            _burnJobStatus = 'failed';
            _burnError = error.toString().replaceFirst('Exception: ', '');
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _burning = true;
      _burnError = null;
      _burnJobStatus = 'uploading video';
    });
    try {
      var job = await BackendApi.createSubtitleBurnJob(
        projectId: projectId,
        videoAssetId: videoAssetId,
        subtitleArtifactId: subtitleArtifactId,
      );
      final jobId = job['id']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw const FormatException(
          'Backend returned no subtitle burn job ID.',
        );
      }
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 10)) {
        final status = job['status']?.toString() ?? 'running';
        if (mounted) setState(() => _burnJobStatus = status);
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        job = await BackendApi.getJob(jobId);
      }
      if (job['status'] != 'completed') {
        throw FormatException(
          job['error']?.toString() ?? 'Subtitle burn did not complete.',
        );
      }
      final artifacts = await BackendApi.getJobArtifacts(jobId);
      final artifact = artifacts
          .where((item) => item['type'] == 'video')
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException('The completed job has no video artifact.');
      }
      final url = BackendApi.resolveApiUrl(artifact['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: 'Subtitled video · ${sourceName ?? 'video'}',
        type: 'video',
        projectId: projectId,
        remoteUrl: url,
        mimeType: artifact['mime_type']?.toString(),
      );
      final player = VideoPlayerController.networkUrl(Uri.parse(url));
      await player.initialize();
      await _burnedVideo?.dispose();
      if (mounted) {
        setState(() {
          _burnedVideo = player;
          _burnJobStatus = 'completed';
        });
      } else {
        await player.dispose();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _burnJobStatus = 'failed';
          _burnError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _burning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transcriberAvailable = _transcriber?['status'] == 'available';
    final subtitleAvailable = _subtitleGenerator?['status'] == 'available';
    return Scaffold(
      appBar: AppBar(title: const Text('Subtitle Studio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            const Text(
              'Video → transcription → subtitles → preview → export',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  _toolTile(
                    'Transcription',
                    'transcriber',
                    _transcriber?['status']?.toString(),
                    transcriberAvailable,
                  ),
                  const Divider(height: 1),
                  _toolTile(
                    'Subtitle generation',
                    'subtitle_gen',
                    _subtitleGenerator?['status']?.toString(),
                    subtitleAvailable,
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Automatic transcription'),
                subtitle: Text(
                  _canTranscribe
                      ? 'Transcriber is available in the current runtime.'
                      : _transcriber?['status'] == 'available'
                      ? 'A transcription tool is installed, but no mobile transcription job is exposed. Enter timed cues below.'
                      : 'Transcriber is unavailable. Create subtitle files by entering timed cues below.',
                ),
              ),
            ),
            if (_transcriptionModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              const _SubtitleLabel('Whisper Model'),
              DropdownButtonFormField<String>(
                initialValue: _transcriptionModels.contains(_transcriptionModel)
                    ? _transcriptionModel
                    : _transcriptionModels.first,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _transcriptionModels
                    .map(
                      (model) =>
                          DropdownMenuItem(value: model, child: Text(model)),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(
                        () =>
                            _transcriptionModel = value ?? _transcriptionModel,
                      ),
              ),
            ],
            if (_properties(_transcriber).containsKey('language')) ...[
              const SizedBox(height: 12),
              const _SubtitleLabel('Language (optional)'),
              TextFormField(
                initialValue: _transcriptionLanguage,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Auto detect, or enter a code such as id / en',
                ),
                onChanged: (value) => _transcriptionLanguage = value,
              ),
            ],
            if (_properties(_transcriber).containsKey('diarize'))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Detect speakers'),
                value: _diarize,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _diarize = value),
              ),
            OutlinedButton.icon(
              onPressed: _canTranscribe ? _transcribe : null,
              icon: Icon(
                _busy ? Icons.hourglass_top : Icons.transcribe_outlined,
              ),
              label: Text(
                _busy ? 'Transcribing…' : 'Choose Video and Transcribe',
              ),
            ),
            if (_sourceName != null)
              ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: const Text('Transcription source'),
                subtitle: Text(_sourceName!),
              ),
            const SizedBox(height: 14),
            const _SubtitleLabel('Subtitle Format'),
            if (_formats.isEmpty)
              const Text('The subtitle tool does not advertise output formats.')
            else
              Wrap(
                spacing: 8,
                children: _formats
                    .map(
                      (format) => ChoiceChip(
                        label: Text(format.toUpperCase()),
                        selected: _format == format,
                        onSelected: (_) => setState(() => _format = format),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 16),
            const _SubtitleLabel('Timed subtitle cues'),
            for (var index = 0; index < _cues.length; index++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _cues[index].text,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Cue ${index + 1} text',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _cues[index].start,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Start (s)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cues[index].end,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'End (s)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _cues.length <= 1
                                ? null
                                : () {
                                    final removed = _cues.removeAt(index);
                                    removed.dispose();
                                    setState(() {});
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _cues.length >= 100
                    ? null
                    : () => setState(() => _cues.add(_CueEditor())),
                icon: const Icon(Icons.add),
                label: const Text('Add cue'),
              ),
            ),
            const SizedBox(height: 8),
            Text(_availability, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Burn subtitles into video'),
              subtitle: Text(
                !_videoPostOperations.contains('burn_subtitles')
                    ? 'OpenMontage caption burning is unavailable.'
                    : _subtitleArtifactId == null
                    ? 'Generate a subtitle artifact first.'
                    : 'Choose a video; FFmpeg will burn this subtitle file into it.',
              ),
              value: _burnJobStatus == 'completed',
              onChanged:
                  _videoPostOperations.contains('burn_subtitles') &&
                      _subtitleArtifactId != null &&
                      !_burning &&
                      _burnJobStatus != 'completed'
                  ? (enabled) {
                      if (enabled) _burnSubtitles();
                    }
                  : null,
            ),
            if (_burning) const LinearProgressIndicator(),
            if (_burnJobStatus != null || _burnError != null)
              Card(
                child: ListTile(
                  leading: Icon(
                    _burnJobStatus == 'completed'
                        ? Icons.check_circle_outline
                        : _burnJobStatus == 'failed'
                        ? Icons.error_outline
                        : Icons.hourglass_top,
                  ),
                  title: Text('Caption burn: ${_burnJobStatus ?? 'unknown'}'),
                  subtitle: Text(
                    _burnError ?? 'The result is saved to Library.',
                  ),
                ),
              ),
            if (_burnedVideo?.value.isInitialized == true) ...[
              const SizedBox(height: 10),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: _burnedVideo!.value.aspectRatio,
                      child: VideoPlayer(_burnedVideo!),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            final player = _burnedVideo!;
                            if (player.value.isPlaying) {
                              player.pause();
                            } else {
                              player.play();
                            }
                            setState(() {});
                          },
                          icon: Icon(
                            _burnedVideo!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            _burnedVideo!,
                            allowScrubbing: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _canGenerate ? _generate : null,
              icon: Icon(
                _busy ? Icons.hourglass_top : Icons.closed_caption_outlined,
              ),
              label: Text(
                _busy
                    ? 'Generating subtitles...'
                    : 'Generate ${_format.toUpperCase()}',
              ),
            ),
            const SizedBox(height: 10),
            if (_jobId != null || _jobError != null)
              Card(
                child: ListTile(
                  leading: Icon(
                    _jobStatus == 'completed'
                        ? Icons.check_circle_outline
                        : _jobStatus == 'failed'
                        ? Icons.error_outline
                        : Icons.hourglass_top,
                  ),
                  title: Text('Subtitle job: ${_jobStatus ?? 'unknown'}'),
                  subtitle: Text(_jobError ?? 'Job ${_jobId ?? ''}'),
                ),
              ),
            if (_subtitlePreview != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _subtitlePreview!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolTile(
    String title,
    String toolId,
    String? status,
    bool available,
  ) => ListTile(
    leading: Icon(
      available ? Icons.check_circle_outline : Icons.cloud_off_outlined,
    ),
    title: Text(title),
    subtitle: Text('$toolId · ${status ?? 'not registered'}'),
  );
}

class _CueEditor {
  _CueEditor({String text = '', double start = 0, double end = 3}) {
    this.text.text = text;
    this.start.text = start
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'\.0+$'), '');
    this.end.text = end.toStringAsFixed(3).replaceFirst(RegExp(r'\.0+$'), '');
  }

  final text = TextEditingController();
  final start = TextEditingController();
  final end = TextEditingController();

  void dispose() {
    text.dispose();
    start.dispose();
    end.dispose();
  }
}

class _SubtitleLabel extends StatelessWidget {
  const _SubtitleLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}
