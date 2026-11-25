import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Bouton principal à dégradé signature, avec halo lumineux.
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
    final radius = BorderRadius.circular(20);

    return Opacity(
      opacity: onPressed == null ? 0.65 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: SgPalette.brand,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: p.accent.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 12),
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
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
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
