import 'dart:async';

import '../models/video_generation_request.dart';

class MockGenerationService {
  static Future<Map<String, dynamic>> createJob(
    VideoGenerationRequest request,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return {
      'id': id,
      'projectId': id,
      'jobId': 'mock-$id',
      'status': 'processing',
      'progress': 0,
      'request': request,
      'createdAt': DateTime.now(),
    };
  }
}
