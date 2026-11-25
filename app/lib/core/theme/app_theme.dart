import 'package:material_ui/material_ui.dart';

import 'sg_palette.dart';

/// Thèmes Material de SocialGrow AI (identité « Aurore »).
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(SgPalette.dark, Brightness.dark);

  static ThemeData light() => _build(SgPalette.light, Brightness.light);

  static ThemeData _build(SgPalette p, Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6D4AFF),
      brightness: brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: dark ? const Color(0xFF12082E) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF2A1F66) : const Color(0xFFE6E0FF),
      onPrimaryContainer:
          dark ? const Color(0xFFE6DEFF) : const Color(0xFF2A1670),
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: dark ? const Color(0xFF4A5278) : const Color(0xFF9AA0C0),
      outlineVariant: dark ? const Color(0xFF2A3150) : const Color(0xFFD9DBEE),
      surfaceContainerLow:
          dark ? const Color(0xFF0F1430) : const Color(0xFFFFFFFF),
      surfaceContainer:
          dark ? const Color(0xFF141A3A) : const Color(0xFFF1EFFF),
      surfaceContainerHigh:
          dark ? const Color(0xFF1A2146) : const Color(0xFFEAE7FF),
      surfaceContainerHighest:
          dark ? const Color(0xFF202850) : const Color(0xFFE2DEFF),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final text = base.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: p.textPrimary,
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
