import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/backend_api.dart';
import '../services/library_storage.dart';

class AiImageGeneratorPage extends StatefulWidget {
  const AiImageGeneratorPage({super.key});

  @override
  State<AiImageGeneratorPage> createState() => _AiImageGeneratorPageState();
}

class _AiImageGeneratorPageState extends State<AiImageGeneratorPage> {
  final _prompt = TextEditingController();
  final _negativePrompt = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  List<String> _jobOperations = [];
  String? _selectedToolId;
  String? _selectedModelId;
  String? _referencePath;
  String? _referenceName;
  String? _registryError;
  bool _loading = true;
  String _ratio = '1:1';
  String _resolution = '1024';
  bool _generating = false;
  String? _jobId;
  String? _jobStatus;
  String? _jobError;
  String? _artifactUrl;
  String? _projectId;

  @override
  void initState() {
    super.initState();
    _loadRegistry();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _negativePrompt.dispose();
    super.dispose();
  }

  Future<void> _loadRegistry() async {
    try {
      final results = await Future.wait([
        BackendApi.getProviders(capability: 'image_generation'),
        BackendApi.getCapabilities(),
      ]);
      final providers = results[0];
      final capabilities = results[1];
      final capability = capabilities.where(
        (item) => item['id'] == 'image_generation',
      );
      final operations = capability.isEmpty
          ? const <String>[]
          : List<String>.from(
              capability.first['mobile_job_operations'] as List? ?? const [],
            );
      final available = providers.where(
        (provider) => provider['status'] == 'available',
      );
      final selected = available.firstOrNull ?? providers.firstOrNull;
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _jobOperations = operations;
        _selectedToolId = selected?['tool_id']?.toString();
        _selectedModelId = _models(selected).firstOrNull?['id']?.toString();
        _ratio = _aspectOptions.firstOrNull ?? _ratio;
        _resolution = _enumOptions('resolution').firstOrNull ?? _resolution;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _registryError = error.toString().replaceFirst('FormatException: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _models(Map<String, dynamic>? provider) {
    final models = provider?['models'];
    return models is List
        ? models.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const [];
  }

  Map<String, dynamic>? get _selectedProvider => _providers
      .where((provider) => provider['tool_id'] == _selectedToolId)
      .firstOrNull;

  Map<String, dynamic> get _schemaProperties {
    final schema = _selectedProvider?['input_schema'];
    final properties = schema is Map ? schema['properties'] : null;
    return properties is Map ? Map<String, dynamic>.from(properties) : const {};
  }

  bool get _supportsReference =>
      ['image_path', 'image_paths', 'image'].any(_schemaProperties.containsKey);

  List<String> get _aspectOptions {
    final values = _schemaProperties['aspect_ratio']?['enum'];
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const ['1:1', '16:9', '9:16', '4:3'];
  }

  List<String> _enumOptions(String key) {
    final values = _schemaProperties[key]?['enum'];
    return values is List
        ? values.map((value) => value.toString()).toList()
        : const [];
  }

  bool get _canGenerate =>
      !_loading &&
      !_generating &&
      _registryError == null &&
      _selectedProvider?['status'] == 'available' &&
      _jobOperations.contains('generate') &&
      _prompt.text.trim().length >= 3 &&
      (!_schemaProperties.containsKey('model') || _selectedModelId != null) &&
      (_referencePath == null || _supportsReference);

  Future<void> _pickReference() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (!mounted || result.isEmpty) return;
    setState(() {
      _referencePath = result.first.path;
      _referenceName = result.first.name;
    });
  }

  String get _availabilityMessage {
    if (_loading) return 'Loading OpenMontage image provider status.';
    if (_registryError != null) {
      return 'Provider registry unavailable: $_registryError';
    }
    if (_providers.isEmpty) {
      return 'No image generation provider is registered.';
    }
    if (_selectedProvider?['status'] != 'available') {
      return 'Selected image provider is unavailable or not configured.';
    }
    if (!_jobOperations.contains('generate')) {
      return 'Image generation is not exposed by the mobile job API yet.';
    }
    return _canGenerate
        ? 'Ready to generate.'
        : 'Enter a prompt to enable generation.';
  }

  Future<void> _generateImage() async {
    if (!_canGenerate) return;
    final provider = _selectedProvider!;
    final properties = _schemaProperties;
    setState(() {
      _generating = true;
      _jobError = null;
      _artifactUrl = null;
      _jobId = null;
      _jobStatus = 'Creating project';
    });
    try {
      final project = await BackendApi.createProject(
        name:
            'Image · ${_prompt.text.trim().substring(0, _prompt.text.trim().length.clamp(0, 48))}',
      );
      final projectId = project['id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        throw const FormatException('Backend returned no project ID.');
      }
      _projectId = projectId;
      final assetIds = <String>[];
      if (_referencePath != null) {
        if (!_supportsReference) {
          throw const FormatException(
            'The selected OpenMontage provider does not support image editing.',
          );
        }
        setState(() => _jobStatus = 'Uploading reference image');
        final uploaded = await BackendApi.uploadMediaAsset(
          projectId: projectId,
          file: File(_referencePath!),
        );
        final assetId = uploaded['id']?.toString();
        if (assetId == null || assetId.isEmpty) {
          throw const FormatException(
            'Backend returned no reference image asset ID.',
          );
        }
        assetIds.add(assetId);
        await LibraryStorage.upsertRemoteAsset(
          id: assetId,
          name:
              uploaded['name']?.toString() ??
              _referenceName ??
              'Reference image',
          type: 'image',
          projectId: projectId,
          remoteUrl: BackendApi.resolveApiUrl(uploaded['file_url'].toString()),
          mimeType: uploaded['mime_type']?.toString(),
        );
      }
      final parameters = <String, dynamic>{
        'provider_tool_id': provider['tool_id'].toString(),
        'prompt': _prompt.text.trim(),
        if (_schemaProperties.containsKey('aspect_ratio'))
          'aspect_ratio': _ratio,
        if (_schemaProperties.containsKey('resolution'))
          'resolution': _resolution,
        if (_selectedModelId != null) 'model_id': _selectedModelId,
        if (properties.containsKey('negative_prompt'))
          'negative_prompt': _negativePrompt.text.trim(),
      };
      if (properties.containsKey('width') || properties.containsKey('height')) {
        final side = int.tryParse(_resolution) ?? 1024;
        final dimensions = switch (_ratio) {
          '16:9' => (side, (side * 9 / 16).round()),
          '9:16' => ((side * 9 / 16).round(), side),
          '4:3' => (side, (side * 3 / 4).round()),
          _ => (side, side),
        };
        if (properties.containsKey('width')) {
          parameters['width'] = dimensions.$1;
        }
        if (properties.containsKey('height')) {
          parameters['height'] = dimensions.$2;
        }
      }
      setState(() => _jobStatus = 'Submitting image job');
      var job = await BackendApi.createImageGenerationJob(
        projectId: projectId,
        assetIds: assetIds,
        parameters: parameters,
      );
      final jobId = job['id']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw const FormatException(
          'Backend returned no image generation job ID.',
        );
      }
      _jobId = jobId;
      final timeout = Stopwatch()..start();
      while (timeout.elapsed < const Duration(minutes: 15)) {
        final status = job['status']?.toString() ?? 'queued';
        if (status == 'completed' ||
            status == 'failed' ||
            status == 'cancelled') {
          break;
        }
        if (mounted) setState(() => _jobStatus = status);
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await BackendApi.getJob(jobId);
      }
      if (job['status'] != 'completed') {
        if (job['status'] != 'failed' && job['status'] != 'cancelled') {
          throw FormatException(
            'Image generation is still processing (job $_jobId). Check this job again later.',
          );
        }
        throw FormatException(job['error']?.toString() ?? 'generation_failed');
      }
      final artifacts = await BackendApi.getJobArtifacts(jobId);
      final image = artifacts
          .where(
            (item) => item['type'] == 'image' && item['download_url'] != null,
          )
          .firstOrNull;
      if (image == null) {
        throw const FormatException('Completed job has no image artifact.');
      }
      final url = BackendApi.resolveApiUrl(image['download_url'].toString());
      await LibraryStorage.upsertRemoteAsset(
        id: image['id'].toString(),
        name: 'Generated image · ${image['metadata']?['format'] ?? 'png'}',
        type: 'image',
        projectId: projectId,
        remoteUrl: url,
        mimeType: image['mime_type']?.toString(),
      );
      if (mounted) {
        setState(() {
          _artifactUrl = url;
          _jobStatus = 'completed';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _jobError = error.toString().replaceFirst(
            'FormatException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = _models(_selectedProvider);
    final providerAvailable = _selectedProvider?['status'] == 'available';
    return Scaffold(
      appBar: AppBar(title: const Text('AI Image Studio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Text(
              'Create an image for a project or as a future video reference.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const _FieldLabel('Prompt'),
            TextField(
              key: const ValueKey('imagePromptField'),
              controller: _prompt,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the image you want to create...',
                alignLabelWithHint: true,
              ),
            ),
            if (_schemaProperties.containsKey('negative_prompt')) ...[
              const SizedBox(height: 12),
              const _FieldLabel('Negative Prompt'),
              TextField(
                controller: _negativePrompt,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Optional details to avoid',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Provider'),
                    if (_loading)
                      const LinearProgressIndicator()
                    else if (_registryError != null)
                      Text(
                        _registryError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    else if (_providers.isEmpty)
                      const Text('No image generation provider is registered.')
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedToolId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: _providers.map((provider) {
                          final providerName =
                              provider['provider_id']?.toString() ??
                              provider['tool_id']?.toString() ??
                              'Provider';
                          return DropdownMenuItem(
                            value: provider['tool_id']?.toString(),
                            child: Text(
                              '$providerName · ${provider['status'] ?? 'unknown'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() {
                          _selectedToolId = value;
                          _selectedModelId = _models(_selectedProvider)
                              .firstOrNull?['id']
                              ?.toString();
                          _ratio = _aspectOptions.firstOrNull ?? _ratio;
                          _resolution =
                              _enumOptions('resolution').firstOrNull ??
                              _resolution;
                        }),
                      ),
                    const SizedBox(height: 12),
                    const _FieldLabel('Model'),
                    if (models.isEmpty)
                      const Text('No model is advertised by this provider.')
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            models.any(
                              (model) => model['id'] == _selectedModelId,
                            )
                            ? _selectedModelId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: models.map((model) {
                          final id = model['id']?.toString() ?? '';
                          return DropdownMenuItem(
                            value: id,
                            child: Text(
                              '${model['name'] ?? id} · ${model['status'] ?? _selectedProvider?['status'] ?? 'unknown'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: providerAvailable
                            ? (value) =>
                                  setState(() => _selectedModelId = value)
                            : null,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _availabilityMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: providerAvailable
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_schemaProperties.containsKey('aspect_ratio')) ...[
              const _FieldLabel('Aspect Ratio'),
              Wrap(
                spacing: 8,
                children: _aspectOptions
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: _ratio == value,
                        onSelected: (_) => setState(() => _ratio = value),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (_schemaProperties.containsKey('resolution')) ...[
              const _FieldLabel('Resolution'),
              if (_enumOptions('resolution').isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _enumOptions('resolution').contains(_resolution)
                      ? _resolution
                      : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _enumOptions('resolution')
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _resolution = value ?? _resolution),
                )
              else
                TextFormField(
                  initialValue: _resolution,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Provider resolution',
                  ),
                  onChanged: (value) => _resolution = value,
                ),
              const SizedBox(height: 12),
            ],
            if (_supportsReference)
              OutlinedButton.icon(
                onPressed: _generating ? null : _pickReference,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_referenceName ?? 'Choose Reference Image'),
              ),
            if (_referencePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(_referencePath!),
                    height: 190,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text(
                      'The selected image cannot be previewed on this device.',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _canGenerate ? _generateImage : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_generating ? 'Generating Image…' : 'Generate Image'),
            ),
            if (_generating) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text('Job ${_jobId ?? '—'} · ${_jobStatus ?? 'starting'}'),
            ],
            if (_jobError != null) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Image generation failed'),
                  subtitle: Text(_jobError!),
                ),
              ),
            ],
            if (_artifactUrl != null) ...[
              const SizedBox(height: 16),
              const _FieldLabel('Generated Image'),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _artifactUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) => const ListTile(
                    title: Text('Image saved to project and Library'),
                    subtitle: Text('Preview is unavailable on this device.'),
                  ),
                ),
              ),
              if (_projectId != null)
                Text('Saved in project $_projectId and Library.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

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
