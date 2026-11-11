import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('theme_mode');
    switch (stored) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      case 'system':
        _themeMode = ThemeMode.system;
        break;
      default:
        _themeMode = ThemeMode.light;
        break;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    switch (mode) {
      case ThemeMode.light:
        await prefs.setString('theme_mode', 'light');
        break;
      case ThemeMode.dark:
        await prefs.setString('theme_mode', 'dark');
        break;
      case ThemeMode.system:
        await prefs.setString('theme_mode', 'system');
        break;
    }
    notifyListeners();
  }
}

class AppTheme {
  static const Color primary = Color(0xFF6D4AFF);
  static const Color primaryDark = Color(0xFF5736D9);
  static const Color secondary = Color(0xFF3B82F6);
  static const Color cyan = Color(0xFF6BE7FF);
  static const Color deepBlue = Color(0xFF0F172E);
  static const Color darkBackground = Color(0xFF070C19);
  static const Color darkSurface = Color(0xFF101827);
  static const Color darkSurfaceElevated = Color(0xFF162235);
  static const Color darkBorder = Color(0xFF27324A);
  static const Color softDark = Color(0xFF1A2438);

  static const Color lightBackground = Color(0xFFF6F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFEAF1FF);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color darkTextSecondary = Color(0xFFB7C0D9);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFFC857);
  static const Color danger = Color(0xFFFF6B6B);

  static ThemeData get baseTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: primary,
      secondary: secondary,
      tertiary: cyan,
      surface: darkSurface,
      surfaceContainerHighest: darkSurfaceElevated,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
      outline: darkBorder,
      error: danger,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: Colors.white,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: Colors.white,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFFEFF3FF),
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: darkTextSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceElevated,
      hintStyle: const TextStyle(color: Color(0xFF9AA7BF)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: danger, width: 1.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: darkSurfaceElevated,
      selectedColor: primary.withValues(alpha: 0.18),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: primary,
      unselectedItemColor: Color(0xFF98A2B3),
      elevation: 0,
      showSelectedLabels: true,
      showUnselectedLabels: true,
    ),
  );

  static ThemeData darkTheme = baseTheme;

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBackground,
    colorScheme: const ColorScheme.light(
      brightness: Brightness.light,
      primary: primary,
      secondary: secondary,
      tertiary: cyan,
      surface: lightSurface,
      surfaceContainerHighest: lightSurfaceElevated,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightTextPrimary,
      outline: lightBorder,
      error: danger,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: lightTextPrimary,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: lightTextPrimary,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: lightTextPrimary,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: lightTextPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: lightTextPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: lightTextPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: lightTextSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: lightTextPrimary),
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface,
      hintStyle: const TextStyle(color: lightTextSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: danger, width: 1.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightTextPrimary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: lightSurfaceElevated,
      selectedColor: primary.withValues(alpha: 0.12),
      labelStyle: const TextStyle(
        color: lightTextPrimary,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: primary,
      unselectedItemColor: Color(0xFF77839A),
      elevation: 0,
      showSelectedLabels: true,
      showUnselectedLabels: true,
    ),
  );
}
