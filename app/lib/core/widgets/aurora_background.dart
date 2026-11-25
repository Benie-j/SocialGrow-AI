import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Fond animé : trois halos lumineux qui dérivent lentement.
/// L'animation s'arrête si l'utilisateur a demandé de réduire les animations.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SgPalette.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuroraPainter(
              animation: _controller,
              palette: palette,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.animation, required this.palette})
      : super(repaint: animation);

  final Animation<double> animation;
  final SgPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);

    final t = animation.value * 2 * math.pi;
    final reach = size.longestSide;

    void orb(Color color, double fx, double fy, double radius, double phase) {
      final center = Offset(
        size.width * (fx + 0.12 * math.sin(t + phase)),
        size.height * (fy + 0.07 * math.cos(t + phase)),
      );
      final r = reach * radius;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: palette.orbAlpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }

    orb(palette.accent, 0.12, 0.10, 0.55, 0);
    orb(palette.accentCool, 0.95, 0.40, 0.45, 2.1);
    orb(palette.accentWarm, 0.25, 0.95, 0.50, 4.2);
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
