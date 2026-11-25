import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Fond de l'application : aplat chaud, trame de points façon carnet
/// et un halo citron discret en haut à droite. Entièrement statique.
class SgBackground extends StatelessWidget {
  const SgBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SgPalette.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _BackgroundPainter(palette: palette)),
        ),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({required this.palette});

  final SgPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);

    final glowCenter = Offset(size.width * 0.95, size.height * 0.04);
    final glowRadius = size.longestSide * 0.55;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            SgPalette.lime.withValues(alpha: palette.isDark ? 0.14 : 0.45),
            SgPalette.lime.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    final dots = Paint()
      ..color = palette.textPrimary.withValues(alpha: palette.isDark ? 0.08 : 0.09);
    const gap = 24.0;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1, dots);
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
