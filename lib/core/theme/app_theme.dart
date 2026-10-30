import 'package:flutter/material.dart';

class AppTheme {
  // 21st.dev High-End Assistive Design Palette (UI/UX Pro Max)
  static const Color background = Color(0xFF080C14); // Deep OLED True Black
  static const Color oledBlack = Color(0xFF000000); // True pitch black for camera viewports
  static const Color surface = Color(0xFF0F172A); // Translucent slate card base
  static const Color surfaceHighlight = Color(0xFF1E293B); // Elevated active surface
  static const Color primary = Color(0xFFF59E0B); // Electric Amber (#F59E0B)
  static const Color primaryDark = Color(0xFFD97706);
  static const Color onPrimary = Color(0xFF000000);
  static const Color accentCyan = Color(0xFF06B6D4); // High-Contrast Cyan (#06B6D4)
  static const Color accentYellow = Color(0xFFFFEB3B); // Safety bright yellow
  static const Color textPrimary = Color(0xFFFFFFFF); // High-contrast pure white
  static const Color textSecondary = Color(0xFFE2E8F0); // Very light grey (WCAG AAA)
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color success = Color(0xFF10B981); // Vivid Emerald (#10B981)
  static const Color accentGreen = success;
  static const Color danger = Color(0xFFFF3B30); // Crimson safety warning
  static const Color border = Color(0xFF1E293B);
  static const Color glassBorder = Color(0x1FFFFFFF); // 1px rgba(255, 255, 255, 0.08)
  static const Color glassSurface = Color(0xD90F172A); // Frosted translucent glass

  static ThemeData get highContrastDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        secondary: accentCyan,
        onSecondary: Color(0xFF000000),
        surface: surface,
        onSurface: textPrimary,
        error: danger,
        onError: Color(0xFF000000),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),
    );
  }
}
