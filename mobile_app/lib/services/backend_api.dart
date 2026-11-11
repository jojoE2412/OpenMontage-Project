import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class BackendApi {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );

  static Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static String _safeApiError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is List) {
          return 'The request was rejected. Check the submitted video and settings.';
        }
      }
    } catch (_) {
      // Avoid returning raw proxy/server pages, which can expose internal details.
    }
    return 'OpenMontage could not complete the request. Please try again.';
  }

  static Future<Map<String, dynamic>> _decodeJsonResponse(
    http.Response response, {
    required String context,
  }) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _safeApiError(response);
      throw Exception('$context failed (${response.statusCode}): $message');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw const FormatException('response is not a JSON object');
    } on FormatException {
      throw Exception('Invalid $context response');
    }
  }

  static Future<Map<String, dynamic>> healthCheck() async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 8));
      final decoded = await _decodeJsonResponse(
        response,
        context: 'Backend health check',
      );
      return decoded;
    } on TimeoutException {
      throw const FormatException('Backend health check timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> createVideo({
    required String title,
    required String prompt,
    required String style,
    required String duration,
  }) async {
    final client = http.Client();
    try {
      final response = await client
          .post(
            _uri('/api/videos'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'prompt': prompt,
              'style': style,
              'duration': duration,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final decoded = await _decodeJsonResponse(
        response,
        context: 'Create video',
      );
      return decoded;
    } on TimeoutException {
      throw const FormatException('Create video request timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/videos/$jobId'))
          .timeout(const Duration(seconds: 8));
      final decoded = await _decodeJsonResponse(
        response,
        context: 'Job status',
      );
      return decoded;
    } on TimeoutException {
      throw const FormatException('Job status request timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
    String context, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = http.Client();
    try {
      final response = await client
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return await _decodeJsonResponse(response, context: context);
    } on TimeoutException {
      throw FormatException(
        context == 'Create video generation job'
            ? 'OpenMontage is still preparing the video job. The request may still be running on your laptop. Check Projects before trying again.'
            : '$context did not receive a response from OpenMontage. Check that the backend is running and that BACKEND_URL is reachable from this device ($baseUrl).',
      );
    } on SocketException {
      throw FormatException(
        'Cannot connect to OpenMontage at $baseUrl. Check the backend, network, and BACKEND_URL.',
      );
    } on http.ClientException {
      throw FormatException(
        'Cannot connect to OpenMontage at $baseUrl. Check the backend, network, and BACKEND_URL.',
      );
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> _getItems(
    String path,
    String context,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri(path))
          .timeout(const Duration(seconds: 90));
      final decoded = await _decodeJsonResponse(response, context: context);
      final items = decoded['items'];
      return items is List
          ? items.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const [];
    } on TimeoutException {
      throw FormatException(
        '$context timed out while OpenMontage loaded its capability registry.',
      );
    } on SocketException {
      throw FormatException(
        'Cannot connect to OpenMontage at $baseUrl. Check the backend and BACKEND_URL.',
      );
    } on http.ClientException {
      throw FormatException(
        'Cannot connect to OpenMontage at $baseUrl. Check the backend and BACKEND_URL.',
      );
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> getCapabilities() =>
      _getItems('/api/capabilities', 'Load capabilities');

  static Future<Map<String, dynamic>> getRuntimeHardware() async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/runtime/hardware'))
          .timeout(const Duration(seconds: 90));
      return await _decodeJsonResponse(response, context: 'Load host hardware');
    } on TimeoutException {
      throw const FormatException('Host hardware detection timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> getProviders({
    String? capability,
  }) => _getItems(
    '/api/providers${capability == null ? '' : '?capability=${Uri.encodeQueryComponent(capability)}'}',
    'Load providers',
  );

  static Future<List<Map<String, dynamic>>> getModels({
    String? capability,
    String? provider,
    String? tool,
  }) {
    final query = <String, String>{
      'capability': ?capability,
      'provider': ?provider,
      'tool': ?tool,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return _getItems('/api/models$suffix', 'Load models');
  }

  static Future<Map<String, dynamic>> createProject({required String name}) =>
      _postJson('/api/projects', {'name': name}, 'Create project');

  static Future<Map<String, dynamic>> createVideoGenerationJob({
    required String projectId,
    required List<String> assetIds,
    required Map<String, dynamic> parameters,
  }) => _postJson(
    '/api/projects/$projectId/jobs',
    {
      'type': 'capability',
      'capability': 'video_generation',
      'operation': 'generate',
      'project_id': projectId,
      'input_asset_ids': assetIds,
      'parameters': parameters,
    },
    'Create video generation job',
    timeout: const Duration(minutes: 5),
  );

  static Future<Map<String, dynamic>> createImageGenerationJob({
    required String projectId,
    required List<String> assetIds,
    required Map<String, dynamic> parameters,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'image_generation',
    'operation': 'generate',
    'project_id': projectId,
    'input_asset_ids': assetIds,
    'parameters': parameters,
  }, 'Create image generation job');

  static Future<Map<String, dynamic>> createTtsGenerationJob({
    required String projectId,
    required Map<String, dynamic> parameters,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'tts',
    'operation': 'generate',
    'project_id': projectId,
    'input_asset_ids': const <String>[],
    'parameters': parameters,
  }, 'Create text-to-speech job');

  static Future<Map<String, dynamic>> createMusicGenerationJob({
    required String projectId,
    required Map<String, dynamic> parameters,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'music_generation',
    'operation': 'generate',
    'project_id': projectId,
    'input_asset_ids': const <String>[],
    'parameters': parameters,
  }, 'Create music generation job');

  static Future<Map<String, dynamic>> createTranscriptionJob({
    required String projectId,
    required String assetId,
    required Map<String, dynamic> parameters,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'analysis',
    'operation': 'transcribe',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': parameters,
  }, 'Create transcription job');

  static Future<List<Map<String, dynamic>>> getProjects() =>
      _getItems('/api/projects', 'Load projects');

  static Future<List<Map<String, dynamic>>> getProjectAssets(
    String projectId,
  ) => _getItems('/api/projects/$projectId/assets', 'Load project assets');

  static Future<Map<String, dynamic>> uploadMediaAsset({
    required String projectId,
    required File file,
  }) async {
    final client = http.Client();
    try {
      final request = http.StreamedRequest(
        'POST',
        _uri(
          '/api/projects/$projectId/assets?filename=${Uri.encodeQueryComponent(file.uri.pathSegments.last)}',
        ),
      );
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = await file.length();
      final sendFuture = client.send(request);
      await request.sink.addStream(file.openRead());
      await request.sink.close();
      final streamed = await sendFuture.timeout(const Duration(minutes: 3));
      return await _decodeJsonResponse(
        await http.Response.fromStream(streamed),
        context: 'Upload media',
      );
    } on TimeoutException {
      throw const FormatException('Media upload timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> uploadVideoAsset({
    required String projectId,
    required File file,
  }) async {
    final client = http.Client();
    try {
      final request = http.StreamedRequest(
        'POST',
        _uri(
          '/api/projects/$projectId/assets?filename=${Uri.encodeQueryComponent(file.uri.pathSegments.last)}',
        ),
      );
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = await file.length();
      final sendFuture = client.send(request);
      await request.sink.addStream(file.openRead());
      await request.sink.close();
      final streamed = await sendFuture.timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      return await _decodeJsonResponse(response, context: 'Upload video');
    } on TimeoutException {
      throw const FormatException('Video upload timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> uploadAudioAsset({
    required String projectId,
    required File file,
  }) async {
    final client = http.Client();
    try {
      final request = http.StreamedRequest(
        'POST',
        _uri(
          '/api/projects/$projectId/assets?filename=${Uri.encodeQueryComponent(file.uri.pathSegments.last)}',
        ),
      );
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = await file.length();
      final sendFuture = client.send(request);
      await request.sink.addStream(file.openRead());
      await request.sink.close();
      final streamed = await sendFuture.timeout(const Duration(minutes: 3));
      return await _decodeJsonResponse(
        await http.Response.fromStream(streamed),
        context: 'Upload audio',
      );
    } on TimeoutException {
      throw const FormatException('Audio upload timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> createAudioEnhancementJob({
    required String projectId,
    required String assetId,
    required String preset,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'audio_processing',
    'operation': 'enhance',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'preset': preset},
  }, 'Create audio enhancement job');

  static Future<Map<String, dynamic>> createAudioVolumeJob({
    required String projectId,
    required String assetId,
    required double volume,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'audio_processing',
    'operation': 'volume',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'volume': volume},
  }, 'Create audio volume job');

  static Future<Map<String, dynamic>> createAudioTrimJob({
    required String projectId,
    required String assetId,
    required double startSeconds,
    required double endSeconds,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'audio_processing',
    'operation': 'trim',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'start_seconds': startSeconds, 'end_seconds': endSeconds},
  }, 'Create audio trim job');

  static Future<Map<String, dynamic>> createSubtitleGenerationJob({
    required String projectId,
    required String format,
    required List<Map<String, dynamic>> segments,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'subtitle',
    'operation': 'generate',
    'project_id': projectId,
    'input_asset_ids': const [],
    'parameters': {'format': format, 'segments': segments},
  }, 'Create subtitle job');

  static Future<Map<String, dynamic>> createSubtitleBurnJob({
    required String projectId,
    required String videoAssetId,
    required String subtitleArtifactId,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'video_post',
    'operation': 'burn_subtitles',
    'project_id': projectId,
    'input_asset_ids': [videoAssetId],
    'parameters': {'subtitle_artifact_id': subtitleArtifactId},
  }, 'Create subtitle burn job');

  static Future<Map<String, dynamic>> createVideoTrimJob({
    required String projectId,
    required String assetId,
    required double start,
    required double end,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'video_post',
    'operation': 'trim',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'start': start, 'end': end},
  }, 'Create trim job');

  static Future<Map<String, dynamic>> createVideoCropJob({
    required String projectId,
    required String assetId,
    required String targetAspect,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'video_post',
    'operation': 'crop',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'target_aspect': targetAspect},
  }, 'Create crop job');

  static Future<Map<String, dynamic>> createVideoSpeedJob({
    required String projectId,
    required String assetId,
    required double speedFactor,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'video_post',
    'operation': 'speed',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'speed_factor': speedFactor},
  }, 'Create speed adjustment job');

  static Future<Map<String, dynamic>> createVideoRenderJob({
    required String projectId,
    required List<String> assetIds,
    String transition = 'cut',
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'video_post',
    'operation': 'render',
    'project_id': projectId,
    'input_asset_ids': assetIds,
    'parameters': {'transition': transition},
  }, 'Create render job');

  static Future<Map<String, dynamic>> createColorGradeJob({
    required String projectId,
    required String assetId,
    required String profile,
    double intensity = 1,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'enhancement',
    'operation': 'color_grade',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': {'profile': profile, 'intensity': intensity},
  }, 'Create color grade job');

  static Future<Map<String, dynamic>> createUpscaleJob({
    required String projectId,
    required String assetId,
    required Map<String, dynamic> parameters,
  }) => _postJson('/api/projects/$projectId/jobs', {
    'type': 'capability',
    'capability': 'enhancement',
    'operation': 'upscale',
    'project_id': projectId,
    'input_asset_ids': [assetId],
    'parameters': parameters,
  }, 'Create upscale job');

  static Future<Map<String, dynamic>> getJob(String jobId) async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/jobs/$jobId'))
          .timeout(const Duration(seconds: 10));
      return await _decodeJsonResponse(response, context: 'Job status');
    } on TimeoutException {
      throw const FormatException('Job status request timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> getJobArtifacts(
    String jobId,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/jobs/$jobId/artifacts'))
          .timeout(const Duration(seconds: 10));
      final decoded = await _decodeJsonResponse(
        response,
        context: 'Job artifacts',
      );
      final items = decoded['items'];
      return items is List
          ? items.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const [];
    } on TimeoutException {
      throw const FormatException('Artifact request timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static Future<String> getArtifactText(String artifactId) async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/artifacts/$artifactId/file'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_safeApiError(response));
      }
      return response.body;
    } on TimeoutException {
      throw const FormatException('Artifact download timed out');
    } on http.ClientException {
      throw const FormatException('Backend is unavailable');
    } finally {
      client.close();
    }
  }

  static String resolveApiUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    return normalized.startsWith('/')
        ? '$baseUrl$normalized'
        : '$baseUrl/$normalized';
  }

  static String resolveVideoUrl(String? rawUrl, {String? jobId}) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return jobId == null ? '' : '$baseUrl/api/videos/$jobId/file';
    }

    final normalized = rawUrl.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    if (normalized.startsWith('/')) {
      return '$baseUrl$normalized';
    }
    return '$baseUrl$normalized';
  }

  static String getVideoUrl(String jobId) => '$baseUrl/api/videos/$jobId/file';
}
