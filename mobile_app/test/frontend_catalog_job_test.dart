import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/feature_catalog.dart';
import 'package:mobile_app/models/processing_job.dart';

void main() {
  test('catalog keeps workflow identities unique across category views', () {
    final workflowIds = FeatureCatalog.workflows
        .map((entry) => entry.workflowId)
        .toList();
    expect(workflowIds, hasLength(11));
    expect(workflowIds.toSet(), hasLength(11));
    expect(
      FeatureCatalog.entries.where((entry) => entry.title == 'Shorts'),
      hasLength(1),
    );
    expect(
      FeatureCatalog.entries.where(
        (entry) => entry.title == 'Podcast Repurpose',
      ),
      hasLength(1),
    );
    expect(
      FeatureCatalog.entries
          .where((entry) => entry.category == CatalogCategory.workflows)
          .map((entry) => entry.workflowId),
      containsAll([
        'cinematic',
        'animated-explainer',
        'documentary-montage',
        'talking-head',
        'avatar-spokesperson',
      ]),
    );
  });

  test('each template has a distinct id and explicit default parameters', () {
    final templates = FeatureCatalog.templates;
    expect(templates.map((entry) => entry.id).toSet(), hasLength(6));
    for (final template in templates) {
      expect(template.defaultParameters, contains('aspectRatio'));
      expect(template.defaultParameters, contains('resolution'));
      expect(template.defaultParameters, contains('fps'));
      expect(template.defaultParameters, contains('mode'));
    }
    expect(
      templates
          .singleWhere((entry) => entry.id == 'social-media')
          .defaultParameters['aspectRatio'],
      '9:16',
    );
  });

  test('processing job parses generic lifecycle, progress, and artifacts', () {
    final job = ProcessingJob.fromJson({
      'id': 'job-42',
      'status': 'rendering',
      'progress': 68,
      'current_step': 'Compositing output',
      'capability': 'video_generation',
      'pipeline_id': 'cinematic',
      'artifacts': [
        {
          'id': 'artifact-1',
          'type': 'video',
          'url': 'https://example.invalid/demo.mp4',
          'mime_type': 'video/mp4',
        },
      ],
    });
    expect(job.status, ProcessingJobStatus.rendering);
    expect(job.progress, closeTo(.68, .001));
    expect(job.currentStep, 'Compositing output');
    expect(job.pipelineId, 'cinematic');
    expect(job.artifacts.single.mimeType, 'video/mp4');
  });
}
