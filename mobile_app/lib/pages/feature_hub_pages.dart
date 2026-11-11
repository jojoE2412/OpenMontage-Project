import 'package:flutter/material.dart';

import '../models/feature_catalog.dart';
import 'audio_studio_page.dart';
import 'enhancement_studio_page.dart';
import 'ai_image_generator_page.dart';
import 'subtitle_studio_page.dart';
import 'ai_video_generator_page.dart';
import 'video_editor_page.dart';
import 'library_page.dart';

class StudioFeature {
  const StudioFeature(
    this.title,
    this.description,
    this.icon, {
    this.ready = false,
    this.workflowId,
    this.pipelineId,
    this.demo = true,
  });
  final String title;
  final String description;
  final IconData icon;
  final bool ready;
  final String? workflowId;
  final String? pipelineId;
  final bool demo;
}

final studioFeatures = FeatureCatalog.capabilities
    .where((entry) => entry.category == CatalogCategory.generate)
    .map(
      (entry) => StudioFeature(
        entry.title,
        entry.description,
        entry.icon,
        ready: entry.id == 'video-editor',
        workflowId: entry.workflowId,
        pipelineId: entry.pipelineId,
        demo: entry.demo,
      ),
    )
    .toList(growable: false);

void openStudioFeature(
  BuildContext context,
  String name, {
  String description = '',
  String? workflowId,
  String? pipelineId,
  String? templateId,
}) {
  final canonical = switch (name) {
    'Edit Video' || 'Edit Video...' || 'Import & Edit' => 'Video Editor',
    'Create Short' => 'Shorts',
    'Audio & Voice' => 'Audio',
    'Enhance Video' || 'Color / Enhancement' => 'Enhancement',
    _ => name,
  };
  FeatureCatalogEntry? workflow;
  for (final entry in FeatureCatalog.workflows) {
    if (entry.workflowId == workflowId) {
      workflow = entry;
      break;
    }
  }
  final resolvedName = workflow == null
      ? canonical
      : switch (workflow.destination) {
          StudioDestination.aiVideo => 'AI Video',
          StudioDestination.animation => 'Animation',
          StudioDestination.avatar => 'Avatar',
          StudioDestination.audio => 'Audio',
          StudioDestination.videoEditor => 'Video Editor',
          StudioDestination.subtitle => 'Subtitle',
          StudioDestination.enhancement => 'Enhancement',
          StudioDestination.shorts => 'Shorts',
          StudioDestination.podcast => 'Podcast Repurpose',
          StudioDestination.screenDemo => 'Screen Demo',
          StudioDestination.localization => 'Localization',
          StudioDestination.hybrid => 'Hybrid Production',
          StudioDestination.characterAnimation => 'Character Animation',
          StudioDestination.footage => 'Footage',
          StudioDestination.library => 'Library',
          StudioDestination.threeD => '3D',
          StudioDestination.aiTools => 'AI Tools',
          StudioDestination.graphicsTools => 'Graphics Tools',
          StudioDestination.aiImage => 'AI Image',
        };
  final effectivePipelineId = pipelineId ?? workflow?.pipelineId;
  if (resolvedName == 'AI Video') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiVideoGeneratorPage(
          workflowId: workflowId,
          pipelineId: effectivePipelineId,
          templateId: templateId,
        ),
      ),
    );
  } else if (resolvedName == 'AI Image') {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiImageGeneratorPage()),
    );
  } else if (resolvedName == 'Audio') {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AudioStudioPage()),
    );
  } else if (resolvedName == 'Subtitle') {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubtitleStudioPage()),
    );
  } else if (resolvedName == 'Enhancement') {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EnhancementStudioPage()),
    );
  } else if (resolvedName == 'Video Editor') {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoEditorPage()),
    );
  } else if (resolvedName == 'Library' || resolvedName == 'Reference') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryPage(
          initialCategory: resolvedName == 'Reference' ? 'References' : null,
        ),
      ),
    );
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CapabilityStudioPage(
          feature: resolvedName,
          description: description,
          workflowId: workflowId,
          pipelineId: effectivePipelineId,
          templateId: templateId,
        ),
      ),
    );
  }
}

