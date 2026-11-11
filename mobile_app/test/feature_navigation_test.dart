import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/pages/feature_hub_pages.dart';
import 'package:mobile_app/pages/home_page.dart';
import 'package:mobile_app/pages/project_detail_page.dart';
import 'package:mobile_app/pages/ai_video_generator_page.dart';
import 'package:mobile_app/pages/template_pages.dart';

void main() {
  testWidgets('Create page preserves the existing Video Editor entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CreateSomethingPage()));
    await tester.pump();
    expect(
      find.text('Choose how you want to start your project.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Video Editor'));
    await tester.pumpAndSettle();
    expect(find.text('Video Editor'), findsOneWidget);
    expect(find.text('Add video'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Apply Trim'), findsOneWidget);
    expect(find.text('Coming Soon'), findsNWidgets(8));
  });

  testWidgets('All Features opens its catalog and AI Video opens generator', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AllFeaturesPage()));
    expect(find.text('Generate'), findsOneWidget);
    await tester.tap(find.text('AI Video').first);
    await tester.pumpAndSettle();
    expect(find.text('AI Video Studio'), findsOneWidget);
    expect(find.text('Project Name'), findsOneWidget);
  });

  testWidgets('AI Image opens its provider-backed studio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openStudioFeature(context, 'AI Image'),
              child: const Text('Open AI Image'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open AI Image'));
    await tester.pumpAndSettle();
    expect(find.text('AI Image Studio'), findsOneWidget);
    expect(find.byKey(const ValueKey('imagePromptField')), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Negative Prompt'), findsNothing);
    final generate = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate Image'),
    );
    expect(generate.onPressed, isNull);
  });

  testWidgets('Audio opens its TTS, processing and music studio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openStudioFeature(context, 'Audio'),
              child: const Text('Open Audio'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Audio'));
    await tester.pumpAndSettle();
    expect(find.text('Audio Studio'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    await tester.tap(find.text('Process'));
    await tester.pumpAndSettle();
    expect(find.text('OpenMontage Audio Tools'), findsOneWidget);
    final run = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Run Processing · Coming Soon'),
    );
    expect(run.onPressed, isNull);
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    expect(find.text('Music Prompt'), findsOneWidget);
  });

  testWidgets('workflow navigation preserves workflow and pipeline ids', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openStudioFeature(
                context,
                'Cinematic',
                workflowId: 'cinematic',
                pipelineId: 'cinematic',
              ),
              child: const Text('Open Cinematic'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Cinematic'));
    await tester.pumpAndSettle();
    final generator = tester.widget<AiVideoGeneratorPage>(
      find.byType(AiVideoGeneratorPage),
    );
    expect(generator.workflowId, 'cinematic');
    expect(generator.pipelineId, 'cinematic');
  });

  testWidgets('Talking Head keeps its workflow identity in Avatar Studio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openStudioFeature(
                context,
                'Talking Head',
                workflowId: 'talking-head',
                pipelineId: 'talking-head',
              ),
              child: const Text('Open Talking Head'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Talking Head'));
    await tester.pumpAndSettle();
    final studio = tester.widget<CapabilityStudioPage>(
      find.byType(CapabilityStudioPage),
    );
    expect(studio.feature, 'Avatar');
    expect(studio.workflowId, 'talking-head');
    expect(studio.pipelineId, 'talking-head');
  });

  testWidgets('template gallery opens the selected template configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TemplateGalleryPage()));
    await tester.tap(find.text('Product Showcase'));
    await tester.pumpAndSettle();
    final detail = tester.widget<TemplateDetailPage>(
      find.byType(TemplateDetailPage),
    );
    expect(detail.template.id, 'product-showcase');
    expect(detail.template.defaultParameters['fps'], 30);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Template'));
    await tester.pumpAndSettle();
    final generator = tester.widget<AiVideoGeneratorPage>(
      find.byType(AiVideoGeneratorPage),
    );
    expect(generator.workflowId, 'cinematic');
    expect(generator.templateId, 'product-showcase');
    expect(generator.initialProject?['templateParameters']['fps'], 30);
  });

  testWidgets('Capability studios open on a medium phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const destinations = <(String, String)>[
      ('AI Image', 'AI Image Studio'),
      ('Animation', 'Animation'),
      ('Avatar', 'Avatar'),
      ('Subtitle', 'Subtitle Studio'),
      ('Audio', 'Audio Studio'),
      ('Enhancement', 'Enhancement Studio'),
      ('Shorts', 'Shorts'),
      ('Podcast Repurpose', 'Podcast Repurpose'),
      ('Screen Demo', 'Screen Demo'),
      ('Localization', 'Localization'),
      ('Footage', 'Footage'),
      ('3D', '3D Studio'),
      ('Hybrid Production', 'Hybrid Production'),
      ('AI Tools', 'AI Tools'),
      ('Graphics Tools', 'Graphics Tools'),
      ('Character Animation', 'Character Animation'),
    ];

    for (final destination in destinations) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openStudioFeature(context, destination.$1),
                  child: Text('Open ${destination.$1}'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open ${destination.$1}'));
      await tester.pumpAndSettle();
      expect(find.text(destination.$2).first, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Home Video Editor opens the real trim workflow', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.tap(find.text('Video Editor').first);
    await tester.pumpAndSettle();
    expect(find.text('Video Editor'), findsOneWidget);
  });

  testWidgets('Project Detail Play Video toggles its inline preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProjectDetailPage(
          title: 'Demo Project',
          prompt: 'A sample prompt',
          style: 'Cinematic',
          duration: '5s',
          assetCount: 0,
        ),
      ),
    );
    expect(find.text('Demo Preview'), findsOneWidget);
    await tester.ensureVisible(find.text('Play Video'));
    await tester.tap(find.text('Play Video'));
    await tester.pump();
    expect(find.text('00:03'), findsOneWidget);
    expect(
      find.text('This project is currently using a demo result.'),
      findsNothing,
    );
  });
}
