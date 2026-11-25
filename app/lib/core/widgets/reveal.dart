import 'package:material_ui/material_ui.dart';

/// Apparition en fondu + glissement, échelonnée selon [order].
class SgReveal extends StatelessWidget {
  const SgReveal({super.key, required this.child, this.order = 0});

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + order * 90),
      curve: Curves.easeOutCubic,
      builder: (context, value, inner) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}
