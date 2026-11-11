import 'package:flutter/material.dart';

import 'pages/splash_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeController.instance.loadThemeMode();
  runApp(const OpenMontageApp());
}

class OpenMontageApp extends StatelessWidget {
  const OpenMontageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'OpenMontage',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: AppThemeController.instance.themeMode,
        home: const SplashPage(),
      ),
    );
  }
}
