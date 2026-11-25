import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Carte de l'application. En mode [highlight], elle prend un trait d'encre
/// marqué et une ombre franche décalée, façon sticker éditorial.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
    this.onTap,
    this.highlight = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool highlight;

  /// Fond personnalisé (par défaut, le fond de carte de la palette).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final shape = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);

    final borderColor = highlight
        ? (p.isDark ? p.ink.withValues(alpha: 0.7) : p.ink)
        : p.glassBorder;

    final shadows = <BoxShadow>[
      if (highlight && !p.isDark)
        BoxShadow(
          color: p.ink,
          offset: const Offset(5, 5),
          blurRadius: 0,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: color ?? p.glass,
        borderRadius: shape,
        border: Border.all(color: borderColor, width: highlight ? 1.6 : 1),
        boxShadow: shadows,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: shape,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
