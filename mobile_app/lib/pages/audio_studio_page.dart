import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/backend_api.dart';
import '../services/library_storage.dart';

class AudioStudioPage extends StatefulWidget {
  const AudioStudioPage({super.key});

  @override
  State<AudioStudioPage> createState() => _AudioStudioPageState();
}

class _AudioStudioPageState extends State<AudioStudioPage> {
  final _text = TextEditingController();
  final _musicStyleController = TextEditingController();
  final _musicTitleController = TextEditingController();
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController(text: '10');
  List<Map<String, dynamic>> _ttsProviders = [];
  List<Map<String, dynamic>> _musicProviders = [];
  List<Map<String, dynamic>> _audioTools = [];
  String _mode = 'Text to Speech';
  String? _ttsToolId;
  String? _musicToolId;
  String? _ttsModel;
  String? _ttsVoice;
  String? _ttsLanguage;
  String? _ttsFormat;
  String? _musicModel;
  String? _audioFile;
  File? _audioSource;
  String? _preset;
  String _audioOperation = 'enhance';
  double _volume = 1;
  String? _jobId;
  String? _jobStatus;
  String? _jobError;
  String? _artifactName;
  String? _artifactUrl;
  String? _playbackError;
  VideoPlayerController? _audioPlayer;
  bool _processing = false;
  List<String> _audioOperations = [];
  String? _error;
  bool _loading = true;
  double _speed = 1;
  double _musicDuration = 30;
  bool _musicInstrumental = true;
  bool _musicCustomMode = false;
  List<String> _ttsJobOperations = [];
  List<String> _musicJobOperations = [];
  double? get _trimStart => double.tryParse(_trimStartController.text);
  double? get _trimEnd => double.tryParse(_trimEndController.text);

  @override
  void initState() {
    super.initState();
    _loadRuntime();
  }

