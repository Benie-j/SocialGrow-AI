import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Bouton principal : encre et citron, avec une ombre franche décalée.
class SgGradientButton extends StatelessWidget {
  const SgGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final radius = BorderRadius.circular(18);
    final fill = p.isDark ? SgPalette.lime : SgPalette.inkDark;
    final onFill = p.isDark ? SgPalette.inkDark : SgPalette.lime;

    return Opacity(
      opacity: onPressed == null ? 0.7 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          boxShadow: [
            if (!p.isDark)
              BoxShadow(
                color: p.accent,
                offset: const Offset(4, 4),
                blurRadius: 0,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: SizedBox(
              height: 58,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: onFill,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, color: onFill),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        color: onFill,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
