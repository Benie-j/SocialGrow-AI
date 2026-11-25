import 'package:material_ui/material_ui.dart';

/// Palette « Sève » de SocialGrow AI : papier chaud et encre en mode clair,
/// nuit de serre en mode sombre, avec un vert citron comme signal d'énergie.
class SgPalette {
  const SgPalette._({
    required this.isDark,
    required this.background,
    required this.glass,
    required this.glassBorder,
    required this.navFill,
    required this.ink,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentCool,
    required this.accentWarm,
    required this.success,
  });

  /// Vert citron signature : toujours associé à de l'encre foncée.
  static const Color lime = Color(0xFFC8F23A);

  /// Encre : texte et traits forts posés sur le citron.
  static const Color inkDark = Color(0xFF111611);

  /// Dégradé signature (forêt), lisible avec du texte blanc.
  static const LinearGradient brand = LinearGradient(
    colors: [Color(0xFF0E3B2B), Color(0xFF17644A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const SgPalette dark = SgPalette._(
    isDark: true,
    background: Color(0xFF0B100D),
    glass: Color(0xFF131A15),
    glassBorder: Color(0x33E6F5D0),
    navFill: Color(0xFF1B251E),
    ink: Color(0xFFC8F23A),
    textPrimary: Color(0xFFF2F5EA),
    textSecondary: Color(0xFF9AA896),
    accent: Color(0xFFC8F23A),
    accentCool: Color(0xFF6FD3E8),
    accentWarm: Color(0xFFFF7A59),
    success: Color(0xFF5BE0A0),
  );

  static const SgPalette light = SgPalette._(
    isDark: false,
    background: Color(0xFFF4EFE4),
    glass: Color(0xFFFBF8F0),
    glassBorder: Color(0x4D111611),
    navFill: Color(0xFF111611),
    ink: Color(0xFF111611),
    textPrimary: Color(0xFF111611),
    textSecondary: Color(0xFF5B6357),
    accent: Color(0xFF0F6B45),
    accentCool: Color(0xFF0B7C97),
    accentWarm: Color(0xFFE5482A),
    success: Color(0xFF138A55),
  );

  static SgPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final bool isDark;
  final Color background;

  /// Fond des cartes.
  final Color glass;

  /// Trait discret (séparateurs, cartes secondaires).
  final Color glassBorder;

  /// Fond de la barre de navigation.
  final Color navFill;

  /// Trait fort des cartes mises en avant.
  final Color ink;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentCool;
  final Color accentWarm;
  final Color success;
}