const Map<String, List<String>> _studioControls = {
  'AI Image': [
    'Project Name',
    'Prompt',
    'Style',
    'Aspect Ratio',
    'Images',
    'Reference Image',
    'Advanced Settings',
  ],
  'Animation': [
    'Project Name',
    'Prompt',
    'Animation Style',
    'Duration',
    'Aspect Ratio',
    'Assets',
  ],
  'Avatar': [
    'Choose Avatar',
    'Portrait Image',
    'Script',
    'Voice',
    'Language',
    'Style',
    'Mode',
  ],
  'Audio': [
    'Mode',
    'Prompt / Script',
    'Genre',
    'Mood',
    'Duration',
    'Voice',
    'Language',
    'Audio Timeline',
    'Volume',
    'Fade',
  ],
  'Subtitle': [
    'Source Video',
    'Language',
    'Subtitle Style',
    'Font',
    'Size',
    'Position',
    'Color',
    'Timing',
    'Burn-in',
  ],
  'Enhance Video': [
    'Source Video',
    'Enhancement Tools',
    'Brightness',
    'Contrast',
    'Saturation',
    'Sharpness',
    'Before / After',
  ],
  'Color / Enhancement': [
    'Source Video',
    'Enhancement Tools',
    'Brightness',
    'Contrast',
    'Saturation',
    'Sharpness',
    'Before / After',
  ],
  'Enhancement': [
    'Source Video',
    'Enhancement Tools',
    'Brightness',
    'Contrast',
    'Saturation',
    'Sharpness',
    'Upscale',
  ],
  'Shorts': [
    'Source Video',
    'Target Platform',
    'Aspect Ratio',
    'Duration',
    'Clip Selection',
    'Caption',
    'Title',
  ],
  'Podcast Repurpose': [
    'Podcast Source',
    'Media Type',
    'Transcript',
    'Speaker Detection',
    'Clip Duration',
    'Short Selection',
    'Caption',
  ],
  'Screen Demo': [
    'Record / Import Screen',
    'Script',
    'Cursor Settings',
    'Highlight',
    'Voice',
    'Preview',
  ],
  'Localization': [
    'Source Video',
    'Source Language',
    'Target Language',
    'Translation',
    'Voice',
    'Subtitles',
    'Preview',
  ],
  '3D': [
    'Scene',
    'Assets',
    'Camera',
    'Environment',
    'Lighting',
    'Preview',
    'Render',
  ],
  'Character Animation': [
    'Select Character',
    'Upload Character',
    'Motion Type',
    'Motion Prompt',
    'Style',
    'Duration',
  ],
  'Hybrid Production': [
    'Project Setup',
    'AI Generated Assets',
    'Real Footage',
    'Images',
    'Audio',
    'Timeline',
    'Preview',
  ],
  'AI Tools': [
    'Tool Category',
    'Source Video / Asset',
    'Language',
    'Analysis Options',
  ],
  'Graphics Tools': [
    'Tool',
    'Prompt / Input',
    'Style',
    'Aspect Ratio',
    'Reference Assets',
  ],
  'Footage': ['Search', 'Category', 'Duration', 'Orientation', 'Provider'],
  'Create Short': [
    'Source Video',
    'Target Platform',
    'Aspect Ratio',
    'Duration',
    'Caption',
  ],
};

String _featureTitle(String feature) => switch (feature) {
  'Create Short' => 'Shorts',
  'Color / Enhancement' || 'Enhance Video' => 'Enhancement',
  'Audio & Voice' => 'Audio',
  'Import & Edit' || 'Edit Video' => 'Video Editor',
  '3D' => '3D Studio',
  _ => feature,
};

class CapabilityStudioPage extends StatefulWidget {
  const CapabilityStudioPage({
    super.key,
    required this.feature,
    this.description = '',
    this.workflowId,
    this.pipelineId,
    this.templateId,
  });
  final String feature;
  final String description;
  final String? workflowId, pipelineId, templateId;

  @override
  State<CapabilityStudioPage> createState() => _CapabilityStudioPageState();
}

class _CapabilityStudioPageState extends State<CapabilityStudioPage> {
  final Map<String, String> _selections = {};
  final Set<String> _enabled = {};
  String get _title => _featureTitle(widget.feature);

