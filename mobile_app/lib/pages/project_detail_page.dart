import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/backend_api.dart';
import '../services/library_storage.dart';
import '../services/project_storage.dart';
import 'ai_video_generator_page.dart';
import 'video_editor_page.dart';
import 'processing_page.dart';

class ProjectDetailPage extends StatefulWidget {
  final String? projectId;
  final String? title;
  final String? videoUrl;
  final String? jobId;
  final String prompt;
  final String style;
  final String duration;
  final int assetCount;
  final String aspectRatio;
  final String model;
  final String provider;
  final String? workflowId, pipelineId;
  final String? templateId;
  final Map<String, dynamic> templateParameters;
  final String mode, resolution;
  final int fps;
  final int? seed;

  const ProjectDetailPage({
    super.key,
    this.projectId,
    this.title,
    this.videoUrl,
    this.jobId,
    required this.prompt,
    required this.style,
    required this.duration,
    required this.assetCount,
    this.aspectRatio = '16:9',
    this.model = 'Auto',
    this.provider = 'auto',
    this.workflowId,
    this.pipelineId,
    this.templateId,
    this.templateParameters = const {},
    this.mode = 'Text to Video',
    this.resolution = '720p',
    this.fps = 24,
    this.seed,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late String projectTitle;
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;
  bool _isDisposing = false;
  bool _isInlinePlaying = false;
  String? _videoError;
  bool _rendering = false;
  bool _uploadingVideos = false;
  int? _backendVideoCount;

  String get prompt => widget.prompt;
  String get style => widget.style;
  String get duration => widget.duration;
  int get assetCount => widget.assetCount;

  @override
  void initState() {
    super.initState();
    projectTitle = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : _titleFromPrompt();
    _initVideoController();
  }

  Future<void> _initVideoController() async {
    final rawUrl = widget.videoUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return;
    }

    if (!mounted || _isDisposing) return;

    setState(() {
      _isVideoLoading = true;
      _videoError = null;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(BackendApi.resolveVideoUrl(rawUrl, jobId: widget.jobId)),
    );

    _videoController = controller;

    try {
      await controller.initialize();
      if (!mounted || _isDisposing) {
        controller.dispose();
        return;
      }
      setState(() {
        _isVideoLoading = false;
        _isInlinePlaying = true;
      });
      controller.setLooping(true);
      controller.play();
    } catch (error) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isVideoLoading = false;
        _videoError = error.toString();
      });
    }
  }

  Future<void> _renderProjectVideos() async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This project is not connected to OpenMontage storage.',
          ),
        ),
      );
      return;
    }
    setState(() => _rendering = true);
    try {
      final assets = await BackendApi.getProjectAssets(projectId);
      final videos = assets.where((asset) => asset['type'] == 'video').toList()
        ..sort((a, b) {
          final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
          final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
          if (aDate == null || bDate == null) return 0;
          return aDate.compareTo(bDate);
        });
      if (videos.length < 2) {
        throw const FormatException(
          'Add at least two video assets to this OpenMontage project before rendering.',
        );
      }
      if (videos.length > 30) {
        throw const FormatException(
          'A render can include at most 30 video assets.',
        );
      }
      if (mounted) setState(() => _backendVideoCount = videos.length);
      final job = await BackendApi.createVideoRenderJob(
        projectId: projectId,
        assetIds: videos.map((asset) => asset['id'].toString()).toList(),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessingPage(
            jobId: job['id'].toString(),
            projectId: projectId,
            title: projectTitle,
            prompt: prompt,
            style: 'FFmpeg Render',
            duration: duration,
            assetCount: videos.length,
            capabilityId: 'video_post',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _addProjectVideos() async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This project is not connected to OpenMontage storage.',
          ),
        ),
      );
      return;
    }
    final picked = await FilePicker.pickFiles(type: FileType.video);
    if (!mounted || picked.isEmpty) return;
    setState(() => _uploadingVideos = true);
    var uploaded = 0;
    var failed = 0;
    try {
      for (final file in picked) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          failed++;
          continue;
        }
        try {
          final asset = await BackendApi.uploadMediaAsset(
            projectId: projectId,
            file: File(path),
          );
          await LibraryStorage.upsertRemoteAsset(
            id: asset['id'].toString(),
            name: asset['name']?.toString() ?? file.name,
            type: 'video',
            projectId: projectId,
            remoteUrl: BackendApi.resolveApiUrl(asset['file_url'].toString()),
            mimeType: asset['mime_type']?.toString(),
          );
          uploaded++;
        } catch (_) {
          failed++;
        }
      }
      final assets = await BackendApi.getProjectAssets(projectId);
      if (mounted) {
        setState(
          () => _backendVideoCount = assets
              .where((asset) => asset['type'] == 'video')
              .length,
        );
      }
      if (!mounted) return;
      final message = uploaded == 0
          ? 'No videos were uploaded.'
          : '$uploaded video${uploaded == 1 ? '' : 's'} added to this project${failed == 0 ? '.' : '; $failed failed.'}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingVideos = false);
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _videoController?.dispose();
    super.dispose();
  }

  String _titleFromPrompt() {
    if (prompt.isEmpty) {
      return 'Untitled Video';
    }

    final words = prompt.trim().split(RegExp(r'\s+'));

    if (words.length <= 6) {
      return prompt.trim();
    }

    return '${words.take(6).join(' ')}...';
  }

  Future<void> _editTitle() async {
    if (!mounted) return;

    final controller = TextEditingController(text: projectTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Project Title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project title'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              return;
            }
            Navigator.of(dialogContext, rootNavigator: true).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                return;
              }
              Navigator.of(dialogContext, rootNavigator: true).pop(trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.dispose();
        }
      });
    }

    if (!mounted) return;

    final normalizedTitle = newTitle?.trim() ?? '';
    if (normalizedTitle.isEmpty) {
      return;
    }

    if (widget.projectId != null) {
      await ProjectStorage.updateProjectTitle(
        widget.projectId!,
        normalizedTitle,
      );
    }

    if (!mounted) return;
    setState(() {
      projectTitle = normalizedTitle;
    });
  }

  String get formattedDuration {
    if (duration.endsWith('s')) {
      final seconds = int.tryParse(duration.substring(0, duration.length - 1));

      if (seconds != null) {
        if (seconds >= 60) {
          final minutes = seconds ~/ 60;
          final remainingSeconds = seconds % 60;

          if (remainingSeconds == 0) {
            return '$minutes minute${minutes > 1 ? 's' : ''}';
          }

          return '$minutes min $remainingSeconds sec';
        }

        return '$seconds seconds';
      }
    }

    return duration;
  }

  void _showVideoPreview(BuildContext context) {
    if (!mounted) return;

    final controller = _videoController;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Video Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF202A45), Color(0xFF53648C)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: controller != null && controller.value.isInitialized
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        )
                      : widget.videoUrl == null || widget.videoUrl!.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_circle_fill_rounded,
                                size: 58,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Demo Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.duration} · ${widget.aspectRatio}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _videoError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Unable to load video preview.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),

                const SizedBox(height: 16),

                Text(
                  widget.videoUrl == null || widget.videoUrl!.isEmpty
                      ? 'This project is currently using a demo result.'
                      : _videoError == null
                      ? 'Video preview is ready.'
                      : 'Video preview unavailable.',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleInlinePlayback() {
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        controller.pause();
        setState(() => _isInlinePlaying = false);
      } else {
        controller.play();
        setState(() => _isInlinePlaying = true);
      }
      return;
    }
    setState(() => _isInlinePlaying = !_isInlinePlaying);
  }

  void _shareProject(BuildContext context) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share feature will be available soon.')),
    );
  }

  void _showMoreOptions(BuildContext context) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Video'),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoEditorPage(
                        projectId: widget.projectId,
                        title: projectTitle,
                        prompt: prompt,
                        duration: duration,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Project'),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete Project?'),
                      content: const Text(
                        'This removes the project from this device.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (!context.mounted) return;
                  if (confirmed == true && widget.projectId != null) {
                    await ProjectStorage.deleteProject(widget.projectId!);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Detail'),
        actions: [
          IconButton(
            onPressed: () {
              _showMoreOptions(context);
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =========================
            // VIDEO PREVIEW
            // =========================
            GestureDetector(
              onTap: _toggleInlinePlayback,
              child: Container(
                width: double.infinity,
                height: (MediaQuery.sizeOf(context).width - 40) * 9 / 16,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF202A45),
                      Color(0xFF53648C),
                      Color(0xFFCE936C),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child:
                    _videoController != null &&
                        _videoController!.value.isInitialized
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    : widget.videoUrl == null || widget.videoUrl!.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isInlinePlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 64,
                              color: Colors.white,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Demo Preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.movie_outlined,
                            size: 64,
                            color: Colors.white38,
                          ),
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isVideoLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 38,
                                  ),
                          ),
                        ],
                      ),
              ),
            ),

            Row(
              children: [
                Text(
                  _isInlinePlaying ? '00:03' : '00:00',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: _isInlinePlaying ? .42 : 0,
                    onChanged: (value) =>
                        setState(() => _isInlinePlaying = value > 0),
                  ),
                ),
                Text(duration, style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  tooltip: 'Fullscreen preview',
                  onPressed: () => _showVideoPreview(context),
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // =========================
            // PROJECT TITLE
            // =========================
            Row(
              children: [
                Expanded(
                  child: Text(
                    projectTitle,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _editTitle,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),

                const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    widget.videoUrl == null
                        ? 'Demo Result · Video completed'
                        : 'Video completed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // =========================
            // PROJECT INFORMATION
            // =========================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _infoRow(
                    context,
                    Icons.movie_creation_outlined,
                    'Style',
                    style,
                  ),

                  const SizedBox(height: 16),

                  _infoRow(
                    context,
                    Icons.timer_outlined,
                    'Duration',
                    formattedDuration,
                  ),

                  const SizedBox(height: 16),

                  _infoRow(
                    context,
                    Icons.folder_outlined,
                    'Assets',
                    '$assetCount selected',
                  ),

                  const SizedBox(height: 16),
                  _infoRow(
                    context,
                    Icons.crop_16_9,
                    'Aspect Ratio',
                    widget.aspectRatio,
                  ),
                  const SizedBox(height: 16),
                  _infoRow(
                    context,
                    Icons.auto_awesome_outlined,
                    'Model',
                    widget.model,
                  ),

                  const SizedBox(height: 16),
                  _infoRow(
                    context,
                    Icons.hub_outlined,
                    'Provider',
                    widget.provider,
                  ),
                  const SizedBox(height: 16),
                  _infoRow(
                    context,
                    Icons.payments_outlined,
                    'Estimated Cost',
                    'Unavailable',
                  ),

                  const SizedBox(height: 16),

                  _infoRow(
                    context,
                    Icons.calendar_today_outlined,
                    'Created',
                    'Today',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // =========================
            // PROMPT
            // =========================
            Text(
              'Prompt',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                prompt.isEmpty ? 'No prompt provided.' : prompt,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

            const SizedBox(height: 28),

            // =========================
            // PLAY VIDEO
            // =========================
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoEditorPage(
                          projectId: widget.projectId,
                          title: projectTitle,
                          prompt: prompt,
                          duration: duration,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.movie_creation_outlined),
                    label: const Text('Edit Video'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleInlinePlayback,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Video'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // =========================
            // GENERATE AGAIN & SHARE
            // =========================
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AiVideoGeneratorPage(
                            initialProject: {
                              'projectId': widget.projectId,
                              'title': projectTitle,
                              'prompt': prompt,
                              'style': style,
                              'duration': duration,
                              'aspectRatio': widget.aspectRatio,
                              'model': widget.model,
                              'provider': widget.provider,
                              'mode': widget.mode,
                              'resolution': widget.resolution,
                              'fps': widget.fps,
                              'seed': widget.seed,
                              'workflowId': widget.workflowId,
                              'pipelineId': widget.pipelineId,
                              'templateId': widget.templateId,
                              'templateParameters': widget.templateParameters,
                            },
                            workflowId: widget.workflowId,
                            pipelineId: widget.pipelineId,
                            templateId: widget.templateId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Generate Again'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _shareProject(context);
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _uploadingVideos ? null : _addProjectVideos,
                icon: _uploadingVideos
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.video_call_outlined),
                label: Text(
                  _uploadingVideos ? 'Uploading Videos' : 'Add Videos',
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Project video assets: ${_backendVideoCount ?? assetCount}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _rendering ? null : _renderProjectVideos,
                icon: _rendering
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(
                  _rendering ? 'Preparing Render' : 'Render Project Videos',
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),

        const SizedBox(width: 14),

        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
        ),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
