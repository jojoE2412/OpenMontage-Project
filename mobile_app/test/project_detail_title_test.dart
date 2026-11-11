import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/pages/project_detail_page.dart';
import 'package:mobile_app/services/backend_api.dart';
import 'package:mobile_app/services/project_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('editing a project title saves the new title without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ProjectDetailPage(
          projectId: 'project-1',
          title: 'Old Title',
          prompt: 'Create a cinematic travel video about sunrise',
          style: 'Cinematic',
          duration: '30s',
          assetCount: 3,
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    await tester.enterText(textField, 'New Title');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('New Title'), findsOneWidget);
  });

  testWidgets(
    'canceling title edit keeps the original title and does not fail',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ProjectDetailPage(
            projectId: 'project-2',
            title: 'Original Title',
            prompt: 'Create a cinematic travel video about sunrise',
            style: 'Cinematic',
            duration: '30s',
            assetCount: 2,
          ),
        ),
      );

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Original Title'), findsOneWidget);
    },
  );

  test('relative backend video URLs resolve to the Android emulator host', () {
    expect(
      BackendApi.resolveVideoUrl('/api/videos/job-123/file', jobId: 'job-123'),
      'http://10.0.2.2:8001/api/videos/job-123/file',
    );

    expect(
      BackendApi.resolveVideoUrl('http://example.com/video.mp4'),
      'http://example.com/video.mp4',
    );
  });

  test('saving a completed job updates the existing project record', () async {
    final first = await ProjectStorage.saveProject(
      id: 'backend-project-1',
      projectId: 'backend-project-1',
      title: 'Source Project',
      prompt: 'A short sample video',
      style: 'Video Edit',
      duration: '8s',
      assetCount: 1,
      status: 'Active',
    );
    final updated = await ProjectStorage.saveProject(
      id: 'backend-project-1',
      projectId: 'backend-project-1',
      title: 'Rendered Project',
      prompt: 'A short sample video',
      style: 'FFmpeg Render',
      duration: '16s',
      assetCount: 2,
      status: 'Completed',
      videoUrl: '/api/artifacts/artifact-1/file',
      jobId: 'job-1',
    );

    final saved = await ProjectStorage.getProjects();
    expect(saved, hasLength(1));
    expect(saved.single['title'], 'Rendered Project');
    expect(saved.single['jobId'], 'job-1');
    expect(updated['createdAt'], first['createdAt']);
  });
}
