import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/main.dart';

void main() {
  testWidgets('affiche les cinq rubriques de navigation', (tester) async {
    await tester.pumpWidget(const SocialGrowApp());

    for (final label in [
      'Tableau de bord',
      'Création IA',
      'Calendrier',
      'Statistiques',
      'Paramètres',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });
}
