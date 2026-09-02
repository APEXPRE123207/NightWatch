import 'package:flutter/material.dart';

class NightWatchTheme {
  // Pure AMOLED black colors
  static const Color background = Color(0xFF07070A);
  static const Color surface = Color(0xFF101017);
  static const Color surfaceElevated = Color(0xFF181824);
  static const Color surfaceBorder = Color(0xFF252538);

  // Accent and status colors
  static const Color accentNormal = Color(0xFF10B981); // Emerald
  static const Color accentAnomaly = Color(0xFFEF4444); // Red/Coral
  static const Color accentMerge = Color(0xFFA855F7); // Purple
  static const Color accentWarming = Color(0xFFF59E0B); // Amber
  static const Color accentSpeech = Color(0xFF38BDF8); // Sky Blue
  static const Color accentMovement = Color(0xFFF97316); // Orange

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accentNormal,
        secondary: accentSpeech,
        surface: surface,
        surfaceContainerHighest: surfaceElevated,
        error: accentAnomaly,
        onPrimary: Colors.black,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: surfaceElevated,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return const TextStyle(color: textMuted, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentNormal, size: 24);
          }
          return const IconThemeData(color: textMuted, size: 24);
        }),
      ),
    );
  }
}
