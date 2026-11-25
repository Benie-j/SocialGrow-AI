import 'package:material_ui/material_ui.dart';

/// Palette « Aurore » de SocialGrow AI, déclinée en mode sombre et clair.
class SgPalette {
  const SgPalette._({
    required this.isDark,
    required this.background,
    required this.glass,
    required this.glassBorder,
    required this.navFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentCool,
    required this.accentWarm,
    required this.success,
    required this.orbAlpha,
  });

  /// Dégradé signature (violet → fuchsia), lisible avec du texte blanc.
  static const LinearGradient brand = LinearGradient(
    colors: [Color(0xFF6D4AFF), Color(0xFFC026D3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const SgPalette dark = SgPalette._(
    isDark: true,
    background: Color(0xFF070B1A),
    glass: Color(0x14FFFFFF),
    glassBorder: Color(0x26FFFFFF),
    navFill: Color(0xF20E1330),
    textPrimary: Color(0xFFF4F6FF),
    textSecondary: Color(0xFFA3ADCF),
    accent: Color(0xFF8B6CFF),
    accentCool: Color(0xFF22D3EE),
    accentWarm: Color(0xFFFF5FC8),
    success: Color(0xFF34D399),
    orbAlpha: 0.38,
  );

  static const SgPalette light = SgPalette._(
    isDark: false,
    background: Color(0xFFF6F5FF),
    glass: Color(0xB3FFFFFF),
    glassBorder: Color(0x1F1B1F4B),
    navFill: Color(0xF5FFFFFF),
    textPrimary: Color(0xFF14172E),
    textSecondary: Color(0xFF5A6080),
    accent: Color(0xFF5B3DF5),
    accentCool: Color(0xFF0891B2),
    accentWarm: Color(0xFFE11D8F),
    success: Color(0xFF059669),
    orbAlpha: 0.30,
  );

  static SgPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final bool isDark;
  final Color background;
  final Color glass;
  final Color glassBorder;
  final Color navFill;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentCool;
  final Color accentWarm;
  final Color success;
  final double orbAlpha;
}
