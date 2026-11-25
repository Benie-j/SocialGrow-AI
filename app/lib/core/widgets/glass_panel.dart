import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Panneau translucide à bord lumineux, façon verre dépoli.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.onTap,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final shape = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);

    final shadows = <BoxShadow>[
      if (highlight)
        BoxShadow(
          color: p.accent.withValues(alpha: p.isDark ? 0.22 : 0.18),
          blurRadius: 32,
          offset: const Offset(0, 12),
        )
      else if (!p.isDark)
        const BoxShadow(
          color: Color(0x1A1B1F4B),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: p.glass,
        borderRadius: shape,
        border: Border.all(
          color: highlight ? p.accent.withValues(alpha: 0.55) : p.glassBorder,
        ),
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
