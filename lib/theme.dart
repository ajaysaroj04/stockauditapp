import 'package:flutter/material.dart';

/// High-contrast theme with large touch targets for dealership / yard use.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B5FFF),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF4F6FA),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(fontSize: 16),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
  );
}

/// Colour used for each fuel type across the app.
Color fuelColor(String fuel) {
  switch (fuel.toLowerCase()) {
    case 'petrol':
      return const Color(0xFFE8590C);
    case 'diesel':
      return const Color(0xFF495057);
    case 'cng':
      return const Color(0xFF2B8A3E);
    case 'ev':
      return const Color(0xFF1C7ED6);
    case 'hybrid':
      return const Color(0xFF7048E8);
    case 'lpg':
      return const Color(0xFF0C8599);
    default:
      return const Color(0xFF868E96);
  }
}
