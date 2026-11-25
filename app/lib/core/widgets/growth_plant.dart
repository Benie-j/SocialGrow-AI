import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Plante vivante dessinée à la main (CustomPainter) : elle pousse avec la
/// progression de l'utilisateur et se balance doucement.
///
/// [growth] va de 0 (jeune pousse) à 1 (pleine floraison).
class GrowthPlant extends StatefulWidget {
  const GrowthPlant({
    super.key,
    required this.growth,
    this.size = 220,
    this.duration = const Duration(milliseconds: 1600),
  });

  final double growth;
  final double size;
  final Duration duration;

  @override
  State<GrowthPlant> createState() => _GrowthPlantState();
}

class _GrowthPlantState extends State<GrowthPlant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _sway.stop();
    } else if (!_sway.isAnimating) {
      _sway.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SgPalette.of(context);
    final target = widget.growth.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: _reduceMotion ? Duration.zero : widget.duration,
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => CustomPaint(
            painter: _PlantPainter(
              growth: value,
              sway: _sway,
              palette: palette,
            ),
          ),
        ),
      ),
    );
  }
}

class _Leaf {
  const _Leaf(this.at, this.side, this.length);

  /// Position sur la tige (0 = pied, 1 = sommet).
  final double at;

  /// -1 = gauche, 1 = droite.
  final int side;

  /// Longueur relative à la largeur du dessin.
  final double length;
}

class _PlantPainter extends CustomPainter {
  _PlantPainter({
    required this.growth,
    required this.sway,
    required this.palette,
  }) : super(repaint: sway);

  final double growth;
  final Animation<double> sway;
  final SgPalette palette;

  static const _leaves = [
    _Leaf(0.16, -1, 0.26),
    _Leaf(0.28, 1, 0.28),
    _Leaf(0.42, -1, 0.25),
    _Leaf(0.56, 1, 0.24),
    _Leaf(0.70, -1, 0.21),
    _Leaf(0.82, 1, 0.18),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Ombre au sol.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.965),
        width: w * 0.5,
        height: h * 0.045,
      ),
      Paint()..color = palette.textPrimary.withValues(alpha: 0.14),
    );

    // Pot.
    final pot = Path()
      ..moveTo(w * 0.35, h * 0.83)
      ..lineTo(w * 0.65, h * 0.83)
      ..lineTo(w * 0.61, h * 0.955)
      ..quadraticBezierTo(w * 0.60, h * 0.965, w * 0.58, h * 0.965)
      ..lineTo(w * 0.42, h * 0.965)
      ..quadraticBezierTo(w * 0.40, h * 0.965, w * 0.39, h * 0.955)
      ..close();
    canvas.drawPath(pot, Paint()..color = palette.accentWarm);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.32, h * 0.80, w * 0.68, h * 0.845),
        Radius.circular(w * 0.02),
      ),
      Paint()
        ..color = Color.lerp(palette.accentWarm, const Color(0xFF000000), 0.18)!,
    );

    // Balancement autour du pied de la tige.
    final base = Offset(w * 0.5, h * 0.81);
    final angle = (sway.value - 0.5) * 0.07;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    canvas.translate(-base.dx, -base.dy);

    final stemPath = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        w * 0.30,
        h * 0.62,
        w * 0.72,
        h * 0.40,
        w * 0.54,
        h * 0.13,
      );
    final metric = stemPath.computeMetrics().first;
    final visible = metric.length * growth;

    final leafA = palette.accent;
    final leafB = palette.isDark
        ? const Color(0xFF7FD6A0)
        : const Color(0xFF58B884);

    // Feuilles (derrière la tige).
    for (var i = 0; i < _leaves.length; i++) {
      final leaf = _leaves[i];
      final scale = ((growth - leaf.at) / 0.16).clamp(0.0, 1.0).toDouble();
      if (scale <= 0) continue;
      final tangent = metric.getTangentForOffset(metric.length * leaf.at);
      if (tangent == null) continue;
      _drawLeaf(
        canvas,
        tangent.position,
        tangent.angle + leaf.side * 0.85,
        w * leaf.length * Curves.easeOutBack.transform(scale),
        i.isEven ? leafA : leafB,
      );
    }

    // Tige.
    canvas.drawPath(
      metric.extractPath(0, visible),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..strokeCap = StrokeCap.round
        ..color = leafA,
    );

    // Bourgeon, puis fleur quand tout est prêt.
    final tip = metric.getTangentForOffset(visible)?.position;
    if (tip != null && growth > 0.05) {
      if (growth >= 0.995) {
        _drawBloom(canvas, tip, w * 0.085);
      } else {
        canvas.drawCircle(
          tip,
          w * 0.026 * (0.6 + growth * 0.8),
          Paint()..color = palette.accentWarm,
        );
      }
    }

    canvas.restore();
  }

  void _drawLeaf(
    Canvas canvas,
    Offset from,
    double angle,
    double length,
    Color color,
  ) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final perp = Offset(-dir.dy, dir.dx);
    final tip = from + dir * length;
    final mid = from + dir * (length * 0.5);
    final bulge = length * 0.38;

    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        mid.dx + perp.dx * bulge,
        mid.dy + perp.dy * bulge,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        mid.dx - perp.dx * bulge,
        mid.dy - perp.dy * bulge,
        from.dx,
        from.dy,
      );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      from,
      from + dir * (length * 0.8),
      Paint()
        ..color = palette.background.withValues(alpha: 0.35)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBloom(Canvas canvas, Offset center, double radius) {
    const petals = 8;
    final petalPaint = Paint()..color = palette.accentWarm;
    for (var i = 0; i < petals; i++) {
      final a = i * 2 * math.pi / petals;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * (radius * 0.62),
        radius * 0.38,
        petalPaint,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.42,
      Paint()..color = SgPalette.lime,
    );
    canvas.drawCircle(
      center,
      radius * 0.42,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = SgPalette.inkDark,
    );
  }

  @override
  bool shouldRepaint(_PlantPainter oldDelegate) =>
      oldDelegate.growth != growth || oldDelegate.palette != palette;
}
