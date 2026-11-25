import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';
import 'package:socialgrow_ai/data/publication_settings_repository.dart';
import 'package:socialgrow_ai/data/workspace_overview.dart';
import 'package:socialgrow_ai/data/workspace_repository.dart';

/// Renvoie successivement les résultats donnés (le dernier se répète).
class _FakeWorkspaceRepository implements WorkspaceRepository {
  _FakeWorkspaceRepository(this._results);

  final List<Object> _results;
  int calls = 0;

  @override
  Future<WorkspaceOverview> load() async {
    final index = calls < _results.length ? calls : _results.length - 1;
    final result = _results[index];
    calls++;
    if (result is WorkspaceOverview) return result;
    throw result;
  }
}

class _PendingWorkspaceRepository implements WorkspaceRepository {
  final Completer<WorkspaceOverview> completer = Completer();

  @override
  Future<WorkspaceOverview> load() => completer.future;
}

const _overview = WorkspaceOverview(
  workspaceId: 'ws-1',
  workspaceName: 'Mon équipe',
  role: 'owner',
  activePageCount: 1,
  displayName: 'Awa Kouassi',
);

Future<void> _pumpShell(WidgetTester tester, WorkspaceRepository repo) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        onSignOut: () async {},
        userName: 'Bénie Jean',
        workspaceRepository: repo,
studioPage: const Column(
  children: [
    Text('Ce qui arrive'),
    Text('Idées de publications'),
  ],
),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  test('libellés des rôles', () {
    WorkspaceOverview withRole(String role) => WorkspaceOverview(
          workspaceId: 'w',
          workspaceName: 'n',
          role: role,
          activePageCount: 0,
        );

    expect(withRole('owner').roleLabel, 'Propriétaire');
    expect(withRole('admin').roleLabel, 'Administrateur');
    expect(withRole('editor').roleLabel, 'Éditeur');
    expect(withRole('viewer').roleLabel, 'Lecteur');
    expect(withRole('autre').roleLabel, 'autre');
  });

  test('une Page est connectée dès qu’une Page active existe', () {
    expect(_overview.hasConnectedPage, isTrue);
    expect(
      const WorkspaceOverview(
        workspaceId: 'w',
        workspaceName: 'n',
        role: 'viewer',
        activePageCount: 0,
      ).hasConnectedPage,
      isFalse,
    );
  });

  testWidgets('affiche l’espace réel, le rôle, le profil et la Page',
      (tester) async {
    await _pumpShell(tester, _FakeWorkspaceRepository([_overview]));

    expect(find.text('Mon équipe'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.text('Awa'), findsOneWidget);
    expect(find.text('1 Page connectée.'), findsOneWidget);
    expect(find.text('Connectée'), findsOneWidget);
  });

  testWidgets('indique le chargement sans inventer de données', (tester) async {
    await _pumpShell(tester, _PendingWorkspaceRepository());

    expect(find.text('Chargement de ton espace…'), findsOneWidget);
    expect(find.text('Mon équipe'), findsNothing);
    expect(find.text('À connecter'), findsOneWidget);
  });

  testWidgets('une erreur propose de réessayer', (tester) async {
    final repo = _FakeWorkspaceRepository([
      const NoWorkspaceException(),
      _overview,
    ]);
    await _pumpShell(tester, repo);

    expect(find.textContaining('Aucun espace de travail'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(repo.calls, 2);
    expect(find.text('Mon équipe'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });
}
