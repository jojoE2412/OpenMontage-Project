enum ProcessingJobStatus {
  queued,
  validating,
  planning,
  running,
  rendering,
  completed,
  failed,
  cancelled,
}

class ProcessingJobArtifact {
  const ProcessingJobArtifact({
    required this.id,
    required this.type,
    this.url,
    this.path,
    this.mimeType,
  });

  final String id;
  final String type;
  final String? url;
  final String? path;
  final String? mimeType;

  factory ProcessingJobArtifact.fromJson(Map<String, dynamic> json) =>
      ProcessingJobArtifact(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'file',
        url: json['url']?.toString() ?? json['download_url']?.toString(),
        path: json['path']?.toString(),
        mimeType: json['mime_type']?.toString() ?? json['mimeType']?.toString(),
      );
}

class ProcessingJob {
  const ProcessingJob({
    required this.id,
    required this.status,
    required this.progress,
    this.currentStep,
    this.capability,
    this.pipelineId,
    this.error,
    this.artifacts = const [],
    this.raw = const {},
  });

  final String id;
  final ProcessingJobStatus status;
  final double progress;
  final String? currentStep;
  final String? capability;
  final String? pipelineId;
  final String? error;
  final List<ProcessingJobArtifact> artifacts;
  final Map<String, dynamic> raw;

  factory ProcessingJob.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString().toLowerCase() ?? 'queued';
    final status = switch (rawStatus) {
      'queued' => ProcessingJobStatus.queued,
      'validating' => ProcessingJobStatus.validating,
      'planning' => ProcessingJobStatus.planning,
      'processing' ||
      'running' ||
      'initializing' => ProcessingJobStatus.running,
      'rendering' => ProcessingJobStatus.rendering,
      'completed' || 'complete' || 'succeeded' => ProcessingJobStatus.completed,
      'failed' || 'error' => ProcessingJobStatus.failed,
      'cancelled' || 'canceled' => ProcessingJobStatus.cancelled,
      _ => ProcessingJobStatus.queued,
    };
    final rawProgress = json['progress'];
    final progress = rawProgress is num
        ? (rawProgress > 1 ? rawProgress / 100 : rawProgress.toDouble()).clamp(
            0.0,
            1.0,
          )
        : status == ProcessingJobStatus.completed
        ? 1.0
        : 0.0;
    final artifacts = json['artifacts'];
    return ProcessingJob(
      id: json['id']?.toString() ?? json['job_id']?.toString() ?? '',
      status: status,
      progress: progress,
      currentStep: json['current_step']?.toString(),
      capability: json['capability']?.toString(),
      pipelineId: json['pipeline_id']?.toString(),
      error: json['error']?.toString(),
      artifacts: artifacts is List
          ? artifacts
                .whereType<Map>()
                .map(
                  (item) => ProcessingJobArtifact.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
      raw: json,
    );
  }
}