  @override
  void dispose() {
    _text.dispose();
    _musicStyleController.dispose();
    _musicTitleController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadRuntime() async {
    try {
      final values = await Future.wait([
        BackendApi.getProviders(capability: 'tts'),
        BackendApi.getProviders(capability: 'music_generation'),
        BackendApi.getProviders(capability: 'audio_processing'),
        BackendApi.getCapabilities(),
      ]);
      if (!mounted) return;
      setState(() {
        _ttsProviders = values[0];
        _musicProviders = values[1];
        _audioTools = values[2];
        final audioCapability = values[3]
            .where((item) => item['id'] == 'audio_processing')
            .firstOrNull;
        _audioOperations = List<String>.from(
          audioCapability?['mobile_job_operations'] as List? ?? const [],
        );
        final ttsCapability = values[3]
            .where((item) => item['id'] == 'tts')
            .firstOrNull;
        final musicCapability = values[3]
            .where((item) => item['id'] == 'music_generation')
            .firstOrNull;
        _ttsJobOperations = List<String>.from(
          ttsCapability?['mobile_job_operations'] as List? ?? const [],
        );
        _musicJobOperations = List<String>.from(
          musicCapability?['mobile_job_operations'] as List? ?? const [],
        );
        _audioOperation = _audioOperations.contains('enhance')
            ? 'enhance'
            : _audioOperations.contains('volume')
            ? 'volume'
            : 'enhance';
        final tts = _bestTool(_ttsProviders);
        final music = _bestTool(_musicProviders);
        _preset = _presets.firstOrNull;
        _ttsToolId = tts?['tool_id']?.toString();
        _musicToolId = music?['tool_id']?.toString();
        _ttsModel = _models(tts).firstOrNull?['id']?.toString();
        _ttsVoice =
            _schemaOptions(tts, 'voice').firstOrNull ??
            _schemaOptions(tts, 'voice_id').firstOrNull ??
            _schemaOptions(tts, 'speaker_id').firstOrNull;
        _ttsLanguage =
            _schemaOptions(tts, 'language_code').firstOrNull ??
            _schemaOptions(tts, 'voice_language').firstOrNull;
        _ttsFormat =
            _schemaOptions(tts, 'response_format').firstOrNull ??
            _schemaOptions(tts, 'format').firstOrNull;
        _musicModel =
            _schemaOptions(music, 'model').firstOrNull ??
            _models(music).firstOrNull?['id']?.toString();
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

  Map<String, dynamic>? _bestTool(List<Map<String, dynamic>> tools) =>
      tools.where((tool) => tool['status'] == 'available').firstOrNull ??
      tools.firstOrNull;

  List<Map<String, dynamic>> _models(Map<String, dynamic>? tool) {
    final values = tool?['models'];
    return values is List
        ? values.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const [];
  }

  Map<String, dynamic> _properties(Map<String, dynamic>? tool) {
    final schema = tool?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    return properties is Map ? Map<String, dynamic>.from(properties) : const {};
  }

  List<String> _schemaOptions(Map<String, dynamic>? tool, String field) {
    final values = _properties(tool)[field]?['enum'];
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  String? get _ttsVoiceField {
    final tool = _findTool(_ttsProviders, _ttsToolId);
    const fields = ['voice', 'voice_id', 'speaker_id'];
    return fields
            .where((field) => _schemaOptions(tool, field).isNotEmpty)
            .firstOrNull ??
        fields.where(_properties(tool).containsKey).firstOrNull;
  }

  String? get _ttsLanguageField {
    final tool = _findTool(_ttsProviders, _ttsToolId);
    const fields = ['language_code', 'voice_language'];
    return fields
            .where((field) => _schemaOptions(tool, field).isNotEmpty)
            .firstOrNull ??
        fields.where(_properties(tool).containsKey).firstOrNull;
  }

  String? get _ttsSpeedField => ['speed', 'speaking_rate', 'voice_speed']
      .where(_properties(_findTool(_ttsProviders, _ttsToolId)).containsKey)
      .firstOrNull;

  bool get _canGenerateTts {
    final tool = _findTool(_ttsProviders, _ttsToolId);
    final properties = _properties(tool);
    return !_loading &&
        !_processing &&
        tool?['status'] == 'available' &&
        _ttsJobOperations.contains('generate') &&
        _text.text.trim().isNotEmpty &&
        (!properties.containsKey('voice') ||
            _ttsVoice != null ||
            !_schemaOptions(tool, 'voice').isNotEmpty) &&
        (!properties.containsKey('voice_id') ||
            _ttsVoice != null ||
            !_schemaOptions(tool, 'voice_id').isNotEmpty);
  }

  bool get _canGenerateMusic {
    final tool = _findTool(_musicProviders, _musicToolId);
    final properties = _properties(tool);
    final promptSchema = properties['prompt'];
    final promptMaximum = promptSchema is Map
        ? (promptSchema['maxLength'] as num?)?.toInt()
        : null;
    final promptMinimum = promptSchema is Map
        ? (promptSchema['minLength'] as num?)?.toInt()
        : null;
    final customRequiredOkay =
        (!_musicCustomMode ||
            !properties.containsKey('style') ||
            _musicStyleController.text.trim().isNotEmpty) &&
        (!_musicCustomMode ||
            !properties.containsKey('title') ||
            _musicTitleController.text.trim().isNotEmpty);
    return !_loading &&
        !_processing &&
        tool?['status'] == 'available' &&
        _musicJobOperations.contains('generate') &&
        _text.text.trim().isNotEmpty &&
        (promptMaximum == null || _text.text.trim().length <= promptMaximum) &&
        (promptMinimum == null || _text.text.trim().length >= promptMinimum) &&
        customRequiredOkay &&
        (!properties.containsKey('duration_seconds') || _musicDuration > 0) &&
        (!properties.containsKey('duration') || _musicDuration > 0) &&
        (properties.containsKey('output_path'));
  }

  Map<String, dynamic>? _findTool(
    List<Map<String, dynamic>> tools,
    String? id,
  ) => tools.where((tool) => tool['tool_id'] == id).firstOrNull;

  Future<void> _pickAudio() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (!mounted || result.isEmpty) return;
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    setState(() {
      _audioFile = result.first.name;
      _audioSource = result.first.path == null
          ? null
          : File(result.first.path!);
      _jobId = null;
      _jobStatus = null;
      _artifactName = null;
      _artifactUrl = null;
      _playbackError = null;
      _jobError = null;
    });
  }

  Map<String, dynamic>? get _audioEnhancer => _audioTools
      .where((tool) => tool['tool_id'] == 'audio_enhance')
      .firstOrNull;

  List<String> get _presets {
    final schema = _audioEnhancer?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    final preset = properties is Map ? properties['preset'] : null;
    final values = preset is Map ? preset['enum'] : null;
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  bool get _canProcess =>
      !_processing &&
      _audioSource != null &&
      _audioOperations.contains(_audioOperation) &&
      (_audioOperation == 'volume' ||
          (_audioOperation == 'trim' &&
              _trimStart != null &&
              _trimEnd != null &&
              _trimStart! >= 0 &&
              _trimEnd! > _trimStart!) ||
          (_audioEnhancer?['status'] == 'available' &&
              _audioOperation == 'enhance' &&
              _presets.contains(_preset)));

  Future<void> _runTts() async {
    if (!_canGenerateTts) return;
    final tool = _findTool(_ttsProviders, _ttsToolId)!;
    final properties = _properties(tool);
    setState(() {
      _processing = true;
      _jobError = null;
      _playbackError = null;
      _jobId = null;
      _jobStatus = 'creating_project';
      _artifactName = null;
      _artifactUrl = null;
    });
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    try {
      final project = await BackendApi.createProject(
        name:
            'Speech · ${_text.text.trim().split(RegExp(r'\s+')).take(5).join(' ')}',
      );
      final projectId = project['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      final parameters = <String, dynamic>{
        'provider_tool_id': _ttsToolId,
        'text': _text.text.trim(),
        if (_ttsModel != null) 'model_id': _ttsModel,
        if (_ttsVoiceField != null && _ttsVoice != null)
          _ttsVoiceField!: _ttsVoiceField == 'speaker_id'
              ? int.tryParse(_ttsVoice!)
              : _ttsVoice,
        if (_ttsLanguageField != null && _ttsLanguage != null)
          _ttsLanguageField!: _ttsLanguage,
        ...?(_ttsSpeedField == null
            ? null
            : <String, dynamic>{_ttsSpeedField!: _speed}),
        if (_ttsFormat != null) ...{
          if (properties.containsKey('response_format'))
            'response_format': _ttsFormat,
          if (!properties.containsKey('response_format') &&
              properties.containsKey('format'))
            'format': _ttsFormat,
        },
      };
      setState(() => _jobStatus = 'submitting');
      var job = await BackendApi.createTtsGenerationJob(
        projectId: projectId,
        parameters: parameters,
      );
      _jobId = job['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no TTS job ID.');
      }
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 10)) {
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
          throw FormatException('TTS is still processing. Job ID: $_jobId');
        }
        throw FormatException(job['error']?.toString() ?? 'generation_failed');
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final artifact = artifacts
          .where(
            (item) => item['type'] == 'audio' && item['download_url'] != null,
          )
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException('Completed TTS job has no audio artifact.');
      }
      final url = BackendApi.resolveApiUrl(artifact['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: 'Narration · ${artifact['metadata']?['format'] ?? 'audio'}',
        type: 'audio',
        projectId: projectId,
        remoteUrl: url,
        mimeType: artifact['mime_type']?.toString(),
      );
      VideoPlayerController? player;
      String? playbackError;
      try {
        player = VideoPlayerController.networkUrl(Uri.parse(url));
        await player.initialize();
        player.addListener(_onAudioPlaybackChanged);
      } catch (error) {
        playbackError = 'TTS artifact is ready, but playback failed: $error';
        await player?.dispose();
        player = null;
      }
      await _audioPlayer?.dispose();
      _audioPlayer = player;
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _artifactName =
              artifact['metadata']?['format']?.toString() ?? 'audio';
          _artifactUrl = url;
          _playbackError = playbackError;
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
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _runMusic() async {
    if (!_canGenerateMusic) return;
    final tool = _findTool(_musicProviders, _musicToolId)!;
    final properties = _properties(tool);
    setState(() {
      _processing = true;
      _jobError = null;
      _playbackError = null;
      _jobId = null;
      _jobStatus = 'creating_project';
      _artifactName = null;
      _artifactUrl = null;
    });
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    try {
      final prompt = _text.text.trim();
      final project = await BackendApi.createProject(
        name: 'Music · ${prompt.split(RegExp(r'\s+')).take(5).join(' ')}',
      );
      final projectId = project['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      final parameters = <String, dynamic>{
        'provider_tool_id': _musicToolId,
        'prompt': prompt,
        if (_musicModel != null) ...{
          if (properties.containsKey('model')) 'model': _musicModel,
          if (properties.containsKey('model_id')) 'model_id': _musicModel,
        },
        if (properties.containsKey('duration_seconds'))
          'duration_seconds': _musicDuration,
        if (!properties.containsKey('duration_seconds') &&
            properties.containsKey('duration'))
          'duration_seconds': _musicDuration,
        if (properties.containsKey('instrumental'))
          'instrumental': _musicInstrumental,
        if (properties.containsKey('force_instrumental'))
          'force_instrumental': _musicInstrumental,
        if (properties.containsKey('custom_mode'))
          'custom_mode': _musicCustomMode,
        if (properties.containsKey('style') &&
            _musicStyleController.text.trim().isNotEmpty)
          'style': _musicStyleController.text.trim(),
        if (properties.containsKey('title') &&
            _musicTitleController.text.trim().isNotEmpty)
          'title': _musicTitleController.text.trim(),
      };
      setState(() => _jobStatus = 'submitting');
      var job = await BackendApi.createMusicGenerationJob(
        projectId: projectId,
        parameters: parameters,
      );
      _jobId = job['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no music job ID.');
      }
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 10)) {
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
          throw FormatException('Music is still processing. Job ID: $_jobId');
        }
        throw FormatException(job['error']?.toString() ?? 'generation_failed');
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final artifact = artifacts
          .where(
            (item) => item['type'] == 'audio' && item['download_url'] != null,
          )
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException(
          'Completed music job has no audio artifact.',
        );
      }
      final url = BackendApi.resolveApiUrl(artifact['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: 'Music · ${artifact['metadata']?['format'] ?? 'audio'}',
        type: 'audio',
        projectId: projectId,
        remoteUrl: url,
        mimeType: artifact['mime_type']?.toString(),
      );
      VideoPlayerController? player;
      String? playbackError;
      try {
        player = VideoPlayerController.networkUrl(Uri.parse(url));
        await player.initialize();
        player.addListener(_onAudioPlaybackChanged);
      } catch (error) {
        playbackError = 'Music artifact is ready, but playback failed: $error';
        await player?.dispose();
        player = null;
      }
      await _audioPlayer?.dispose();
      _audioPlayer = player;
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _artifactName =
              artifact['metadata']?['format']?.toString() ?? 'audio';
          _artifactUrl = url;
          _playbackError = playbackError;
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
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _runEnhancement() async {
    final file = _audioSource;
    final preset = _preset;
    if (!_canProcess ||
        file == null ||
        (_audioOperation == 'enhance' && preset == null)) {
      return;
    }
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    setState(() {
      _processing = true;
      _jobError = null;
      _jobStatus = 'preparing';
      _artifactName = null;
      _artifactUrl = null;
      _playbackError = null;
    });
    try {
      final project = await BackendApi.createProject(
        name: 'Audio enhancement · ${_audioFile ?? 'Audio'}',
      );
      final projectId = project['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      final asset = await BackendApi.uploadAudioAsset(
        projectId: projectId,
        file: file,
      );
      final assetId = asset['id']?.toString();
      if (assetId == null || assetId.isEmpty) {
        throw const FormatException('Backend returned no audio asset ID.');
      }
      await LibraryStorage.upsertRemoteAsset(
        id: assetId,
        name: asset['name']?.toString() ?? file.uri.pathSegments.last,
        type: 'audio',
        projectId: projectId,
        remoteUrl: BackendApi.resolveApiUrl(asset['file_url'].toString()),
        mimeType: asset['mime_type']?.toString(),
      );
      var job = switch (_audioOperation) {
        'enhance' => await BackendApi.createAudioEnhancementJob(
          projectId: projectId,
          assetId: assetId,
          preset: preset!,
        ),
        'volume' => await BackendApi.createAudioVolumeJob(
          projectId: projectId,
          assetId: assetId,
          volume: _volume,
        ),
        'trim' => await BackendApi.createAudioTrimJob(
          projectId: projectId,
          assetId: assetId,
          startSeconds: _trimStart!,
          endSeconds: _trimEnd!,
        ),
        _ => throw StateError('Unsupported audio operation.'),
      };
      _jobId = job['id']?.toString();
      if (_jobId == null || _jobId!.isEmpty) {
        throw const FormatException('Backend returned no job ID.');
      }
      if (mounted) {
        setState(() => _jobStatus = job['status']?.toString() ?? 'queued');
      }
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
          setState(() => _jobStatus = job['status']?.toString() ?? 'running');
        }
      }
      if (job['status'] != 'completed') {
        throw FormatException(
          job['error']?.toString() ?? 'Audio enhancement job did not complete.',
        );
      }
      final artifacts = await BackendApi.getJobArtifacts(_jobId!);
      final artifact = artifacts
          .where(
            (item) => item['type'] == 'audio' && item['download_url'] != null,
          )
          .firstOrNull;
      if (artifact == null) {
        throw const FormatException('Completed job has no audio artifact.');
      }
      final artifactUrl = BackendApi.resolveApiUrl(
        artifact['download_url'].toString(),
      );
      await LibraryStorage.upsertRemoteAsset(
        id: artifact['id'].toString(),
        name: 'Processed audio · ${artifact['metadata']?['format'] ?? 'audio'}',
        type: 'audio',
        projectId: projectId,
        remoteUrl: artifactUrl,
        mimeType: artifact['mime_type']?.toString(),
      );
      VideoPlayerController? player;
      String? playbackError;
      try {
        player = VideoPlayerController.networkUrl(Uri.parse(artifactUrl));
        await player.initialize();
        player.addListener(_onAudioPlaybackChanged);
      } catch (error) {
        playbackError = 'Audio artifact is ready, but playback failed: $error';
        await player?.dispose();
        player = null;
      }
      await _audioPlayer?.dispose();
      _audioPlayer = player;
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _artifactName =
              artifact['metadata']?['format']?.toString() ??
              artifactUrl.split('/').last;
          _artifactUrl = artifactUrl;
          _playbackError = playbackError;
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
      if (mounted) setState(() => _processing = false);
    }
  }

  void _onAudioPlaybackChanged() {
    if (mounted) setState(() {});
  }

  String get _status {
    if (_loading) return 'Loading OpenMontage audio tools.';
    if (_error != null) return 'Audio capability registry unavailable: $_error';
    if (_mode == 'Text to Speech') {
      final tool = _findTool(_ttsProviders, _ttsToolId);
      if (tool == null) return 'No OpenMontage TTS provider is registered.';
      if (tool['status'] != 'available') {
        return 'Selected TTS provider is not configured.';
      }
      if (!_ttsJobOperations.contains('generate')) {
        return 'TTS is not available through the mobile job API.';
      }
      return _text.text.trim().isEmpty
          ? 'Enter narration text to prepare a real TTS job.'
          : 'TTS is ready to create a speech artifact.';
    }
    if (_mode == 'Music') {
      final tool = _findTool(_musicProviders, _musicToolId);
      if (tool == null) {
        return 'No OpenMontage music generation provider is registered.';
      }
      if (tool['status'] != 'available') {
        return 'Selected music provider is not configured.';
      }
      if (!_musicJobOperations.contains('generate')) {
        return 'Music generation is not available through the mobile job API.';
      }
      return _canGenerateMusic
          ? 'Ready to create a real music generation job.'
          : 'Enter a prompt and complete the selected provider requirements.';
    }
    if (_audioTools.isEmpty) return 'No audio processing tool is registered.';
    if (!_audioTools.any((tool) => tool['status'] == 'available')) {
      return 'Audio processing tools are unavailable on this backend.';
    }
    if (!_audioOperations.contains(_audioOperation)) {
      return 'The selected audio operation is not available through the mobile job API.';
    }
    return switch (_audioOperation) {
      'volume' => 'Volume adjustment is ready when an audio file is selected.',
      'trim' => 'Audio trim is ready when an audio file and valid time range are selected.',
      _ => 'Audio enhancement is ready when an audio file and supported preset are selected.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final tts = _findTool(_ttsProviders, _ttsToolId);
    final music = _findTool(_musicProviders, _musicToolId);
    final selectedTool = _mode == 'Text to Speech' ? tts : music;
    final models = _models(selectedTool);
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Studio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Text to Speech',
                  icon: Icon(Icons.record_voice_over_outlined),
                  label: Text('TTS'),
                ),
                ButtonSegment(
                  value: 'Processing',
                  icon: Icon(Icons.graphic_eq_outlined),
                  label: Text('Process'),
                ),
                ButtonSegment(
                  value: 'Music',
                  icon: Icon(Icons.music_note_outlined),
                  label: Text('Music'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: Icon(
                  _mode == 'Text to Speech'
                      ? Icons.record_voice_over_outlined
                      : _mode == 'Music'
                      ? Icons.music_note_outlined
                      : Icons.graphic_eq_outlined,
                ),
                title: Text(_status),
                subtitle: Text(
                  _loading ? 'Checking OpenMontage runtime registry.' : 'Execution state is reported by backend registry and mobile job support.',
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_mode == 'Text to Speech') ...[
              const _AudioLabel('Text'),
              TextField(
                key: const ValueKey('ttsTextField'),
                controller: _text,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() => _jobError = null),
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter narration text...',
                ),
              ),
              const SizedBox(height: 12),
              if (_ttsVoiceField != null) ...[
                const SizedBox(height: 12),
                const _AudioLabel('Voice'),
                _schemaValueSelector(
                  selectedTool,
                  _ttsVoiceField!,
                  _ttsVoice,
                  (value) => setState(() => _ttsVoice = value),
                ),
              ],
              if (_ttsLanguageField != null) ...[
                const SizedBox(height: 12),
                const _AudioLabel('Language'),
                _schemaValueSelector(
                  selectedTool,
                  _ttsLanguageField!,
                  _ttsLanguage,
                  (value) => setState(() => _ttsLanguage = value),
                ),
              ],
              const SizedBox(height: 12),
              const _AudioLabel('Provider'),
              _providerSelector(_ttsProviders, _ttsToolId, (value) {
                setState(() {
                  _ttsToolId = value;
                  final provider = _findTool(_ttsProviders, value);
                  _ttsModel = _models(provider).firstOrNull?['id']?.toString();
                  _ttsVoice =
                      _schemaOptions(provider, 'voice').firstOrNull ??
                      _schemaOptions(provider, 'voice_id').firstOrNull ??
                      _schemaOptions(provider, 'speaker_id').firstOrNull;
                  _ttsLanguage =
                      _schemaOptions(provider, 'language_code').firstOrNull ??
                      _schemaOptions(provider, 'voice_language').firstOrNull;
                  _ttsFormat =
                      _schemaOptions(provider, 'response_format').firstOrNull ??
                      _schemaOptions(provider, 'format').firstOrNull;
                  _speed = 1;
                });
              }),
              const SizedBox(height: 12),
              const _AudioLabel('Model'),
              if (models.isEmpty &&
                  _properties(tts)['model'] is Map &&
                  (_properties(tts)['model'] as Map)['default'] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (_properties(tts)['model'] as Map)['default'].toString(),
                  ),
                  subtitle: const Text('Provider default model'),
                )
              else
                _modelSelector(
                  models,
                  _ttsModel,
                  (value) => setState(() => _ttsModel = value),
                  tts?['status'] == 'available',
                ),
              if (_ttsSpeedField != null) ...[
                const SizedBox(height: 12),
                _ttsSpeedControl(selectedTool, _ttsSpeedField!),
              ],
              if (_schemaOptions(selectedTool, 'response_format').isNotEmpty ||
                  _schemaOptions(selectedTool, 'format').isNotEmpty) ...[
                const SizedBox(height: 12),
                const _AudioLabel('Output Format'),
                DropdownButtonFormField<String>(
                  initialValue:
                      _schemaOptions(
                            selectedTool,
                            'response_format',
                          ).contains(_ttsFormat) ||
                          _schemaOptions(
                            selectedTool,
                            'format',
                          ).contains(_ttsFormat)
                      ? _ttsFormat
                      : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items:
                      (_schemaOptions(
                                selectedTool,
                                'response_format',
                              ).isNotEmpty
                              ? _schemaOptions(selectedTool, 'response_format')
                              : _schemaOptions(selectedTool, 'format'))
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toUpperCase()),
                            ),
                          )
                          .toList(),
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _ttsFormat = value),
                ),
              ],
            ] else if (_mode == 'Music') ...[
              _AudioLabel(_musicCustomMode ? 'Lyrics' : 'Music Prompt'),
              TextField(
                key: const ValueKey('musicPromptField'),
                controller: _text,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: _musicCustomMode
                      ? 'Write the lyrics for the song...'
                      : 'Describe mood, genre, instruments, and tempo...',
                ),
              ),
              const SizedBox(height: 12),
              if (_properties(music).containsKey('duration_seconds') ||
                  _properties(music).containsKey('duration')) ...[
                _AudioLabel('Duration · ${_musicDuration.round()} seconds'),
                Slider(
                  value: _musicDuration.clamp(
                    ((_properties(music)['duration_seconds'] ??
                                    _properties(music)['duration'])['minimum']
                                as num?)
                            ?.toDouble() ??
                        3,
                    ((_properties(music)['duration_seconds'] ??
                                    _properties(music)['duration'])['maximum']
                                as num?)
                            ?.toDouble() ??
                        600,
                  ),
                  min:
                      ((_properties(music)['duration_seconds'] ??
                                  _properties(music)['duration'])['minimum']
                              as num?)
                          ?.toDouble() ??
                      3,
                  max:
                      ((_properties(music)['duration_seconds'] ??
                                  _properties(music)['duration'])['maximum']
                              as num?)
                          ?.toDouble() ??
                      600,
                  divisions: 60,
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _musicDuration = value),
                ),
              ],
              if (_properties(music).containsKey('instrumental') ||
                  _properties(music).containsKey('force_instrumental'))
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Instrumental'),
                  subtitle: const Text('Generate without vocals'),
                  value: _musicInstrumental,
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _musicInstrumental = value),
                ),
              if (_properties(music).containsKey('custom_mode'))
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom lyrics mode'),
                  subtitle: const Text('Use the prompt above as exact lyrics'),
                  value: _musicCustomMode,
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _musicCustomMode = value),
                ),
              if (_properties(music).containsKey('style')) ...[
                const _AudioLabel('Style'),
                TextField(
                  controller: _musicStyleController,
                  enabled: !_processing,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Genre or musical style',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (_properties(music).containsKey('title')) ...[
                const _AudioLabel('Track title'),
                TextField(
                  controller: _musicTitleController,
                  enabled: !_processing,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Optional title',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (_schemaOptions(music, 'model').isNotEmpty) ...[
                const _AudioLabel('Model'),
                DropdownButtonFormField<String>(
                  initialValue:
                      _schemaOptions(music, 'model').contains(_musicModel)
                      ? _musicModel
                      : _schemaOptions(music, 'model').firstOrNull,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _schemaOptions(music, 'model')
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _musicModel = value),
                ),
                const SizedBox(height: 12),
              ],
              const _AudioLabel('Provider'),
              _providerSelector(_musicProviders, _musicToolId, (value) {
                setState(() {
                  _musicToolId = value;
                  final selected = _findTool(_musicProviders, value);
                  _musicModel =
                      _schemaOptions(selected, 'model').firstOrNull ??
                      _models(selected).firstOrNull?['id']?.toString();
                });
              }),
              const SizedBox(height: 12),
              if (_schemaOptions(music, 'model').isEmpty &&
                  models.isNotEmpty) ...[
                const _AudioLabel('Model'),
                _modelSelector(
                  models,
                  _musicModel,
                  (value) => setState(() => _musicModel = value),
                  music?['status'] == 'available',
                ),
              ],
            ] else ...[
              if (_audioOperations.isNotEmpty) ...[
                SegmentedButton<String>(
                  segments: [
                    if (_audioOperations.contains('enhance'))
                      const ButtonSegment(
                        value: 'enhance',
                        label: Text('Enhance'),
                      ),
                    if (_audioOperations.contains('volume'))
                      const ButtonSegment(
                        value: 'volume',
                        label: Text('Volume'),
                      ),
                    if (_audioOperations.contains('trim'))
                      const ButtonSegment(value: 'trim', label: Text('Trim')),
                  ],
                  selected: {_audioOperation},
                  onSelectionChanged: (values) =>
                      setState(() => _audioOperation = values.first),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _pickAudio,
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(_audioFile ?? 'Choose Audio File'),
              ),
              if (_audioOperation == 'volume') ...[
                _AudioLabel('Volume ${(_volume * 100).round()}%'),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _volume = value),
                ),
              ],
              if (_audioOperation == 'trim') ...[
                const _AudioLabel('Trim range · seconds'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _trimStartController,
                        enabled: !_processing,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Start',
                          suffixText: 'sec',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _trimEndController,
                        enabled: !_processing,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'End',
                          suffixText: 'sec',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
              if (_audioOperation == 'enhance' && _presets.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _AudioLabel('Enhancement preset'),
                DropdownButtonFormField<String>(
                  initialValue: _presets.contains(_preset) ? _preset : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _presets
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset,
                          child: Text(preset),
                        ),
                      )
                      .toList(),
                  onChanged: _processing
                      ? null
                      : (value) => setState(() => _preset = value),
                ),
              ],
              const SizedBox(height: 12),
              const _AudioLabel('OpenMontage Audio Tools'),
              if (_loading)
                const LinearProgressIndicator()
              else if (_audioTools.isEmpty)
                const Text('No audio processing tools are registered.')
              else
                ..._audioTools.map((tool) {
                  final operations = List<String>.from(
                    tool['operations'] as List? ?? const [],
                  );
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        tool['status'] == 'available'
                            ? Icons.check_circle_outline
                            : Icons.cloud_off_outlined,
                      ),
                      title: Text(tool['tool_id']?.toString() ?? 'Audio tool'),
                      subtitle: Text(
                        '${tool['status'] ?? 'unknown'} · ${operations.isEmpty ? 'No operation declared' : operations.join(', ')}',
                      ),
                    ),
                  );
                }),
              if (_audioFile != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.audio_file_outlined),
                    title: Text(
                      _audioFile!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text(
                      'Selected locally; the file is uploaded when you run the selected audio operation.',
                    ),
                  ),
                ),
              ],
              if (_jobId != null || _jobError != null) ...[
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: Icon(
                      _jobStatus == 'completed'
                          ? Icons.check_circle_outline
                          : _jobStatus == 'failed'
                          ? Icons.error_outline
                          : Icons.hourglass_top,
                    ),
                    title: Text('Audio job: ${_jobStatus ?? 'unknown'}'),
                    subtitle: Text(
                      _jobError ??
                          (_artifactName == null
                              ? 'Job ${_jobId!}'
                              : 'Audio artifact ready · ${_artifactName!}'),
                    ),
                  ),
                ),
              ],
              if (_artifactUrl != null) ...[
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _mode == 'Text to Speech'
                              ? 'Generated Speech'
                              : _mode == 'Music'
                              ? 'Generated Music'
                              : _audioOperation == 'volume'
                              ? 'Adjusted Audio'
                              : 'Enhanced Audio',
                        ),
                        const SizedBox(height: 12),
                        if (_playbackError != null)
                          Text(_playbackError!)
                        else if (_audioPlayer?.value.isInitialized == true) ...[
                          VideoProgressIndicator(
                            _audioPlayer!,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              bufferedColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.25),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton.filled(
                                onPressed: () => _audioPlayer!.value.isPlaying
                                    ? _audioPlayer!.pause()
                                    : _audioPlayer!.play(),
                                icon: Icon(
                                  _audioPlayer!.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(_audioPlayer!.value.position),
                              ),
                              const Spacer(),
                              Text(
                                _formatDuration(_audioPlayer!.value.duration),
                              ),
                            ],
                          ),
                        ] else
                          const Text('Loading audio player…'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _mode == 'Processing'
                  ? (_canProcess ? _runEnhancement : null)
                  : _mode == 'Text to Speech'
                  ? (_canGenerateTts ? _runTts : null)
                  : _mode == 'Music'
                  ? (_canGenerateMusic ? _runMusic : null)
                  : null,
              icon: Icon(_processing ? Icons.hourglass_top : Icons.play_arrow),
              label: Text(
                _processing
                    ? (_mode == 'Text to Speech'
                          ? 'Generating Speech…'
                          : 'Processing audio…')
                    : _mode == 'Text to Speech' && _canGenerateTts
                    ? 'Generate Speech'
                    : _mode == 'Music' && _canGenerateMusic
                    ? 'Generate Music'
                    : _mode == 'Processing' && _canProcess
                    ? (_audioOperation == 'volume'
                          ? 'Apply Volume'
                          : _audioOperation == 'trim'
                          ? 'Trim Audio'
                          : 'Enhance Audio')
                    : 'Run $_mode · Coming Soon',
              ),
            ),
            const SizedBox(height: 8),
            const Card(
              child: ListTile(
                leading: Icon(Icons.multitrack_audio_outlined),
                title: Text('Audio artifact'),
                subtitle: Text(
                  'Completed audio jobs are saved to the project and Library with a playable result.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _providerSelector(
    List<Map<String, dynamic>> providers,
    String? selectedId,
    ValueChanged<String?> onChanged,
  ) {
    if (_loading) return const LinearProgressIndicator();
    if (_error != null) return Text(_error!);
    if (providers.isEmpty) return const Text('No provider is registered.');
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: providers.map((provider) {
        final id = provider['tool_id']?.toString() ?? '';
        final name = provider['provider_id']?.toString() ?? id;
        return DropdownMenuItem(
          value: id,
          child: Text(
            '$name · ${provider['status'] ?? 'unknown'}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _modelSelector(
    List<Map<String, dynamic>> models,
    String? selectedId,
    ValueChanged<String?> onChanged,
    bool providerAvailable,
  ) {
    if (models.isEmpty) {
      return const Text('No model is advertised by this provider.');
    }
    return DropdownButtonFormField<String>(
      initialValue: models.any((model) => model['id'] == selectedId)
          ? selectedId
          : null,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: models.map((model) {
        final id = model['id']?.toString() ?? '';
        return DropdownMenuItem(
          value: id,
          child: Text(
            '${model['name'] ?? id} · ${model['status'] ?? 'unknown'}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: providerAvailable ? onChanged : null,
    );
  }

  Widget _schemaValueSelector(
    Map<String, dynamic>? tool,
    String field,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    final options = _schemaOptions(tool, field);
    if (options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(),
        onChanged: _processing ? null : onChanged,
      );
    }
    return TextFormField(
      key: ValueKey('tts_${field}_field'),
      initialValue: value,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: field == 'voice' || field == 'voice_id'
            ? 'Provider voice'
            : 'Language code',
      ),
      onChanged: _processing ? null : onChanged,
    );
  }

  Widget _ttsSpeedControl(Map<String, dynamic>? tool, String field) {
    final raw = _properties(tool)[field];
    final schema = raw is Map ? raw : const <String, dynamic>{};
    final minimum = (schema['minimum'] as num?)?.toDouble() ?? 0.25;
    final maximum = (schema['maximum'] as num?)?.toDouble() ?? 2.0;
    final value = _speed.clamp(minimum, maximum).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AudioLabel('Speed · ${value.toStringAsFixed(2)}'),
        Slider(
          value: value,
          min: minimum,
          max: maximum,
          divisions: 10,
          onChanged: _processing
              ? null
              : (next) => setState(() => _speed = next),
        ),
      ],
    );
  }
}

class _AudioLabel extends StatelessWidget {
  const _AudioLabel(this.text);

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
