import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';
import 'package:socialgrow_ai/features/dashboard/presentation/dashboard_page.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        onSignOut: () async {},
        userName: 'Bénie Jean',
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  testWidgets('affiche les cinq rubriques de navigation', (tester) async {
    await _pumpShell(tester);

    expect(find.byTooltip('Accueil'), findsOneWidget);
    expect(find.byTooltip('Studio'), findsOneWidget);
    expect(find.byTooltip('Agenda'), findsOneWidget);
    expect(find.byTooltip('Stats'), findsOneWidget);
    expect(find.byTooltip('Réglages'), findsOneWidget);
  });

  testWidgets('affiche le tableau de bord', (tester) async {
    await _pumpShell(tester);

    expect(
      find.textContaining(RegExp(r'^(Bonjour|Bon après-midi|Bonsoir)$')),
      findsOneWidget,
    );
    expect(find.text('Bénie'), findsOneWidget);
    expect(find.text('Parcours de lancement'), findsOneWidget);
    expect(find.text('Ton espace'), findsOneWidget);
  });

  testWidgets('la navigation ouvre la rubrique Studio', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byTooltip('Studio'));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Ce qui arrive'), findsOneWidget);
    expect(find.text('Idées de publications'), findsOneWidget);
  });

  testWidgets('une étape du parcours ouvre les réglages', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Définir ta stratégie éditoriale'));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Paramètres de publication'), findsOneWidget);
  });

  test('prénom affiché : nom complet, sinon début de l’e-mail', () {
    expect(DashboardPage.firstNameFrom('Bénie Jean', null), 'Bénie');
    expect(DashboardPage.firstNameFrom(null, 'marie.dupont@mail.fr'), 'Marie');
    expect(DashboardPage.firstNameFrom('  ', 'luc@mail.fr'), 'Luc');
    expect(DashboardPage.firstNameFrom(null, null), isNull);
  });

  test('salutation selon l’heure', () {
    expect(DashboardPage.greetingFor(8), 'Bonjour');
    expect(DashboardPage.greetingFor(15), 'Bon après-midi');
    expect(DashboardPage.greetingFor(21), 'Bonsoir');
    expect(DashboardPage.greetingFor(2), 'Bonsoir');
  });
}
