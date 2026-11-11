import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/pages/ai_video_generator_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpGenerator(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AiVideoGeneratorPage()));
  }

  testWidgets('configured prompt does not claim unavailable generation', (
    tester,
  ) async {
    await pumpGenerator(tester);
    await tester.enterText(
      find.byType(TextField).at(1),
      'A sunrise above Mount Bromo',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate Video'));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate Video'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Generation Summary'), findsNothing);
  });

  testWidgets('generator exposes local GPU and Hugging Face runtimes', (
    tester,
  ) async {
    await pumpGenerator(tester);
    expect(find.text('My GPU'), findsOneWidget);
    expect(find.text('Hugging Face'), findsOneWidget);
    await tester.tap(find.text('Hugging Face'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no included inference credits'),
      findsOneWidget,
    );
    expect(find.text('Estimated cost'), findsOneWidget);
  });

  testWidgets('image mode requires an image and exposes local asset controls', (
    tester,
  ) async {
    await pumpGenerator(tester);
    await tester.tap(find.text('Image to Video'));
    await tester.pumpAndSettle();
    expect(find.text('Reference Image'), findsOneWidget);
    expect(find.text('Add Image'), findsWidgets);
    await tester.enterText(
      find.byType(TextField).at(1),
      'Move the clouds slowly across the sky',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.text('Generation Summary'), findsNothing);
  });

  testWidgets('template selection updates prompt and parameters', (
    tester,
  ) async {
    await pumpGenerator(tester);
    await tester.tap(find.text('Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Social Media').first);
    await tester.pumpAndSettle();
    expect(find.text('Fast-paced vertical content'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Fast-paced vertical content',
    );
  });

  testWidgets(
    'style, duration, ratio and resolution controls remain editable',
    (tester) async {
      await pumpGenerator(tester);
      await tester.enterText(
        find.byType(TextField).at(1),
        'A carefully described scenic mountain sunrise',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      if (find.text('Anime').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('Anime').first);
        await tester.tap(find.text('Anime').first);
        await tester.pumpAndSettle();
      } else {
        expect(
          find.text(
            'This OpenMontage provider does not accept a style parameter.',
          ),
          findsOneWidget,
        );
      }
      if (find.text('10 seconds').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('10 seconds'));
        await tester.tap(find.text('10 seconds'));
        await tester.pumpAndSettle();
      }
      if (find.text('9:16 · Portrait / Shorts').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('9:16 · Portrait / Shorts'));
        await tester.tap(find.text('9:16 · Portrait / Shorts'));
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      if (find.text('1080p').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('1080p'));
        await tester.tap(find.text('1080p'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Generate Video'));
      expect(find.text('Generate Video'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Generate Video'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
