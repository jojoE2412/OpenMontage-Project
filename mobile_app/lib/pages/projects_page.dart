import 'package:flutter/material.dart';

import '../services/project_storage.dart';
import '../widgets/project_card.dart';
import 'ai_video_generator_page.dart';
import 'project_detail_page.dart';
import 'video_editor_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String selectedFilter = 'All';

  List<Map<String, dynamic>> projects = [];
  bool isLoading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    ProjectStorage.revision.addListener(_loadProjects);
    _loadProjects();
  }

  @override
  void dispose() {
    _search.dispose();
    ProjectStorage.revision.removeListener(_loadProjects);
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final savedProjects = await ProjectStorage.getProjects();

    if (!mounted) return;

    setState(() {
      projects = savedProjects;
      isLoading = false;
    });
  }

  IconData _getProjectIcon(String style) {
    switch (style) {
      case 'Cinematic':
        return Icons.movie_creation_outlined;
      case 'Documentary':
        return Icons.photo_camera_outlined;
      case 'Anime':
        return Icons.animation_outlined;
      case 'Realistic':
        return Icons.videocam_outlined;
      case 'Minimal':
        return Icons.dashboard_outlined;
      default:
        return Icons.movie_outlined;
    }
  }

  String _formatDuration(dynamic duration) {
    final value = duration.toString();

    switch (value) {
      case '15s':
        return '15 seconds';
      case '30s':
        return '30 seconds';
      case '60s':
        return '60 seconds';
      case '90s':
        return '90 seconds';
      case '120s':
        return '120 seconds';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProjects =
        (selectedFilter == 'All'
                ? projects
                : projects
                      .where(
                        (project) =>
                            (project['status']?.toString().toLowerCase() ??
                                'draft') ==
                            selectedFilter.toLowerCase(),
                      )
                      .toList())
            .where(
              (project) => '${project['title']} ${project['prompt']}'
                  .toLowerCase()
                  .contains(_search.text.toLowerCase()),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Projects',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Manage your AI-generated video workspace.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search projects',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _filterButton('All'),
                const SizedBox(width: 8),
                _filterButton('Completed'),
                const SizedBox(width: 8),
                _filterButton('Processing'),
                const SizedBox(width: 8),
                _filterButton('Failed'),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredProjects.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _loadProjects,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filteredProjects.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final project = filteredProjects[index];
                          final String prompt =
                              project['prompt']?.toString() ?? '';
                          final String title =
                              project['title']?.toString() ??
                              _getProjectTitle(prompt);
                          final String style =
                              project['style']?.toString() ?? 'Cinematic';
                          final String duration =
                              project['duration']?.toString() ?? '30s';
                          final String status =
                              project['status']?.toString() ?? 'Completed';
                          final int assetCount =
                              (project['assetCount'] as num?)?.toInt() ?? 0;
                          return ProjectCard(
                            title: title,
                            style: style,
                            duration: _formatDuration(duration),
                            status: status,
                            icon: _getProjectIcon(style),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProjectDetailPage(
                                    projectId: project['id']?.toString(),
                                    title: title,
                                    prompt: prompt,
                                    style: style,
                                    duration: duration,
                                    assetCount: assetCount,
                                    videoUrl: project['videoUrl']?.toString(),
                                    aspectRatio:
                                        project['aspectRatio']?.toString() ??
                                        '16:9',
                                    model:
                                        project['model']?.toString() ?? 'Auto',
                                    provider:
                                        project['provider']?.toString() ??
                                        'auto',
                                    workflowId: project['workflowId']
                                        ?.toString(),
                                    pipelineId: project['pipelineId']
                                        ?.toString(),
                                    templateId: project['templateId']
                                        ?.toString(),
                                    templateParameters:
                                        Map<String, dynamic>.from(
                                          project['templateParameters']
                                                  as Map? ??
                                              {},
                                        ),
                                  ),
                                ),
                              );
                            },
                            onMore: () => _projectOptions(
                              project,
                              title,
                              prompt,
                              style,
                              duration,
                              assetCount,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _projectOptions(
    Map<String, dynamic> project,
    String title,
    String prompt,
    String style,
    String duration,
    int assetCount,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('Edit Video'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final id = project['id']?.toString();
    if (action == 'rename' && id != null) {
      final controller = TextEditingController(text: title);
      final updated = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename Project'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (updated?.isNotEmpty == true) {
        await ProjectStorage.updateProjectTitle(id, updated!);
      }
    } else if (action == 'delete' && id != null) {
      await ProjectStorage.deleteProject(id);
    } else if (action == 'edit') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VideoEditorPage(title: title, prompt: prompt, duration: duration),
        ),
      );
    } else if (action == 'duplicate') {
      await ProjectStorage.saveProject(
        title: '$title (Copy)',
        prompt: prompt,
        style: style,
        duration: duration,
        assetCount: assetCount,
        status: project['status']?.toString() ?? 'Completed',
        aspectRatio: project['aspectRatio']?.toString(),
        model: project['model']?.toString(),
        provider: project['provider']?.toString(),
        mode: project['mode']?.toString(),
        resolution: project['resolution']?.toString(),
        fps: (project['fps'] as num?)?.toInt(),
        seed: (project['seed'] as num?)?.toInt(),
        workflowId: project['workflowId']?.toString(),
        pipelineId: project['pipelineId']?.toString(),
        templateId: project['templateId']?.toString(),
        templateParameters: Map<String, dynamic>.from(
          project['templateParameters'] as Map? ?? {},
        ),
      );
    }
    await _loadProjects();
  }

  String _getProjectTitle(String prompt) {
    if (prompt.trim().isEmpty) {
      return 'Untitled Video';
    }

    final words = prompt.trim().split(RegExp(r'\s+'));

    if (words.length <= 6) {
      return prompt.trim();
    }

    return '${words.take(6).join(' ')}...';
  }

  Widget _emptyState() {
    String message;

    if (selectedFilter == 'All') {
      message = 'No projects yet.';
    } else {
      message = 'No $selectedFilter projects.';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          ),

          const SizedBox(height: 16),

          Text(
            selectedFilter == 'All' ? 'No videos yet' : message,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            selectedFilter == 'All'
                ? 'Create your first AI-generated video.'
                : 'Create a video to see it here.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (selectedFilter == 'All') ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiVideoGeneratorPage()),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate Video'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterButton(String filter) {
    final isSelected = selectedFilter == filter;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedFilter = filter;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            filter,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
