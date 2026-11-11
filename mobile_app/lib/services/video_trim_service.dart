import 'dart:io';

import 'backend_api.dart';

/// Replaceable service boundary for the Phase 1 video trim workflow.
abstract interface class VideoTrimService {
  Future<Map<String, dynamic>> createProject(String name);
  Future<Map<String, dynamic>> uploadVideo(String projectId, File file);
  Future<Map<String, dynamic>> createTrimJob({
    required String projectId,
    required String assetId,
    required double start,
    required double end,
  });
  Future<Map<String, dynamic>> createCropJob({
    required String projectId,
    required String assetId,
    required String targetAspect,
  });
  Future<Map<String, dynamic>> getJob(String jobId);
  Future<List<Map<String, dynamic>>> getArtifacts(String jobId);
  String resolveUrl(String url);
}

class BackendVideoTrimService implements VideoTrimService {
  const BackendVideoTrimService();

  @override
  Future<Map<String, dynamic>> createProject(String name) =>
      BackendApi.createProject(name: name);

  @override
  Future<Map<String, dynamic>> uploadVideo(String projectId, File file) =>
      BackendApi.uploadVideoAsset(projectId: projectId, file: file);

  @override
  Future<Map<String, dynamic>> createTrimJob({
    required String projectId,
    required String assetId,
    required double start,
    required double end,
  }) => BackendApi.createVideoTrimJob(
    projectId: projectId,
    assetId: assetId,
    start: start,
    end: end,
  );

  @override
  Future<Map<String, dynamic>> createCropJob({
    required String projectId,
    required String assetId,
    required String targetAspect,
  }) => BackendApi.createVideoCropJob(
    projectId: projectId,
    assetId: assetId,
    targetAspect: targetAspect,
  );

  @override
  Future<Map<String, dynamic>> getJob(String jobId) => BackendApi.getJob(jobId);

  @override
  Future<List<Map<String, dynamic>>> getArtifacts(String jobId) =>
      BackendApi.getJobArtifacts(jobId);

  @override
  String resolveUrl(String url) => BackendApi.resolveApiUrl(url);
}
