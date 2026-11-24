import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/data/publication_settings.dart';
import 'package:socialgrow_ai/data/publication_settings_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/publication_settings_page.dart';

class FakeRepository implements PublicationSettingsRepository {
  FakeRepository(String role)
      : access = WorkspaceAccess(
          workspaceId: 'ws-1',
          workspaceName: 'Mon équipe',
          role: role,
        );

  final WorkspaceAccess access;
  PublicationSettings? saved;

  @override
  Future<WorkspaceAccess> loadAccess() async => access;

  @override
  Future<PublicationSettings> load(String workspaceId) async =>
      PublicationSettings();

  @override
  Future<PublicationSettings> save(
    String workspaceId,
    PublicationSettings settings,
  ) async {
    final copy = PublicationSettings.fromMap(settings.toMap());
    saved = copy;
    return copy;
  }
}

Future<void> _pump(WidgetTester tester, FakeRepository repository) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: PublicationSettingsPage(repository: repository)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('affiche les sept sections de réglages', (tester) async {
    await _pump(tester, FakeRepository('owner'));

    for (final title in [
      'Fréquence',
      'Horaires',
      'Contenu',
      'Formats',
      'Automatisation',
      'Stratégie',
      'Gestion des doublons',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('un éditeur peut modifier et enregistrer', (tester) async {
    final repository = FakeRepository('editor');
    await _pump(tester, repository);

    // Le bouton est inactif tant que rien n’a changé.
    final before = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(before.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(repository.saved, isNotNull);
    expect(repository.saved?.postsPerDay, 2);
  });

  testWidgets('un lecteur voit les réglages en lecture seule', (tester) async {
    final repository = FakeRepository('viewer');
    await _pump(tester, repository);

    expect(find.textContaining('Lecture seule'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
  });
}
