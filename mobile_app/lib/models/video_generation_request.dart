enum VideoGenerationState {
  idle,
  validating,
  generating,
  completed,
  failed,
  cancelled,
}

class VideoGenerationRequest {
  const VideoGenerationRequest({
    required this.projectName,
    required this.prompt,
    required this.mode,
    required this.model,
    required this.provider,
    required this.style,
    required this.duration,
    required this.aspectRatio,
    required this.resolution,
    required this.negativePrompt,
    required this.guidance,
    required this.fps,
    required this.assetIds,
    this.workflowId,
    this.pipelineId,
    this.templateId,
    this.templateParameters = const {},
    this.seed,
  });

  final String projectName, prompt, mode, model, provider, style;
  final int duration, fps;
  final String aspectRatio, resolution, negativePrompt;
  final int? seed;
  final String? workflowId, pipelineId;
  final String? templateId;
  final Map<String, dynamic> templateParameters;
  final double guidance;
  final List<String> assetIds;
}
