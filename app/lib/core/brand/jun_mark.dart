import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// Marque JUN AI : un J qui plonge dans un crochet, une feuille qui pousse
/// à son sommet et une étincelle d'intelligence artificielle.
///
/// Les coordonnées (viewBox 108) sont celles de `app/branding/jun_mark.svg`,
/// source de vérité du logo : toute évolution du dessin se fait dans les deux.
class JunMarkPainter extends CustomPainter {
  const JunMarkPainter({
    this.stem = 1,
    this.leaf = 1,
    this.spark = 1,
    this.sparkColor = const Color(0xFFF4EFE4),
  });

  /// Avancement du tracé du J, de la feuille et de l'étincelle (0 à 1).
  final double stem;
  final double leaf;
  final double spark;

  /// Couleur de l'étincelle (crème sur fond sombre, encre sur fond clair).
  final Color sparkColor;

  static const Color leafColor = Color(0xFFFF7A59);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 108 * 0.88);
    canvas.translate(-54, -54);

    // Feuille : elle pivote autour de sa base, au sommet de la tige.
    final leafT = leaf.clamp(0.0, 1.0).toDouble();
    if (leafT > 0) {
      canvas.save();
      canvas.translate(57, 42);
      canvas.scale(Curves.easeOutBack.transform(leafT));
      canvas.rotate((1 - leafT) * -0.5);
      canvas.translate(-57, -42);
      final leafPath = Path()
        ..moveTo(57, 42)
        ..cubicTo(54, 33, 61, 24, 74, 23)
        ..cubicTo(76, 35, 69, 44, 57, 42)
        ..close();
      canvas.drawPath(leafPath, Paint()..color = leafColor);
      canvas.restore();
    }

    // J : la tige se trace, puis plonge dans le crochet.
    final stemT = stem.clamp(0.0, 1.0).toDouble();
    if (stemT > 0) {
      final jPath = Path()
        ..moveTo(57, 44)
        ..lineTo(57, 64)
        ..cubicTo(57, 74.5, 51.5, 81, 42.5, 81)
        ..cubicTo(36, 81, 31.5, 77.5, 30, 71.5);
      final metric = jPath.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * stemT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = SgPalette.lime,
      );
    }

    // Étincelle : elle apparaît en tournant sur elle-même.
    final sparkT = spark.clamp(0.0, 1.0).toDouble();
    if (sparkT > 0) {
      canvas.save();
      canvas.translate(35, 36);
      canvas.scale(Curves.easeOutBack.transform(sparkT));
      canvas.rotate((1 - sparkT) * math.pi / 2);
      canvas.translate(-35, -36);
      final sparkPath = Path()
        ..moveTo(35, 28)
        ..cubicTo(35.6, 33.4, 37.6, 35.4, 43, 36)
        ..cubicTo(37.6, 36.6, 35.6, 38.6, 35, 44)
        ..cubicTo(34.4, 38.6, 32.4, 36.6, 27, 36)
        ..cubicTo(32.4, 35.4, 34.4, 33.4, 35, 28)
        ..close();
      canvas.drawPath(sparkPath, Paint()..color = sparkColor);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(JunMarkPainter oldDelegate) =>
      oldDelegate.stem != stem ||
      oldDelegate.leaf != leaf ||
      oldDelegate.spark != spark ||
      oldDelegate.sparkColor != sparkColor;
}

/// La marque seule, entièrement tracée.
class JunMark extends StatelessWidget {
  const JunMark({
    super.key,
    this.size = 96,
    this.sparkColor = const Color(0xFFF4EFE4),
  });

  final double size;
  final Color sparkColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: JunMarkPainter(sparkColor: sparkColor)),
    );
  }
}

/// L'icône de l'app : la marque sur sa tuile d'encre, halo citron en coin.
class JunTile extends StatelessWidget {
  const JunTile({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        gradient: RadialGradient(
          center: const Alignment(0.7, -0.76),
          radius: 1.1,
          colors: [
            SgPalette.lime.withValues(alpha: 0.30),
            SgPalette.inkDark,
          ],
          stops: const [0, 0.75],
        ),
        color: SgPalette.inkDark,
      ),
      child: Center(child: JunMark(size: size * 0.9)),
    );
  }
}
