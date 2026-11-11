import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/pages/library_page.dart';
import 'package:mobile_app/services/library_storage.dart';
import 'package:mobile_app/services/project_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('library supports project association and image preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ProjectStorage.saveProject(
      title: 'Test project',
      prompt: 'A test project prompt',
      style: 'Cinematic',
      duration: '5s',
      assetCount: 0,
    );
    await LibraryStorage.saveAsset(
      name: 'reference.png',
      path: '/missing/reference.png',
      type: 'image',
    );

    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.more_horiz).first);
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Associate with Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test project'));
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final saved = (await LibraryStorage.getAssets()).single;
    expect(saved['projectIds'], isNotEmpty);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('reference.png'), findsWidgets);
    expect(find.byType(Image), findsOneWidget);
  });
}
