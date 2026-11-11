import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/feature_catalog.dart';
import '../services/backend_api.dart';
import '../services/library_storage.dart';
import '../services/project_storage.dart';

class AiVideoGeneratorPage extends StatefulWidget {
  const AiVideoGeneratorPage({
    super.key,
    this.initialProject,
    this.workflowId,
    this.pipelineId,
    this.templateId,
  });
  final Map<String, dynamic>? initialProject;
  final String? workflowId, pipelineId, templateId;

  @override
  State<AiVideoGeneratorPage> createState() => _AiVideoGeneratorPageState();
}

class _AiVideoGeneratorPageState extends State<AiVideoGeneratorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prompt;
  late final TextEditingController _project;
  final _negative = TextEditingController();
  final _seed = TextEditingController();
  String _mode = 'Text to Video', _style = 'Cinematic';
  String _executionMode = 'huggingface';
  int _duration = 5, _fps = 24;
  int _inferenceSteps = 20;
  String _ratio = '16:9', _resolution = '720p', _seedMode = 'Auto';
  double _guidance = 7;
  bool _advanced = false, _submitted = false;
  String? _generationError;
  String? _template;
  List<Map<String, dynamic>> _providerTools = [];
  List<String> _mobileJobOperations = [];
  String? _selectedProviderToolId;
  String? _selectedModelId;
  String? _registryError;
  Map<String, dynamic>? _hardware;
  String? _hardwareError;
  bool _registryLoading = true;
  bool _generating = false;
  String? _generationJobId;
  String? _generationStatus;
  String? _videoPlaybackError;
  VideoPlayerController? _generatedVideo;
  final List<Map<String, String>> _assets = [];

  @override
  void initState() {
    super.initState();
    final old = widget.initialProject ?? {};
    _prompt = TextEditingController(text: old['prompt']?.toString() ?? '');
    _project = TextEditingController(
      text: old['title']?.toString() ?? 'Untitled Video',
    );
    _style = old['style']?.toString() ?? _style;
    _duration =
        int.tryParse(
          (old['duration']?.toString() ?? '5').replaceAll('s', ''),
        ) ??
        5;
    _ratio = old['aspectRatio']?.toString() ?? _ratio;
    _mode = old['mode']?.toString() ?? _mode;
    _resolution = old['resolution']?.toString() ?? _resolution;
    _fps = (old['fps'] as num?)?.toInt() ?? _fps;
    final templateParameters = Map<String, dynamic>.from(
      old['templateParameters'] as Map? ?? const {},
    );
    _ratio = templateParameters['aspectRatio'] as String? ?? _ratio;
    _resolution = templateParameters['resolution'] as String? ?? _resolution;
    _fps = (templateParameters['fps'] as num?)?.toInt() ?? _fps;
    _mode = templateParameters['mode'] as String? ?? _mode;
    if (old['seed'] is num) {
      _seedMode = 'Custom seed';
      _seed.text = old['seed'].toString();
    }
    _loadRuntimeOptions();
  }

  Future<void> _loadRuntimeOptions() async {
    try {
      final providers = await BackendApi.getProviders(
        capability: 'video_generation',
      );
      final capabilities = await BackendApi.getCapabilities();
      final capability = capabilities.where(
        (item) => item['id'] == 'video_generation',
      );
      final mobileOperations = capability.isEmpty
          ? const <String>[]
          : List<String>.from(
              capability.first['mobile_job_operations'] as List? ?? const [],
            );
      if (!mounted) return;
      setState(() {
        _providerTools = providers;
        _mobileJobOperations = mobileOperations;
        _registryLoading = false;
      });
      await _loadHostHardware();
      if (!mounted) return;
      final cloud = providers.where(
        (item) => item['provider_id'] == 'huggingface',
      );
      final usableCloud = cloud.where((item) => item['status'] == 'available');
      final local = providers.where((item) => item['runtime'] == 'local_gpu');
      final compatibleLocal = local.where(_isLocalProviderReady);
      final initial =
          usableCloud.firstOrNull ??
          compatibleLocal.firstOrNull ??
          cloud.firstOrNull ??
          local.firstOrNull;
      setState(() {
        _executionMode = initial?['provider_id'] == 'huggingface'
            ? 'huggingface'
            : 'local_gpu';
        _selectedProviderToolId = initial?['tool_id']?.toString();
        _selectedModelId = _modelForProvider(initial)?['id']?.toString();
        _syncModelDefaults(_modelForProvider(initial));
        _fps = (_selectedModel?['fps'] as num?)?.toInt() ?? _fps;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _registryError = error.toString().replaceFirst('FormatException: ', '');
        _registryLoading = false;
      });
    }
  }

  Future<void> _loadHostHardware() async {
    try {
      final hardware = await BackendApi.getRuntimeHardware();
      if (mounted) setState(() => _hardware = hardware);
    } catch (error) {
      if (mounted) {
        setState(
          () => _hardwareError = error.toString().replaceFirst(
            'FormatException: ',
            '',
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _modelsFor(Map<String, dynamic>? provider) {
    final values = provider?['models'];
    return values is List
        ? values.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const [];
  }

  Map<String, dynamic>? _modelForProvider(Map<String, dynamic>? provider) {
    final models = _modelsFor(provider);
    if (provider?['runtime'] == 'local_gpu') {
      for (final model in models) {
        if (_isLocalModelReady(provider, model['id']?.toString())) return model;
      }
    }
    return models.firstOrNull;
  }

  void _syncModelDefaults(Map<String, dynamic>? model) {
    final defaultDuration = model?['default_duration_seconds'];
    if (defaultDuration is num) _duration = defaultDuration.toInt();
    final durationOptions = model?['duration_options'];
    if (durationOptions is List && durationOptions.isNotEmpty) {
      final choices = durationOptions
          .map((value) => (value as num).toInt())
          .toList();
      if (!choices.contains(_duration)) _duration = choices.first;
    } else if (!_durationOptions.contains(_duration)) {
      _duration = _durationOptions.firstOrNull ?? _duration;
    }
    if (model?['fps'] is num) _fps = (model!['fps'] as num).toInt();
    if (model?['resolution'] is String) {
      _resolution = model!['resolution'] as String;
    } else if (model?['default_width'] is num &&
        model?['default_height'] is num) {
      _resolution = '${model!['default_width']}x${model['default_height']}';
    }
    if (model?['aspect_ratio'] is String) {
      _ratio = model!['aspect_ratio'] as String;
    } else if (model?['default_width'] is num &&
        model?['default_height'] is num) {
      _ratio = '${model!['default_width']}:${model['default_height']}';
    }
  }

  Map<String, dynamic>? get _selectedProvider {
    for (final provider in _providerTools) {
      if (provider['tool_id'] == _selectedProviderToolId) return provider;
    }
    return null;
  }

  List<Map<String, dynamic>> get _providersForSelection => _providerTools
      .where(
        (provider) => _executionMode == 'huggingface'
            ? provider['provider_id'] == 'huggingface'
            : provider['runtime'] == 'local_gpu',
      )
      .toList();

  bool _isLocalProviderReady(Map<String, dynamic> provider) {
    final providers = _hardware?['local_video_providers'];
    if (providers is! List) return false;
    return providers.whereType<Map>().any(
      (item) =>
          item['tool_id'] == provider['tool_id'] && item['status'] == 'ready',
    );
  }

  bool _isLocalModelReady(Map<String, dynamic>? provider, String? modelId) {
    final local = _localProviderHardware(provider);
    final localModels = local?['models'];
    if (localModels is List && modelId != null) {
      for (final model in localModels.whereType<Map>()) {
        if (model['model_id'] == modelId) return model['status'] == 'ready';
      }
    }
    return local?['status'] == 'ready';
  }

  Map<String, dynamic>? get _selectedModel =>
      _modelsFor(_selectedProvider)
          .where((model) => model['id']?.toString() == _selectedModelId)
          .firstOrNull;

  int get _selectedModelFps =>
      (_selectedModel?['fps'] as num?)?.toInt() ?? _fps;

  Map<String, dynamic>? _localProviderHardware(Map<String, dynamic>? provider) {
    if (provider == null) return null;
    final providers = _hardware?['local_video_providers'];
    if (providers is! List) return null;
    for (final item in providers.whereType<Map>()) {
      if (item['tool_id'] == provider['tool_id']) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  bool get _providerSupportsMode {
    final operations = List<String>.from(
      _selectedProvider?['operations'] as List? ?? const [],
    );
    final requiredOperation = switch (_mode) {
      'Image to Video' => 'image_to_video',
      'Reference Video' => 'reference_to_video',
      _ => 'text_to_video',
    };
    final modelOperations = _selectedModel?['operations'];
    return operations.contains(requiredOperation) &&
        (modelOperations is! List ||
            modelOperations.contains(requiredOperation));
  }

  List<String> get _generationModesForSelectedProvider {
    if (_selectedProvider == null) {
      return const [
        'Text to Video',
        'Image to Video',
        'Reference Video',
        'Template',
      ];
    }
    final providerOperations = List<String>.from(
      _selectedProvider?['operations'] as List? ?? const [],
    );
    final modelOperations = _selectedModel?['operations'];
    final operations = modelOperations is List
        ? providerOperations.where(modelOperations.contains).toList()
        : providerOperations;
    return [
      if (operations.contains('text_to_video')) 'Text to Video',
      if (operations.contains('image_to_video')) 'Image to Video',
      if (operations.contains('reference_to_video')) 'Reference Video',
      'Template',
    ];
  }

  @override
  void dispose() {
    _prompt.dispose();
    _project.dispose();
    _negative.dispose();
    _seed.dispose();
    _generatedVideo?.dispose();
    super.dispose();
  }

  bool get _hasPrompt => _prompt.text.trim().length >= 12;
  bool get _hasImage => _assets.any((a) => a['type'] == 'image');
  bool get _hasUsableImage => _assets.any((asset) {
    if (asset['type'] != 'image') return false;
    final localPath = asset['path'] ?? '';
    return localPath.isNotEmpty ||
        ((asset['backendProjectId'] ?? '').isNotEmpty &&
            (asset['remoteUrl'] ?? '').isNotEmpty &&
            (asset['id'] ?? '').isNotEmpty);
  });
  bool get _hasReferenceVideo => _assets.any((a) => a['type'] == 'video');
  Map<String, dynamic> get _selectedSchemaProperties {
    final schema = _selectedProvider?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    return properties is Map ? Map<String, dynamic>.from(properties) : const {};
  }

  List<int> get _durationOptions {
    final modelValues = _selectedModel?['duration_options'];
    if (modelValues is List) {
      return modelValues.map((value) => (value as num).toInt()).toList();
    }
    final values = _selectedSchemaProperties['duration_hint']?['enum'];
    if (values is List) {
      return values
          .map((value) => int.tryParse(value.toString().replaceAll('s', '')))
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
    }
    return const [5, 10, 15, 30];
  }

  List<String> get _aspectOptions {
    final values = _selectedSchemaProperties['aspect_ratio']?['enum'];
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const ['16:9', '9:16', '1:1'];
  }

  List<int> get _fpsOptions {
    final values = _selectedSchemaProperties['fps']?['enum'];
    if (values is List) {
      return values
          .map((value) => int.tryParse(value.toString()))
          .whereType<int>()
          .toList();
    }
    return const [24, 30, 60];
  }

  bool get _canGenerate =>
      !_generating &&
      !_registryLoading &&
      _registryError == null &&
      _selectedProvider?['status'] == 'available' &&
      (_executionMode != 'local_gpu' ||
          _isLocalModelReady(_selectedProvider, _selectedModelId)) &&
      _mobileJobOperations.contains('generate') &&
      _providerSupportsMode &&
      _hasPrompt &&
      (!_selectedSchemaProperties.containsKey('duration_hint') &&
              !_selectedSchemaProperties.containsKey('num_frames') ||
          _durationOptions.contains(_duration)) &&
      (!_selectedSchemaProperties.containsKey('aspect_ratio') ||
          _aspectOptions.contains(_ratio)) &&
      (!_selectedSchemaProperties.containsKey('fps') ||
          _fpsOptions.isEmpty ||
          _fpsOptions.contains(_fps)) &&
      (_mode != 'Image to Video' || _hasUsableImage) &&
      (_mode != 'Reference Video' || _hasReferenceVideo);

  Future<void> _pick(String type, {bool replace = false}) async {
    final result = await FilePicker.pickFiles(
      type: type == 'image' ? FileType.image : FileType.video,
    );
    if (!mounted || result.isEmpty) return;
    setState(() {
      if (replace) _assets.removeWhere((asset) => asset['type'] == type);
      _assets.add({
        'name': result.first.name,
        'path': result.first.path ?? '',
        'type': type,
      });
    });
  }

  Future<void> _pickLibrary() async {
    final all = await LibraryStorage.getAssets();
    final options = all
        .where((a) => ['image', 'video'].contains(a['type']))
        .toList();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Reference Assets')),
            if (options.isEmpty)
              const ListTile(
                title: Text('No image or video assets in your library yet.'),
              ),
            ...options.map(
              (a) => ListTile(
                leading: Icon(
                  a['type'] == 'image'
                      ? Icons.image_outlined
                      : Icons.video_library_outlined,
                ),
                title: Text(a['name']?.toString() ?? 'Asset'),
                onTap: () => Navigator.pop(context, a),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => _assets.add({
          'name': selected['name'].toString(),
          'path': selected['path'].toString(),
          'type': selected['type'].toString(),
          'id': selected['id']?.toString() ?? '',
          'backendProjectId': selected['backendProjectId']?.toString() ?? '',
          'remoteUrl': selected['remoteUrl']?.toString() ?? '',
        }),
      );
    }
  }

  void _chooseTemplate(TemplateCatalogEntry template) {
    setState(() {
      _template = template.title;
      _prompt.text = template.prompt;
      _style = template.style;
      _duration = int.tryParse(template.duration.replaceAll('s', '')) ?? 15;
      _ratio = template.defaultParameters['aspectRatio'] as String? ?? '16:9';
      _resolution =
          template.defaultParameters['resolution'] as String? ?? '720p';
      _fps = template.defaultParameters['fps'] as int? ?? 24;
      _mode = template.defaultParameters['mode'] as String? ?? 'Text to Video';
      _syncModelDefaults(_selectedModel);
    });
  }

  Future<void> _confirmGenerate() async {
    setState(() => _submitted = true);
    if (!_canGenerate) {
      setState(() => _generationError = _generationUnavailableReason);
      return;
    }
    final provider = _selectedProvider!;
    final providerToolId = provider['tool_id'].toString();
    final properties = _selectedSchemaProperties;
    setState(() {
      _generating = true;
      _generationError = null;
      _videoPlaybackError = null;
      _generationStatus = 'Creating project';
      _generationJobId = null;
    });
    try {
      final referenceSelection = switch (_mode) {
        'Image to Video' =>
          _assets.where((asset) => asset['type'] == 'image').firstOrNull,
        'Reference Video' =>
          _assets.where((asset) => asset['type'] == 'video').firstOrNull,
        _ => null,
      };
      final imageSelection = _mode == 'Image to Video'
          ? referenceSelection
          : null;
      final selectedRemoteProject = referenceSelection?['backendProjectId'];
      final initialProjectId = widget.initialProject?['projectId']?.toString();
      final shouldReuseProject =
          selectedRemoteProject != null &&
          selectedRemoteProject.isNotEmpty &&
          (referenceSelection?['remoteUrl'] ?? '').isNotEmpty &&
          (referenceSelection?['id'] ?? '').isNotEmpty;
      final projectId = shouldReuseProject
          ? selectedRemoteProject
          : initialProjectId?.isNotEmpty == true
          ? initialProjectId
          : (await BackendApi.createProject(
              name: _project.text.trim(),
            ))['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }

      final assetIds = <String>[];
      String? referenceArtifactId;
      if (_mode == 'Image to Video') {
        final selection = imageSelection!;
        final imagePath = selection['path'] ?? '';
        if (shouldReuseProject) {
          final remoteId = selection['id'];
          if (remoteId == null || remoteId.isEmpty) {
            throw const FormatException(
              'Selected Library image has no backend ID.',
            );
          }
          final remoteUrl = selection['remoteUrl'] ?? '';
          if (remoteUrl.contains('/api/artifacts/')) {
            referenceArtifactId = remoteId;
          } else {
            assetIds.add(remoteId);
          }
        } else if (imagePath.isNotEmpty && await File(imagePath).exists()) {
          setState(() => _generationStatus = 'Uploading reference image');
          final image = await BackendApi.uploadMediaAsset(
            projectId: projectId,
            file: File(imagePath),
          );
          final imageId = image['id']?.toString();
          if (imageId == null || imageId.isEmpty) {
            throw const FormatException(
              'Backend returned no reference image asset ID.',
            );
          }
          assetIds.add(imageId);
          await LibraryStorage.upsertRemoteAsset(
            id: imageId,
            name:
                image['name']?.toString() ??
                File(imagePath).uri.pathSegments.last,
            type: 'image',
            projectId: projectId,
            remoteUrl: BackendApi.resolveApiUrl(image['file_url'].toString()),
            mimeType: image['mime_type']?.toString(),
          );
        } else {
          throw const FormatException(
            'Choose a local image or a backend image in Library.',
          );
        }
      } else if (_mode == 'Reference Video') {
        final selection = referenceSelection;
        if (selection == null) {
          throw const FormatException('Choose a reference video to continue.');
        }
        final remoteId = selection['id'] ?? '';
        final remoteProject = selection['backendProjectId'] ?? '';
        if (remoteId.isNotEmpty && remoteProject == projectId) {
          if ((selection['remoteUrl'] ?? '').contains('/api/artifacts/')) {
            referenceArtifactId = remoteId;
          } else {
            assetIds.add(remoteId);
          }
        } else {
          final videoPath = selection['path'] ?? '';
          if (videoPath.isEmpty || !await File(videoPath).exists()) {
            throw const FormatException(
              'Choose a local video or one in this project.',
            );
          }
          setState(() => _generationStatus = 'Uploading reference video');
          final uploaded = await BackendApi.uploadMediaAsset(
            projectId: projectId,
            file: File(videoPath),
          );
          final videoId = uploaded['id']?.toString();
          if (videoId == null || videoId.isEmpty) {
            throw const FormatException(
              'Backend returned no reference video asset ID.',
            );
          }
          assetIds.add(videoId);
          await LibraryStorage.upsertRemoteAsset(
            id: videoId,
            name:
                uploaded['name']?.toString() ??
                File(videoPath).uri.pathSegments.last,
            type: 'video',
            projectId: projectId,
            remoteUrl: BackendApi.resolveApiUrl(
              uploaded['file_url'].toString(),
            ),
            mimeType: uploaded['mime_type']?.toString(),
          );
        }
      }

      final parameters = <String, dynamic>{
        'provider_tool_id': providerToolId,
        'prompt': _prompt.text.trim(),
        'mode': switch (_mode) {
          'Image to Video' => 'image_to_video',
          'Reference Video' => 'reference_to_video',
          _ => 'text_to_video',
        },
        if (properties.containsKey('aspect_ratio')) 'aspect_ratio': _ratio,
        'duration_seconds': _duration,
        if (_selectedModelId != null) 'model_id': _selectedModelId,
        if (_seedMode == 'Custom seed') 'seed': int.tryParse(_seed.text.trim()),
        if (properties.containsKey('negative_prompt'))
          'negative_prompt': _negative.text.trim(),
        if (properties.containsKey('guidance_scale'))
          'guidance_scale': _guidance,
        if (properties.containsKey('num_inference_steps'))
          'num_inference_steps': _inferenceSteps,
        if (properties.containsKey('fps')) 'fps': _fps,
      };
      if (referenceArtifactId != null) {
        parameters['reference_artifact_id'] = referenceArtifactId;
      }
      if (properties.containsKey('duration_hint')) {
        parameters['duration_seconds'] = _duration;
      }
      if (properties.containsKey('num_frames')) {
        parameters['num_frames'] = _duration * _selectedModelFps + 1;
      }
      if (properties.containsKey('width') || properties.containsKey('height')) {
        final modelWidth = (_selectedModel?['default_width'] as num?)?.toInt();
        final modelHeight = (_selectedModel?['default_height'] as num?)
            ?.toInt();
        final shortSide =
            int.tryParse(_resolution.replaceAll(RegExp(r'[^0-9]'), '')) ?? 720;
        final dimensions = modelWidth != null && modelHeight != null
            ? (modelWidth, modelHeight)
            : switch (_ratio) {
                '9:16' => (shortSide, (shortSide * 16 / 9).round()),
                '1:1' => (shortSide, shortSide),
                _ => ((shortSide * 16 / 9).round(), shortSide),
              };
        if (properties.containsKey('width')) {
          parameters['width'] = dimensions.$1;
        }
        if (properties.containsKey('height')) {
          parameters['height'] = dimensions.$2;
        }
      }
      setState(() => _generationStatus = 'Submitting generation job');
      var job = await BackendApi.createVideoGenerationJob(
        projectId: projectId,
        assetIds: assetIds,
        parameters: parameters,
      );
      final jobId = job['id']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw const FormatException('Backend returned no generation job ID.');
      }
      _generationJobId = jobId;
      while (true) {
        final status = job['status']?.toString() ?? 'queued';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        final progress = (job['progress'] as num?)?.round();
        if (mounted) {
          setState(
            () => _generationStatus = progress == null
                ? status
                : '$status · $progress%',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 5));
        job = await BackendApi.getJob(jobId);
      }
      if (job['status'] != 'completed') {
        final status = job['status']?.toString();
        if (status == 'failed' || status == 'cancelled') {
          throw FormatException(
            job['error']?.toString() ??
                (status == 'cancelled'
                    ? 'Video generation was cancelled.'
                    : 'generation_failed'),
          );
        }
      }
      final artifacts = await BackendApi.getJobArtifacts(jobId);
      final video = artifacts
          .where(
            (item) => item['type'] == 'video' && item['download_url'] != null,
          )
          .firstOrNull;
      if (video == null) {
        throw const FormatException('Completed job has no video artifact.');
      }
      final videoUrl = BackendApi.resolveApiUrl(
        video['download_url'].toString(),
      );
      await LibraryStorage.upsertRemoteAsset(
        id: video['id'].toString(),
        name: 'Generated video · ${video['metadata']?['format'] ?? 'mp4'}',
        type: 'video',
        projectId: projectId,
        remoteUrl: videoUrl,
        mimeType: video['mime_type']?.toString(),
      );
      await _generatedVideo?.dispose();
      _generatedVideo = null;
      try {
        final player = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await player.initialize();
        _generatedVideo = player;
      } catch (_) {
        _videoPlaybackError =
            'Video artifact is saved, but preview could not be initialized.';
      }
      await ProjectStorage.saveProject(
        id: projectId,
        projectId: projectId,
        title: _project.text.trim(),
        prompt: _prompt.text.trim(),
        style: _style,
        duration:
            '${(video['metadata']?['duration'] as num?)?.toDouble() ?? _duration}s',
        assetCount: assetIds.length + 1,
        status: 'Completed',
        videoUrl: videoUrl,
        jobId: jobId,
        aspectRatio: _ratio,
        model: _selectedModelId ?? 'Auto',
        provider: provider['provider_id']?.toString() ?? providerToolId,
        mode: _mode,
        resolution: _resolution,
        fps: _selectedModelFps,
      );
      if (mounted) {
        setState(() => _generationStatus = 'completed');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _generationError = error.toString().replaceFirst(
            'FormatException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String get _generationUnavailableReason {
    if (_registryLoading) return 'Loading OpenMontage provider availability.';
    if (_registryError != null) {
      return 'Could not load OpenMontage providers: $_registryError';
    }
    if (_selectedProvider == null) {
      return 'No OpenMontage video provider is registered.';
    }
    if (_executionMode == 'local_gpu' &&
        !_isLocalModelReady(_selectedProvider, _selectedModelId)) {
      final local = _localProviderHardware(_selectedProvider);
      final modelStatus = (local?['models'] as List?)
          ?.whereType<Map>()
          .where((model) => model['model_id'] == _selectedModelId)
          .firstOrNull;
      final vram = _hardware?['gpu'] is Map
          ? (_hardware!['gpu'] as Map)['vram_mb']
          : null;
      final required =
          modelStatus?['minimum_vram_mb'] ?? _selectedModel?['vram_mb'];
      if (vram != null &&
          required != null &&
          (vram as num) < (required as num)) {
        return 'This GPU has $vram MB VRAM; ${_selectedProvider?['provider_id']} requires about $required MB. Choose Hugging Face or use a GPU with more VRAM.';
      }
      return 'This model needs the OpenMontage CUDA video dependencies. Sequential CPU offload can make generation very slow.';
    }
    if (_selectedProvider?['status'] != 'available') {
      return _selectedProvider?['install_instructions']?.toString() ??
          'Selected provider is unavailable or not configured.';
    }
    if (!_providerSupportsMode) {
      return 'Selected provider does not support this generation mode.';
    }
    if (!_mobileJobOperations.contains('generate')) {
      return 'Video generation is not executable through the mobile job API yet.';
    }
    return 'Ready to generate.';
  }

  Widget _providerSelector(ThemeData theme) {
    final selected = _selectedProvider;
    final models = _modelsFor(selected);
    final available = selected?['status'] == 'available';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Generation Runtime'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'local_gpu',
                  icon: Icon(Icons.memory_outlined),
                  label: Text('My GPU'),
                ),
                ButtonSegment(
                  value: 'huggingface',
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('Hugging Face'),
                ),
              ],
              selected: {_executionMode},
              onSelectionChanged: (selection) {
                final mode = selection.first;
                final choices = _providerTools.where(
                  (provider) => mode == 'huggingface'
                      ? provider['provider_id'] == 'huggingface'
                      : provider['runtime'] == 'local_gpu',
                );
                final next = mode == _executionMode
                    ? _selectedProvider
                    : choices
                              .where(
                                (provider) => provider['status'] == 'available',
                              )
                              .firstOrNull ??
                          choices.firstOrNull;
                setState(() {
                  _executionMode = mode;
                  _selectedProviderToolId = next?['tool_id']?.toString();
                  _selectedModelId = _modelForProvider(next)?['id']?.toString();
                  _syncModelDefaults(_modelForProvider(next));
                  if (!_generationModesForSelectedProvider.contains(_mode)) {
                    _mode = 'Text to Video';
                  }
                  _fps =
                      (_selectedModel?['fps'] as num?)?.toInt() ??
                      _fpsOptions.firstOrNull ??
                      _fps;
                  _generationError = null;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              _executionMode == 'huggingface'
                  ? 'Runs in the cloud through Hugging Face Inference Providers. Configure HF_TOKEN on the backend. Free accounts currently have no included inference credits; usage may require purchased credits or PRO.'
                  : 'Runs on this computer. Generation is enabled only when its detected GPU meets the selected model requirement.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _label('Provider'),
            if (_registryLoading)
              const LinearProgressIndicator()
            else if (_registryError != null)
              Text(
                'Provider registry unavailable: $_registryError',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (_providersForSelection.isEmpty)
              const Text(
                'No provider is registered for this runtime yet. Configure a Hugging Face token on the backend or use a compatible local GPU.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedProviderToolId,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: _providersForSelection.map((provider) {
                  final name =
                      provider['provider_id']?.toString() ??
                      provider['tool_id']?.toString() ??
                      'Provider';
                  final status = provider['status']?.toString() ?? 'unknown';
                  return DropdownMenuItem(
                    value: provider['tool_id']?.toString(),
                    child: Text(
                      '$name · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() {
                  _selectedProviderToolId = value;
                  final next = _selectedProvider;
                  _selectedModelId = _modelForProvider(next)?['id']?.toString();
                  _syncModelDefaults(_modelForProvider(next));
                  if (!_generationModesForSelectedProvider.contains(_mode)) {
                    _mode = 'Text to Video';
                  }
                  if (!_durationOptions.contains(_duration)) {
                    _duration = _durationOptions.firstOrNull ?? _duration;
                  }
                  _fps =
                      (_selectedModel?['fps'] as num?)?.toInt() ??
                      _fpsOptions.firstOrNull ??
                      _fps;
                  _generationError = null;
                }),
              ),
            const SizedBox(height: 12),
            _label('Model'),
            if (models.isEmpty)
              Text(
                'No model is advertised by this provider${available ? '' : ' (provider unavailable)'}.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    models.any((model) => model['id'] == _selectedModelId)
                    ? _selectedModelId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: models
                    .map(
                      (model) => DropdownMenuItem<String>(
                        value: model['id']?.toString(),
                        child: Text(
                          '${model['name'] ?? model['id']} · ${model['vram_mb'] ?? '?'} MB VRAM${model['speed'] == 'slow' ? ' · slow' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: available
                    ? (value) => setState(() {
                        _selectedModelId = value;
                        _syncModelDefaults(_selectedModel);
                        if (!_generationModesForSelectedProvider.contains(
                          _mode,
                        )) {
                          _mode = 'Text to Video';
                        }
                      })
                    : null,
              ),
            const SizedBox(height: 10),
            Text(
              _generationUnavailableReason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: available
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
            if (_executionMode == 'local_gpu') ...[
              const SizedBox(height: 12),
              _localHardwareCard(theme),
            ],
            if (_executionMode == 'huggingface' &&
                selected != null &&
                models.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Model target: ${models.first['resolution'] ?? 'provider default'} · ${models.first['fps'] ?? '?'} FPS · up to ${models.first['max_duration_seconds'] ?? '?'} sec. Resolution and aspect ratio are fixed by this model route.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _localHardwareCard(ThemeData theme) {
    final local = _localProviderHardware(_selectedProvider);
    final localModel = (local?['models'] as List?)
        ?.whereType<Map>()
        .where((model) => model['model_id'] == _selectedModelId)
        .firstOrNull;
    final gpu = _hardware?['gpu'];
    final cuda = _hardware?['cuda'];
    String display(dynamic value) =>
        value == null ? 'Not detected' : value.toString();
    final status =
        localModel?['status']?.toString() ?? local?['status']?.toString();
    final requiredVram =
        localModel?['minimum_vram_mb'] ?? _selectedModel?['vram_mb'];
    final statusColor = status == 'ready'
        ? Colors.green
        : status == 'unsupported_hardware'
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Local GPU compatibility'),
            if (_hardwareError != null)
              Text('Hardware detection unavailable: $_hardwareError')
            else if (_hardware == null)
              const LinearProgressIndicator()
            else ...[
              Text(
                'GPU: ${display(gpu is Map ? gpu['name'] : null)} · ${display(gpu is Map ? gpu['vram_mb'] : null)} MB VRAM',
              ),
              Text(
                'CUDA: ${cuda is Map && cuda['available'] == true ? 'Available' : 'Unavailable'} · RAM: ${display(_hardware!['ram_mb'])} MB',
              ),
              Text(
                'CPU: ${display(_hardware!['cpu'] is Map ? (_hardware!['cpu'] as Map)['name'] : null)} · ${display(_hardware!['cpu'] is Map ? (_hardware!['cpu'] as Map)['logical_cores'] : null)} cores',
              ),
              if (status != null)
                Text(
                  'Selected model needs about ${display(requiredVram)} MB VRAM · $status${_selectedModel?['offload_strategy'] == 'sequential_cpu' ? ' · Sequential CPU offload is very slow' : ''}',
                  style: TextStyle(color: statusColor),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String get _costMessage => _executionMode == 'huggingface'
      ? 'Hugging Face Free currently includes no Inference Providers credits. Check model/provider pricing and your HF usage before generating; clip frame count affects provider usage.'
      : 'No cloud inference charge. Uses local GPU resources and may download model weights.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promptError = _submitted && !_hasPrompt
        ? (_prompt.text.trim().isEmpty
              ? 'Please describe the video you want to create.'
              : 'Please provide a more detailed description.')
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('AI Video Studio'),
            Text(
              'Turn ideas into production-ready video.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              if (widget.workflowId != null || widget.templateId != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(
                      widget.workflowId == null ? 'Template' : 'Workflow',
                    ),
                    subtitle: Text(widget.templateId ?? widget.workflowId!),
                    trailing: const Text('Not connected'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _providerSelector(theme),
              const SizedBox(height: 12),
              Text(
                'Turn ideas into polished videos.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _label('Project Name'),
              TextField(
                key: const ValueKey('projectNameField'),
                controller: _project,
                maxLength: 100,
                onChanged: (_) => setState(() => _generationError = null),
                decoration: const InputDecoration(
                  hintText: 'Untitled Video',
                  counterText: '',
                ),
              ),
              if (_submitted && !_hasPrompt)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _prompt.text.trim().isEmpty
                        ? 'Please describe the video you want to create.'
                        : 'Please provide a more detailed description.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _label('Generation Mode'),
              _selectChips(
                _generationModesForSelectedProvider,
                _mode,
                (v) => setState(() {
                  _mode = v;
                  _submitted = false;
                }),
              ),
              if (_mode == 'Template') ...[
                const SizedBox(height: 10),
                _label('Choose a Template'),
                ...FeatureCatalog.templates.map(
                  (template) => Card(
                    child: ListTile(
                      selected: _template == template.title,
                      leading: Icon(
                        _template == template.title
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _template == template.title
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(template.title),
                      subtitle: Text(template.prompt),
                      onTap: () => _chooseTemplate(template),
                    ),
                  ),
                ),
              ],
              if (_mode == 'Image to Video') ...[
                const SizedBox(height: 14),
                _label('Reference Image'),
                _imagePicker(),
              ],
              if (_mode == 'Reference Video') ...[
                const SizedBox(height: 14),
                _label('Reference Video'),
                OutlinedButton.icon(
                  onPressed: () => _pick('video', replace: true),
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(
                    _hasReferenceVideo
                        ? 'Change Reference Video'
                        : 'Choose Reference Video',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _label(
                _mode == 'Image to Video'
                    ? 'Motion Prompt'
                    : 'Describe your video',
              ),
              TextField(
                controller: _prompt,
                maxLength: 1000,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() => _generationError = null),
                decoration: InputDecoration(
                  hintText: _mode == 'Image to Video'
                      ? 'Describe how the image should move...'
                      : 'Describe the video you want to create...',
                  alignLabelWithHint: true,
                  errorText: promptError,
                  helperText: '${_prompt.text.length} / 1000 characters',
                ),
              ),
              if (_mode == 'Image to Video')
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Add an image and a motion description to continue.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ),
              if (_mode == 'Reference Video' && !_hasReferenceVideo)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Please choose a reference video to continue.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 12),
              if (_selectedSchemaProperties.containsKey('style')) ...[
                _label('Style'),
                _selectChips(
                  List<String>.from(
                    _selectedSchemaProperties['style']?['enum'] ?? const [],
                  ),
                  _style,
                  (v) => setState(() => _style = v),
                ),
              ] else
                const Text(
                  'This OpenMontage provider does not accept a style parameter.',
                ),
              const SizedBox(height: 12),
              if (_selectedSchemaProperties.containsKey('duration_hint') ||
                  _selectedSchemaProperties.containsKey('num_frames')) ...[
                _label('Duration'),
                _selectChips(
                  _durationOptions.map((x) => '$x seconds').toList(),
                  '$_duration seconds',
                  (v) =>
                      setState(() => _duration = int.parse(v.split(' ').first)),
                ),
                const SizedBox(height: 12),
              ],
              if (_selectedSchemaProperties.containsKey('aspect_ratio')) ...[
                _label('Aspect Ratio'),
                Wrap(
                  spacing: 8,
                  children: _aspectOptions
                      .map(
                        (v) => ChoiceChip(
                          label: Text(
                            '$v · ${v == '16:9'
                                ? 'Landscape'
                                : v == '9:16'
                                ? 'Portrait / Shorts'
                                : 'Square'}',
                          ),
                          selected: _ratio == v,
                          onSelected: (_) => setState(() => _ratio = v),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              _assetsSection(),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Estimated cost'),
                  subtitle: Text(
                    _costMessage,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ExpansionTile(
                  title: const Text('Advanced Settings'),
                  initiallyExpanded: _advanced,
                  onExpansionChanged: (v) => setState(() => _advanced = v),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if ((_selectedSchemaProperties.containsKey('width') ||
                            _selectedSchemaProperties.containsKey('height')) &&
                        _selectedModel?['default_width'] == null) ...[
                      _label('Resolution'),
                      _selectChips(
                        ['480p', '720p', '1080p'],
                        _resolution,
                        (v) => setState(() => _resolution = v),
                      ),
                    ],
                    if (_selectedSchemaProperties.containsKey('seed')) ...[
                      const SizedBox(height: 8),
                      _label('Seed'),
                      _selectChips(
                        ['Auto', 'Custom seed'],
                        _seedMode,
                        (v) => setState(() => _seedMode = v),
                      ),
                      if (_seedMode == 'Custom seed')
                        TextField(
                          controller: _seed,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '123456'),
                        ),
                    ],
                    if (_selectedSchemaProperties.containsKey(
                      'negative_prompt',
                    )) ...[
                      const SizedBox(height: 8),
                      _label('Negative Prompt'),
                      TextField(
                        controller: _negative,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Things to avoid...',
                        ),
                      ),
                    ],
                    if (_selectedSchemaProperties.containsKey(
                      'guidance_scale',
                    )) ...[
                      _label(
                        'Guidance / Creativity · ${_guidance.toStringAsFixed(1)}',
                      ),
                      Slider(
                        value: _guidance,
                        min:
                            (_selectedSchemaProperties['guidance_scale']?['minimum']
                                    as num?)
                                ?.toDouble() ??
                            1,
                        max:
                            (_selectedSchemaProperties['guidance_scale']?['maximum']
                                    as num?)
                                ?.toDouble() ??
                            12,
                        divisions: 20,
                        onChanged: (v) => setState(() => _guidance = v),
                      ),
                    ],
                    if (_selectedSchemaProperties.containsKey(
                      'num_inference_steps',
                    )) ...[
                      _label('Inference Steps · $_inferenceSteps'),
                      Slider(
                        value: _inferenceSteps.toDouble(),
                        min:
                            ((_selectedSchemaProperties['num_inference_steps']?['minimum']
                                        as num?) ??
                                    1)
                                .toDouble(),
                        max:
                            ((_selectedSchemaProperties['num_inference_steps']?['maximum']
                                        as num?) ??
                                    50)
                                .toDouble(),
                        divisions: 49,
                        onChanged: (value) =>
                            setState(() => _inferenceSteps = value.round()),
                      ),
                    ],
                    if (_selectedSchemaProperties.containsKey('fps')) ...[
                      _label('Frame Rate'),
                      _selectChips(
                        _fpsOptions.map((x) => '$x FPS').toList(),
                        '$_fps FPS',
                        (v) => setState(
                          () => _fps = int.parse(v.split(' ').first),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _canGenerate ? _confirmGenerate : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _generating
                        ? 'Generating · ${_generationStatus ?? 'queued'}'
                        : 'Generate Video',
                  ),
                ),
              ),
              if (_generating && _generationJobId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _generationStatus == 'Submitting generation job'
                        ? 'Preparing the video model on your laptop. The first run can take several minutes. Keep this screen open and do not tap Generate again.'
                        : 'Preparing your project and generation request…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_generationJobId != null)
                ListTile(
                  leading: const Icon(Icons.work_history_outlined),
                  title: Text('Job ${_generationJobId!}'),
                  subtitle: Text('Status: ${_generationStatus ?? 'queued'}'),
                ),
              if (_generatedVideo?.value.isInitialized == true)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Generated Video'),
                        const SizedBox(height: 8),
                        AspectRatio(
                          aspectRatio: _generatedVideo!.value.aspectRatio,
                          child: VideoPlayer(_generatedVideo!),
                        ),
                        IconButton(
                          onPressed: () => setState(
                            () => _generatedVideo!.value.isPlaying
                                ? _generatedVideo!.pause()
                                : _generatedVideo!.play(),
                          ),
                          icon: Icon(
                            _generatedVideo!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        const Text('Saved to this project and Library.'),
                      ],
                    ),
                  ),
                ),
              if (_videoPlaybackError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_videoPlaybackError!),
                ),
              if (_generationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Generation Failed · $_generationError',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_mode == 'Image to Video' && !_hasImage)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Please add a reference image.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePicker() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (_hasImage)
            ..._assets
                .where((a) => a['type'] == 'image')
                .map((a) => _assetTile(a))
          else
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 34),
                  SizedBox(height: 8),
                  Text('Add an image to animate'),
                ],
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _pick('image'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add Image'),
              ),
              if (_hasImage)
                TextButton(
                  onPressed: () => _pick('image', replace: true),
                  child: const Text('Replace'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _assetsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Reference Assets'),
      Wrap(
        spacing: 6,
        children: [
          OutlinedButton.icon(
            onPressed: () => _pick('image'),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Add Image'),
          ),
          OutlinedButton.icon(
            onPressed: () => _pick('video'),
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('Add Video'),
          ),
          TextButton.icon(
            onPressed: _pickLibrary,
            icon: const Icon(Icons.folder_open),
            label: const Text('Library'),
          ),
        ],
      ),
      ..._assets.map(_assetTile),
    ],
  );

  Widget _assetTile(Map<String, String> a) => Card(
    child: ListTile(
      leading: a['type'] == 'image' && (a['path'] ?? '').isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(a['path']!),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
              ),
            )
          : Icon(
              a['type'] == 'video'
                  ? Icons.video_file_outlined
                  : Icons.image_outlined,
            ),
      title: Text(
        a['name'] ?? 'Reference asset',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Remove asset',
        onPressed: () => setState(() => _assets.remove(a)),
        icon: const Icon(Icons.close),
      ),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
  Widget _selectChips(
    List<String> values,
    String selected,
    ValueChanged<String> onSelect,
  ) => Wrap(
    spacing: 7,
    runSpacing: 4,
    children: values
        .map(
          (v) => ChoiceChip(
            label: Text(v),
            selected: selected == v,
            onSelected: (_) => onSelect(v),
          ),
        )
        .toList(),
  );
}
