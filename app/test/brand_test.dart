import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/brand/jun_mark.dart';
import 'package:socialgrow_ai/features/splash/presentation/splash_gate.dart';

void main() {
  testWidgets('la marque et la tuile JUN AI se dessinent sans erreur',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [JunMark(), JunTile(size: 64)]),
        ),
      ),
    );

    expect(find.byType(JunMark), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final progress in [0.0, 0.25, 0.6, 1.0]) {
    testWidgets('la marque se trace à $progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(120, 120),
              painter: JunMarkPainter(
                stem: progress,
                leaf: progress,
                spark: progress,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('le splash affiche la marque puis laisse place à l’app',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(child: Text('accueil')),
      ),
    );

    expect(find.text('JUN'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('accueil'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('accueil'), findsOneWidget);
    expect(find.text('JUN'), findsNothing);
  });
}
