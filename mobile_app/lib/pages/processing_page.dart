import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backend_api.dart';
import '../services/project_storage.dart';
import '../services/library_storage.dart';
import '../models/processing_job.dart';
import 'project_detail_page.dart';

class ProcessingPage extends StatefulWidget {
  final String jobId;
  final String projectId;
  final String title;
  final String prompt;
  final String style;
  final String duration;
  final int assetCount;
  final bool mockMode;
  final String aspectRatio, model, provider, mode, resolution;
  final int fps;
  final int? seed;
  final String? workflowId, pipelineId;
  final String? templateId;
  final Map<String, dynamic> templateParameters;
  final String capabilityId;

  const ProcessingPage({
    super.key,
    required this.jobId,
    required this.projectId,
    required this.title,
    required this.prompt,
    required this.style,
    required this.duration,
    required this.assetCount,
    this.mockMode = false,
    this.aspectRatio = '16:9',
    this.model = 'Auto',
    this.provider = 'auto',
    this.mode = 'Text to Video',
    this.resolution = '720p',
    this.fps = 24,
    this.seed,
    this.workflowId,
    this.pipelineId,
    this.templateId,
    this.templateParameters = const {},
    this.capabilityId = 'video_generation',
  });

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage>
    with SingleTickerProviderStateMixin {
  double progress = 0.0;
  int currentStep = 0;
  String? errorMessage;
  DateTime? _pollStartedAt;
  Timer? _pollTimer;
  bool _isDisposed = false;
  ProcessingJobStatus _jobStatus = ProcessingJobStatus.queued;

  late AnimationController pulseController;

  late final List<String> steps;
  String? _backendCurrentStep;
  ProcessingJob? _job;

  String get _statusLabel => switch (_jobStatus) {
    ProcessingJobStatus.queued => 'queued',
    ProcessingJobStatus.validating => 'validating',
    ProcessingJobStatus.planning => 'planning',
    ProcessingJobStatus.running => 'running',
    ProcessingJobStatus.rendering => 'rendering',
    ProcessingJobStatus.completed => 'completed',
    ProcessingJobStatus.failed => 'failed',
    ProcessingJobStatus.cancelled => 'cancelled',
  };

  @override
  void initState() {
    super.initState();

    steps = widget.mockMode
        ? [
            'Validating request (demo)',
            'Planning workflow (demo)',
            'Processing ${widget.capabilityId.replaceAll('_', ' ')} (demo)',
            'Saving local result (demo)',
          ]
        : [
            'Queued',
            'Preparing job...',
            'Processing ${widget.capabilityId.replaceAll('_', ' ')}...',
            'Saving artifacts...',
          ];
    _jobStatus = widget.mockMode
        ? ProcessingJobStatus.running
        : ProcessingJobStatus.queued;

    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    _pollStartedAt ??= DateTime.now();
    if (widget.mockMode) {
      _startMockProgress();
    } else {
      unawaited(_startPolling());
    }
  }

  void _startMockProgress() {
    _jobStatus = ProcessingJobStatus.running;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      setState(() {
        progress = (progress + 0.2).clamp(0.0, 1.0);
        currentStep = (progress * steps.length).floor().clamp(
          0,
          steps.length - 1,
        );
      });
      if (progress >= 1) {
        _jobStatus = ProcessingJobStatus.completed;
        timer.cancel();
        unawaited(_completeProject());
      }
    });
  }

  Future<void> _completeProject({String? videoUrl}) async {
    try {
      final artifacts = _job?.artifacts ?? const <ProcessingJobArtifact>[];
      for (final artifact in artifacts) {
        final url = artifact.url;
        if (url == null || url.isEmpty) continue;
        await LibraryStorage.upsertRemoteAsset(
          id: artifact.id,
          name: 'Rendered video',
          type: artifact.type,
          projectId: widget.projectId,
          remoteUrl: BackendApi.resolveApiUrl(url),
          mimeType: artifact.mimeType,
        );
      }
      final finalProject = await ProjectStorage.saveProject(
        id: widget.projectId,
        projectId: widget.projectId,
        title: widget.title,
        prompt: widget.prompt,
        style: widget.style,
        duration: widget.duration,
        assetCount: widget.assetCount,
        status: 'Completed',
        videoUrl: videoUrl,
        jobId: widget.jobId,
        aspectRatio: widget.aspectRatio,
        model: widget.model,
        provider: widget.provider,
        mode: widget.mode,
        resolution: widget.resolution,
        fps: widget.fps,
        seed: widget.seed,
        workflowId: widget.workflowId,
        pipelineId: widget.pipelineId,
        templateId: widget.templateId,
        templateParameters: widget.templateParameters,
      );
      if (!mounted || _isDisposed) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ProjectDetailPage(
            projectId: finalProject['id']?.toString(),
            title: finalProject['title']?.toString(),
            prompt: widget.prompt,
            style: widget.style,
            duration: widget.duration,
            assetCount: widget.assetCount,
            videoUrl: finalProject['videoUrl']?.toString(),
            jobId: widget.jobId,
            aspectRatio: widget.aspectRatio,
            model: widget.model,
            provider: widget.provider,
            workflowId: widget.workflowId,
            pipelineId: widget.pipelineId,
            templateId: widget.templateId,
            templateParameters: widget.templateParameters,
            mode: widget.mode,
            resolution: widget.resolution,
            fps: widget.fps,
            seed: widget.seed,
          ),
        ),
      );
    } catch (error) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _jobStatus = ProcessingJobStatus.failed;
        errorMessage = error.toString();
        currentStep = steps.length - 1;
      });
    }
  }

  Future<void> _cancelDemoJob() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel generation?'),
        content: const Text(
          'The mock job will stop and no project will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Generating'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Job'),
          ),
        ],
      ),
    );
    if (shouldCancel == true && mounted) {
      _pollTimer?.cancel();
      setState(() => _jobStatus = ProcessingJobStatus.cancelled);
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'validating':
        return 'Validating request...';
      case 'planning':
        return 'Planning workflow...';
      case 'queued':
        return 'Job queued';
      case 'initializing':
        return 'Preparing job...';
      case 'processing':
      case 'running':
        return 'Processing ${widget.capabilityId.replaceAll('_', ' ')}...';
      case 'rendering':
        return 'Rendering output...';
      case 'completed':
        return 'Job completed';
      case 'failed':
        return 'Job failed';
      case 'cancelled':
        return 'Job cancelled';
      default:
        return 'Processing job...';
    }
  }

  Future<void> _startPolling() async {
    if (!mounted || _isDisposed) return;

    final startedAt = _pollStartedAt ??= DateTime.now();
    final timeout = widget.capabilityId == 'video_post'
        ? const Duration(minutes: 10)
        : const Duration(seconds: 90);
    if (DateTime.now().difference(startedAt) > timeout) {
      if (!mounted || _isDisposed) return;
      setState(() {
        errorMessage = 'The job timed out. Please try again.';
        progress = 1.0;
        currentStep = steps.length - 1;
      });
      return;
    }

    try {
      final response = await BackendApi.getJob(widget.jobId)
          .timeout(const Duration(seconds: 8));

      if (response['status']?.toString() == 'completed') {
        response['artifacts'] = await BackendApi.getJobArtifacts(widget.jobId);
      }

      if (!mounted || _isDisposed) return;

      final job = ProcessingJob.fromJson(response);
      setState(() {
        _job = job;
        progress = job.progress;
        _backendCurrentStep = job.currentStep;
        _jobStatus = job.status;
        currentStep = _statusIndex(job.status);
        errorMessage = job.error;
      });

      if (job.status == ProcessingJobStatus.completed) {
        final videoUrl =
            response['video_url']?.toString() ??
            job.artifacts
                .where((item) => item.type == 'video')
                .firstOrNull
                ?.url;
        await _completeProject(videoUrl: videoUrl);
        return;
      }

      if (job.status == ProcessingJobStatus.failed) {
        if (!mounted || _isDisposed) return;
        setState(() {
          errorMessage = job.error ?? 'Job failed.';
          progress = 1.0;
          currentStep = _statusIndex(ProcessingJobStatus.failed);
        });
        return;
      }
      if (job.status == ProcessingJobStatus.cancelled) return;
    } on TimeoutException {
      if (!mounted || _isDisposed) return;
      setState(() {
        errorMessage = 'Backend is slow to respond. Please wait.';
      });
    } on FormatException catch (error) {
      if (!mounted || _isDisposed) return;
      setState(() {
        errorMessage = error.message;
        progress = 1.0;
        currentStep = _statusIndex(ProcessingJobStatus.failed);
      });
      return;
    } catch (error) {
      if (!mounted || _isDisposed) return;
      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
        progress = 1.0;
        currentStep = _statusIndex(ProcessingJobStatus.failed);
      });
      return;
    }

    if (!mounted || _isDisposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isDisposed) {
        unawaited(_startPolling());
      }
    });
  }

  int _statusIndex(ProcessingJobStatus status) {
    switch (status) {
      case ProcessingJobStatus.validating:
      case ProcessingJobStatus.queued:
        return 0;
      case ProcessingJobStatus.planning:
        return 1;
      case ProcessingJobStatus.running:
        return 2;
      case ProcessingJobStatus.cancelled:
      case ProcessingJobStatus.rendering:
      case ProcessingJobStatus.completed:
      case ProcessingJobStatus.failed:
        return 3;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pollTimer?.cancel();
    pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressPercent = (progress * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.mockMode && _jobStatus == ProcessingJobStatus.running)
            IconButton(
              tooltip: 'Cancel generation',
              onPressed: _cancelDemoJob,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              ScaleTransition(
                scale: pulseController,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                _jobStatus == ProcessingJobStatus.cancelled
                    ? 'Job Cancelled'
                    : errorMessage == null
                    ? 'Processing ${widget.capabilityId.replaceAll('_', ' ')}'
                    : 'Job update',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              Text(
                _jobStatus == ProcessingJobStatus.cancelled
                    ? 'The mock job was cancelled. No project was saved.'
                    : errorMessage == null
                    ? widget.mockMode
                          ? 'Frontend preview only · no AI provider is being called.'
                          : _statusText(_statusNameFromStep(currentStep))
                    : errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Please try again or check backend availability.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 28),

              // Progress
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 10,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$progressPercent%',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              // Current step
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        errorMessage == null
                            ? (_backendCurrentStep?.isNotEmpty == true
                                  ? _backendCurrentStep!
                                  : steps[currentStep])
                            : errorMessage!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),

                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Generic job information
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Job Details · ${widget.mockMode ? 'Demo' : 'Backend'}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 14),

                    _infoRow(
                      context,
                      Icons.movie_outlined,
                      'Capability',
                      widget.capabilityId,
                    ),

                    if (widget.workflowId != null) ...[
                      const SizedBox(height: 10),
                      _infoRow(
                        context,
                        Icons.account_tree_outlined,
                        'Workflow',
                        widget.workflowId!,
                      ),
                    ],

                    if (widget.pipelineId != null) ...[
                      const SizedBox(height: 10),
                      _infoRow(
                        context,
                        Icons.account_tree_outlined,
                        'Pipeline',
                        widget.pipelineId!,
                      ),
                    ],

                    const SizedBox(height: 10),
                    _infoRow(
                      context,
                      Icons.sync_outlined,
                      'Status',
                      errorMessage != null ? 'Failed' : _statusLabel,
                    ),

                    const SizedBox(height: 10),
                    _infoRow(
                      context,
                      Icons.tag_outlined,
                      'Job ID',
                      widget.jobId,
                    ),

                    if (_job?.artifacts.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      _infoRow(
                        context,
                        Icons.attach_file,
                        'Artifacts',
                        '${_job!.artifacts.length}',
                      ),
                    ],

                    const SizedBox(height: 10),

                    _infoRow(
                      context,
                      Icons.timer_outlined,
                      'Duration',
                      widget.duration,
                    ),

                    const SizedBox(height: 10),

                    _infoRow(
                      context,
                      Icons.folder_outlined,
                      'Assets',
                      '${widget.assetCount} selected',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (widget.mockMode && errorMessage != null)
                FilledButton(
                  onPressed: () {
                    setState(() {
                      errorMessage = null;
                      progress = 0;
                      currentStep = 0;
                    });
                    _startMockProgress();
                  },
                  child: const Text('Try Again'),
                ),
              if (widget.mockMode &&
                  (_jobStatus == ProcessingJobStatus.cancelled ||
                      errorMessage != null))
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Create'),
                ),

              Text(
                widget.mockMode
                    ? 'Frontend demo job · no generation service is connected.'
                    : 'Waiting for the backend job to finish.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _statusNameFromStep(int index) {
    if (index < 0 || index >= steps.length) {
      return 'queued';
    }
    switch (index) {
      case 0:
        return 'queued';
      case 1:
        return 'initializing';
      case 2:
        return 'processing';
      case 3:
        return 'rendering';
      default:
        return 'processing';
    }
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),

        const SizedBox(width: 10),

        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),

        const SizedBox(width: 8),

        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