  @override
  Widget build(BuildContext context) {
    final controls =
        _studioControls[widget.feature] ??
        ['Project Name', 'Source Asset', 'Prompt', 'Style', 'Preview'];
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: const _StatusPill('Coming Soon')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Text(
              widget.description.isEmpty
                  ? 'Workspace untuk ${_title.toLowerCase()} dalam production pipeline OpenMontage.'
                  : widget.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (widget.workflowId != null) ...[
              _sectionTitle('Workflow'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(widget.workflowId!),
                subtitle: Text(
                  widget.pipelineId == null
                      ? 'Frontend workflow context'
                      : 'Pipeline reference: ${widget.pipelineId} · execution unavailable',
                ),
              ),
            ],
            if (widget.feature == 'AI Tools') _analysisCards(),
            if (widget.feature == 'Graphics Tools') _graphicsCards(),
            if (widget.feature == 'Footage') _footageResults(),
            if (widget.feature == 'Audio')
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('Provider availability is not verified'),
                subtitle: Text(
                  'Text to Speech and Music actions are disabled until an OpenMontage service is available.',
                ),
              ),
            for (final control in controls) ...[
              _sectionTitle(control),
              _controlFor(control),
            ],
            if (widget.feature == 'Audio') ...[
              _sectionTitle('Audio Processing'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: ['Mix', 'Voice', 'Music', 'SFX', 'Enhance']
                    .map(
                      (v) => FilterChip(
                        label: Text(v),
                        selected: _enabled.contains(v),
                        onSelected: (s) => setState(
                          () => s ? _enabled.add(v) : _enabled.remove(v),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (widget.feature == 'Enhancement' ||
                widget.feature == 'Enhance Video' ||
                widget.feature == 'Color / Enhancement') ...[
              _sectionTitle('Enhancement Tools'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    [
                          'Upscale',
                          'Background Removal',
                          'Face Enhance',
                          'Face Restore',
                          'Color Grade',
                          'Auto Reframe',
                          'Face Tracking',
                          'Audio Enhance',
                        ]
                        .map(
                          (v) => FilterChip(
                            label: Text(v),
                            selected: _enabled.contains(v),
                            onSelected: (s) => setState(
                              () => s ? _enabled.add(v) : _enabled.remove(v),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.hourglass_empty),
              label: Text('$_primaryAction · Coming Soon'),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Execution is unavailable until a matching OpenMontage job operation is exposed.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _primaryAction => switch (widget.feature) {
    'AI Image' => 'Generate Image',
    'Animation' => 'Generate Animation',
    'Avatar' => 'Generate Avatar Video',
    'Enhancement' => 'Preview Enhancement',
    'Character Animation' => 'Animate Character',
    'Audio' => 'Generate Audio',
    'Subtitle' => 'Generate Subtitles',
    'Shorts' || 'Create Short' => 'Create Short',
    'Podcast Repurpose' => 'Generate Clips',
    'Localization' => 'Generate Localized Video',
    'Screen Demo' => 'Preview Demo',
    '3D' => 'Render Scene',
    'AI Tools' => 'Run Analysis',
    _ => 'Continue',
  };

  Widget _controlFor(String label) {
    if (label == 'Preview' ||
        label == 'Before / After' ||
        label == 'Transcript' ||
        label == 'Audio Timeline') {
      return Card(
        child: SizedBox(
          height: label.contains('Preview') || label == 'Before / After'
              ? 150
              : 78,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  label.contains('Preview') || label == 'Before / After'
                      ? Icons.play_circle_outline
                      : Icons.view_timeline_outlined,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 5),
                Text('$label · preview unavailable'),
              ],
            ),
          ),
        ),
      );
    }
    if (label == 'Advanced Settings') {
      return Card(
        child: ExpansionTile(
          title: const Text('Advanced Settings'),
          children: [
            const ListTile(title: Text('Seed'), subtitle: Text('Auto')),
            const ListTile(
              title: Text('Negative Prompt'),
              subtitle: Text('Optional'),
            ),
          ],
        ),
      );
    }
    if (label == 'Prompt' ||
        label == 'Prompt / Script' ||
        label == 'Script' ||
        label == 'Motion Prompt' ||
        label == 'Translation' ||
        label == 'Search') {
      return TextField(
        maxLines: label == 'Search' ? 1 : 3,
        decoration: InputDecoration(
          hintText: label == 'Search'
              ? 'Search assets…'
              : 'Describe what you want to create…',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(
            label == 'Search' ? Icons.search : Icons.edit_outlined,
          ),
        ),
      );
    }
    if (label == 'Project Name' ||
        label.contains('Source') ||
        label.contains('Image') ||
        label.contains('Assets') ||
        label.contains('Upload') ||
        label.contains('Character') ||
        label.contains('Record') ||
        label == 'Scene') {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(
          'Select $label · Coming Soon',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if ([
      'Brightness',
      'Contrast',
      'Saturation',
      'Sharpness',
      'Volume',
      'Fade',
    ].contains(label)) {
      return Slider(
        min: 0,
        max: 100,
        value: (_selections[label] == null
            ? 50
            : double.tryParse(_selections[label]!)?.clamp(0, 100).toDouble() ??
                  50),
        onChanged: (v) =>
            setState(() => _selections[label] = v.toStringAsFixed(0)),
      );
    }
    final options = switch (label) {
      'Aspect Ratio' => ['16:9', '9:16', '1:1', '4:3'],
      'Duration' || 'Clip Duration' => ['5s', '10s', '15s', '30s'],
      'Images' => ['1', '2', '4', '8'],
      'Language' || 'Source Language' || 'Target Language' => [
        'English',
        'Bahasa Indonesia',
        'Japanese',
        'Spanish',
      ],
      'Style' ||
      'Animation Style' ||
      'Subtitle Style' => ['Auto', 'Cinematic', 'Clean', 'Bold', 'Documentary'],
      'Mode' => ['Talking Head', 'Lip Sync'],
      'Genre' => ['Cinematic', 'Ambient', 'Pop', 'Electronic'],
      'Mood' => ['Calm', 'Energetic', 'Dramatic'],
      'Target Platform' => ['YouTube Shorts', 'TikTok', 'Instagram Reels'],
      'Category' ||
      'Tool Category' => ['All', 'Video', 'Image', 'Audio', 'Graphics'],
      'Orientation' => ['Any', 'Landscape', 'Portrait', 'Square'],
      _ => ['Auto', 'Default', 'Standard'],
    };
    if (label == 'Enhancement Tools' ||
        label == 'Analysis Options' ||
        label == 'Cursor Settings' ||
        label == 'Highlight') {
      return Wrap(
        spacing: 8,
        children: options
            .map(
              (v) => ChoiceChip(
                label: Text(v),
                selected: (_selections[label] ?? options.first) == v,
                onSelected: (_) => setState(() => _selections[label] = v),
              ),
            )
            .toList(),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selections[label] ?? options.first,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: label,
      ),
      items: options
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selections[label] = v ?? options.first),
    );
  }

  Widget _analysisCards() => Column(
    children: [
      for (final entry in [
        ('Transcription', Icons.subtitles_outlined, 'transcriber'),
        ('Scene Detection', Icons.movie_filter_outlined, 'scene_detect'),
        ('Frame Sampling', Icons.photo_library_outlined, 'frame_sampler'),
        ('Image Analysis', Icons.image_search_outlined, 'image_analyzer'),
        ('Audio Analysis', Icons.graphic_eq_outlined, 'audio_probe'),
      ])
        Card(
          child: ExpansionTile(
            leading: Icon(entry.$2),
            title: Text(entry.$1),
            subtitle: Text('OpenMontage tool · ${entry.$3} · not connected'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const TextField(
                decoration: InputDecoration(labelText: 'Input asset / query'),
              ),
              const SizedBox(height: 10),
              const SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: null, child: Text('Run tool')),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Result'),
                subtitle: Text('Not connected to a backend tool.'),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _graphicsCards() => Column(
    children: [
      for (final entry in [
        ('Diagram', Icons.account_tree_outlined, 'diagram_gen'),
        ('Code Visualization', Icons.code, 'code_snippet'),
        (
          'Data Visualization',
          Icons.insert_chart_outlined,
          'frontend catalog · not connected',
        ),
        ('Math Animation', Icons.functions, 'math_animate'),
        (
          'Stock Image Search',
          Icons.photo_library_outlined,
          'pexels_image / pixabay_image',
        ),
      ])
        Card(
          child: ExpansionTile(
            leading: Icon(entry.$2),
            title: Text(entry.$1),
            subtitle: Text('Tool reference · ${entry.$3} · demo only'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const TextField(
                decoration: InputDecoration(labelText: 'Prompt / source input'),
              ),
              const SizedBox(height: 10),
              const SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: null, child: Text('Run tool')),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Result'),
                subtitle: Text('No graphics service is connected.'),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _footageResults() => const Card(
    child: ListTile(
      leading: Icon(Icons.cloud_off_outlined),
      title: Text('Stock search unavailable'),
      subtitle: Text('No stock footage provider is configured.'),
    ),
  );
  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

StudioFeature _studioFeature(FeatureCatalogEntry entry) => StudioFeature(
  entry.title,
  entry.description,
  entry.icon,
  ready:
      entry.id == 'ai-video' ||
      entry.id == 'video-editor' ||
      entry.id == 'library',
  workflowId: entry.workflowId,
  pipelineId: entry.pipelineId,
  demo: entry.demo,
);

class CreateSomethingPage extends StatelessWidget {
  const CreateSomethingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Choose how you want to start your project.'),
        const SizedBox(height: 18),
        Text('Create with AI', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final entry in FeatureCatalog.capabilities.where(
              (entry) => entry.category == CatalogCategory.generate,
            ))
              _FeatureCard(feature: _studioFeature(entry)),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const Icon(Icons.movie_outlined),
            title: const Text('Video Editor'),
            subtitle: const Text('Start editing a video you already have.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openStudioFeature(context, 'Video Editor'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Production Workflows',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Workflows guide a project through multiple production stages. These frontend entries do not start OpenMontage pipelines yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final workflow in FeatureCatalog.workflows)
          _FeatureCard(feature: _studioFeature(workflow)),
      ],
    ),
  );
}

class AllFeaturesPage extends StatelessWidget {
  const AllFeaturesPage({super.key});

  static const _categoryTitles = <CatalogCategory, String>{
    CatalogCategory.generate: 'Generate',
    CatalogCategory.edit: 'Edit',
    CatalogCategory.production: 'Production',
    CatalogCategory.assets: 'Assets',
    CatalogCategory.advanced: 'Advanced',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('All Features')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        for (final category in _categoryTitles.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              category.value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.06,
            children: [
              for (final entry in FeatureCatalog.entries.where(
                (item) => item.category == category.key,
              ))
                _FeatureCard(feature: _studioFeature(entry)),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            'Workflows',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final workflow in FeatureCatalog.entries.where(
          (item) => item.category == CatalogCategory.workflows,
        ))
          _FeatureCard(feature: _studioFeature(workflow)),
      ],
    ),
  );
}

class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.feature,
    this.description = '',
  });
  final String feature;
  final String description;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(feature)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(feature, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              description.isEmpty
                  ? 'This production tool is part of the OpenMontage studio roadmap.'
                  : description,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const _ComingBadge(),
            const SizedBox(height: 18),
            const Text(
              'This feature is shown as a preview. No external service is connected yet.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComingBadge extends StatelessWidget {
  const _ComingBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiary.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Coming Soon',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final StudioFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (feature.title) {
      'AI Video' => const Color(0xFF8058FF),
      'Video Editor' => const Color(0xFF3B82F6),
      'Create Short' || 'Shorts' => const Color(0xFFF97316),
      'AI Image' || 'Animation' => const Color(0xFF8B5CF6),
      'Audio' ||
      'Audio & Voice' ||
      'Podcast Repurpose' => const Color(0xFF10B981),
      'Avatar' => const Color(0xFFEC4899),
      'Footage' ||
      'Reference' ||
      'Library' ||
      'Import & Edit' => const Color(0xFF06B6D4),
      'Subtitle' || 'Localization' => const Color(0xFF2563EB),
      '3D' || 'Hybrid Production' || 'AI Tools' => const Color(0xFFF59E0B),
      _ => theme.colorScheme.primary,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openStudioFeature(
          context,
          feature.title,
          description: feature.description,
          workflowId: feature.workflowId,
          pipelineId: feature.pipelineId,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(feature.icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      feature.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!feature.ready) ...[
                      const SizedBox(height: 8),
                      const _ComingBadge(),
                    ] else if (feature.demo) ...[
                      const SizedBox(height: 8),
                      const _StatusPill('Demo'),
                    ],
                  ],
                ),
              ),
              if (feature.ready)
                Icon(Icons.chevron_right, color: accent, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}
