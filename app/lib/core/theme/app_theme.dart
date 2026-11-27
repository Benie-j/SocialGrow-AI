import 'package:material_ui/material_ui.dart';

import 'sg_palette.dart';

/// Thèmes Material de JUN AI (identité « Sève »).
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(SgPalette.dark, Brightness.dark);

  static ThemeData light() => _build(SgPalette.light, Brightness.light);

  static ThemeData _build(SgPalette p, Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F6B45),
      brightness: brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: dark ? SgPalette.inkDark : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF2A3A12) : const Color(0xFFDDF59A),
      onPrimaryContainer:
          dark ? const Color(0xFFE3F7A8) : const Color(0xFF0F2A1D),
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: dark ? const Color(0xFF5A6B5C) : const Color(0xFF8A8F7E),
      outlineVariant:
          dark ? const Color(0xFF2A362C) : const Color(0xFFD6CFBC),
      surfaceContainerLow:
          dark ? const Color(0xFF111812) : const Color(0xFFFBF8F0),
      surfaceContainer:
          dark ? const Color(0xFF161E18) : const Color(0xFFF0EADB),
      surfaceContainerHigh:
          dark ? const Color(0xFF1C251E) : const Color(0xFFE8E1CF),
      surfaceContainerHighest:
          dark ? const Color(0xFF222D25) : const Color(0xFFDFD7C2),
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
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
          height: 1.02,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
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
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? p.navFill : SgPalette.inkDark,
        contentTextStyle: TextStyle(
          color: dark ? p.textPrimary : SgPalette.lime,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
