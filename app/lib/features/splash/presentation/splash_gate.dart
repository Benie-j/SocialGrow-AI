import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/brand/jun_mark.dart';
import '../../../core/theme/sg_palette.dart';

/// Écran de démarrage animé de JUN AI, puis passage en fondu vers [child].
///
/// L'écran natif Android (couleur d'encre) précède celui-ci sans coupure :
/// la marque se dessine alors sur le même fond.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _started = false;
  bool _reduceMotion = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      // Marque déjà tracée, simple temps d'affichage.
      _controller.duration = const Duration(milliseconds: 700);
    }
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : _SplashScreen(
              key: const ValueKey('splash'),
              animation: _controller,
              reduceMotion: _reduceMotion,
            ),
    );
  }
}

double _segment(double t, double from, double to, [Curve? curve]) {
  final value = ((t - from) / (to - from)).clamp(0.0, 1.0).toDouble();
  return (curve ?? Curves.linear).transform(value);
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({
    super.key,
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Semantics(
        label: 'JUN AI',
        child: ColoredBox(
          color: SgPalette.inkDark,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.9, -0.95),
                    radius: 1.15,
                    colors: [
                      SgPalette.lime.withValues(alpha: 0.26),
                      SgPalette.lime.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = reduceMotion ? 1.0 : animation.value;
                  final settle = _segment(t, 0, 0.5, Curves.easeOutCubic);
                  final word = _segment(t, 0.52, 0.80, Curves.easeOutCubic);
                  final tagline = _segment(t, 0.66, 0.90, Curves.easeOut);

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.9 + 0.1 * settle,
                          child: SizedBox(
                            width: 170,
                            height: 170,
                            child: CustomPaint(
                              painter: JunMarkPainter(
                                stem: _segment(
                                  t,
                                  0.04,
                                  0.38,
                                  Curves.easeInOutCubic,
                                ),
                                leaf: _segment(t, 0.34, 0.58),
                                spark: _segment(t, 0.50, 0.70),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: word,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - word)),
                            child: const _Wordmark(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Opacity(
                          opacity: tagline,
                          child: const Text(
                            'Fais grandir ta Page Facebook.',
                            style: TextStyle(
                              color: Color(0xFFB9C4B5),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'JUN',
          style: TextStyle(
            color: Color(0xFFF4EFE4),
            fontSize: 46,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(width: 10),
        Transform.rotate(
          angle: -0.07,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: SgPalette.lime,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                color: SgPalette.inkDark,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
                height: 1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
