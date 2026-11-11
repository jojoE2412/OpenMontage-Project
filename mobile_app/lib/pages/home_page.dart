import 'package:flutter/material.dart';

import '../models/feature_catalog.dart';
import '../services/project_storage.dart';
import 'app_destination_page.dart';
import 'feature_hub_pages.dart';
import 'project_detail_page.dart';

typedef HomeTabSelected = void Function(int index);

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onTabSelected});
  final HomeTabSelected? onTabSelected;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _projects = const [];
  @override
  void initState() {
    super.initState();
    ProjectStorage.revision.addListener(_loadProjects);
    _loadProjects();
  }

  @override
  void dispose() {
    ProjectStorage.revision.removeListener(_loadProjects);
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projects = await ProjectStorage.getProjects();
    if (mounted) setState(() => _projects = projects.take(3).toList());
  }

  void _openProject(Map<String, dynamic> project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(
          projectId: project['id']?.toString(),
          title: project['title']?.toString(),
          prompt: project['prompt']?.toString() ?? '',
          style: project['style']?.toString() ?? 'Cinematic',
          duration: project['duration']?.toString() ?? '5s',
          assetCount: (project['assetCount'] as num?)?.toInt() ?? 0,
          videoUrl: project['videoUrl']?.toString(),
          jobId: project['jobId']?.toString(),
          aspectRatio: project['aspectRatio']?.toString() ?? '16:9',
          model: project['model']?.toString() ?? 'Auto',
          provider: project['provider']?.toString() ?? 'auto',
          workflowId: project['workflowId']?.toString(),
          pipelineId: project['pipelineId']?.toString(),
          templateId: project['templateId']?.toString(),
          mode: project['mode']?.toString() ?? 'Text to Video',
          resolution: project['resolution']?.toString() ?? '720p',
          fps: (project['fps'] as num?)?.toInt() ?? 24,
          seed: (project['seed'] as num?)?.toInt(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quick = <(String, IconData, Color, VoidCallback)>[
      (
        'AI Video',
        Icons.movie_creation_outlined,
        const Color(0xff7057e8),
        () => openStudioFeature(context, 'AI Video'),
      ),
      (
        'AI Image',
        Icons.image_outlined,
        const Color(0xffd94f87),
        () => openStudioFeature(context, 'AI Image'),
      ),
      (
        'Video Editor',
        Icons.movie_outlined,
        const Color(0xff3677d4),
        () => openStudioFeature(context, 'Video Editor'),
      ),
      (
        'Audio',
        Icons.graphic_eq_outlined,
        const Color(0xff238f70),
        () => openStudioFeature(context, 'Audio'),
      ),
    ];
    return Scaffold(
      drawer: OpenMontageDrawer(onTabSelected: widget.onTabSelected ?? (_) {}),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProjects,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Row(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff7c5cff), Color(0xff4c8dff)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'OpenMontage',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => openDestination(
                      context,
                      AppDestination.notificationCenter,
                    ),
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onTabSelected?.call(4),
                    child: const CircleAvatar(child: Text('JD')),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Good morning, Creator 👋',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Ready to create something amazing?',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff252d55), Color(0xff6952c9)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create with AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Turn an idea into a project. Generation is currently a frontend demo.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () => openStudioFeature(context, 'AI Video'),
                        icon: const Icon(Icons.add),
                        label: const Text('Start creating'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Quick Create', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.65,
                children: [
                  for (final item in quick)
                    _QuickAction(
                      title: item.$1,
                      icon: item.$2,
                      color: item.$3,
                      onTap: item.$4,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent Projects',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onTabSelected?.call(1),
                    child: const Text('View All'),
                  ),
                ],
              ),
              if (_projects.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.video_library_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your local projects will appear here.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final project in _projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentProject(
                    project: project,
                    onTap: () => _openProject(project),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Explore Workflows',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onTabSelected?.call(2),
                    child: const Text('View All'),
                  ),
                ],
              ),
              SizedBox(
                height: 145,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: FeatureCatalog.workflows.length,
                  itemBuilder: (context, index) {
                    final workflow = FeatureCatalog.workflows[index];
                    return SizedBox(
                      width: 230,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => openStudioFeature(
                            context,
                            workflow.title,
                            description: workflow.description,
                            workflowId: workflow.workflowId,
                            pipelineId: workflow.pipelineId,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  workflow.icon,
                                  color: theme.colorScheme.primary,
                                ),
                                const Spacer(),
                                Text(
                                  workflow.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  workflow.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AllFeaturesPage()),
                  ),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('All Features'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentProject extends StatelessWidget {
  const _RecentProject({required this.project, required this.onTap});
  final Map<String, dynamic> project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: const CircleAvatar(child: Icon(Icons.movie_outlined)),
      title: Text(
        project['title']?.toString() ?? 'Untitled Project',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${project['style'] ?? 'Project'} · local project'),
      trailing: Text(
        project['status']?.toString() ?? 'Draft',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}
