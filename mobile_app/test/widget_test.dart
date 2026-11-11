// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/main.dart';
import 'package:mobile_app/pages/processing_page.dart';

void main() {
  testWidgets('OpenMontage app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenMontageApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('processing page can be disposed without throwing', (
    WidgetTester tester,
  ) async {
    final testSize = const Size(400, 900);
    tester.view.physicalSize = testSize;
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: const SizedBox(
          width: 400,
          height: 900,
          child: ProcessingPage(
            jobId: 'job-123',
            projectId: 'project-123',
            title: 'Sample title',
            prompt: 'Sample prompt',
            style: 'Cinematic',
            duration: '30s',
            assetCount: 2,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });
}
