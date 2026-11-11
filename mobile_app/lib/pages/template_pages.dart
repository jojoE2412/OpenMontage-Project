import 'package:flutter/material.dart';

import '../models/feature_catalog.dart';
import 'ai_video_generator_page.dart';

class TemplateGalleryPage extends StatelessWidget {
  const TemplateGalleryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Templates')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Starter templates · frontend configurations'),
        const SizedBox(height: 12),
        for (final template in FeatureCatalog.templates)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.movie_filter_outlined),
              ),
              title: Text(template.title),
              subtitle: Text('${template.style} · ${template.duration}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TemplateDetailPage(template: template),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class TemplateDetailPage extends StatelessWidget {
  const TemplateDetailPage({super.key, required this.template});
  final TemplateCatalogEntry template;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(template.title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xff5b6991), Color(0xffedb278), Color(0xff344461)],
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 56,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Template configuration · local demo',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(template.prompt),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Workflow'),
          subtitle: Text(template.workflowId),
        ),
        ListTile(title: const Text('Style'), subtitle: Text(template.style)),
        ListTile(
          title: const Text('Duration'),
          subtitle: Text(template.duration),
        ),
        for (final parameter in template.defaultParameters.entries)
          ListTile(
            title: Text(parameter.key),
            subtitle: Text(parameter.value.toString()),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AiVideoGeneratorPage(
                workflowId: template.workflowId,
                pipelineId: _pipelineId(template.workflowId),
                templateId: template.id,
                initialProject: {
                  'title': template.title,
                  'prompt': template.prompt,
                  'style': template.style,
                  'duration': template.duration,
                  'aspectRatio': template.workflowId == 'shorts'
                      ? '9:16'
                      : '16:9',
                  'workflowId': template.workflowId,
                  'pipelineId': _pipelineId(template.workflowId),
                  'templateId': template.id,
                  'templateParameters': template.defaultParameters,
                },
              ),
            ),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Use Template'),
        ),
      ],
    ),
  );

  static String _pipelineId(String workflowId) => switch (workflowId) {
    'shorts' => 'clip-factory',
    'localization' => 'localization-dub',
    _ => workflowId,
  };
}
