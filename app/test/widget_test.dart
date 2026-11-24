import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';

void main() {
  testWidgets('affiche les cinq rubriques de navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          onSignOut: () async {},
        ),
      ),
    );

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Création IA'), findsOneWidget);
    expect(find.text('Calendrier'), findsOneWidget);
    expect(find.text('Statistiques'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('affiche le tableau de bord', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          onSignOut: () async {},
        ),
      ),
    );

    expect(find.text('Bienvenue 👋'), findsOneWidget);
    expect(find.text('Ton espace de travail'), findsOneWidget);
  });
}
