import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/widgets/growth_plant.dart';

void main() {
  for (final growth in [0.0, 0.5, 1.0]) {
    testWidgets('la plante se dessine à $growth', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GrowthPlant(growth: growth, size: 200)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));

      expect(find.byType(GrowthPlant), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
