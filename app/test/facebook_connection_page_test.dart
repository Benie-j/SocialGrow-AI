import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';
import 'package:socialgrow_ai/data/facebook_connection.dart';
import 'package:socialgrow_ai/data/workspace_overview.dart';
import 'package:socialgrow_ai/data/workspace_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/facebook_connection_page.dart';
import 'package:socialgrow_ai/features/settings/presentation/settings_page.dart';

class FakeFacebookRepository implements FacebookConnectionRepository {
  FakeFacebookRepository({
    this.authorized = true,
    List<ConnectedFacebookPage>? connected,
    this.available = const [
      FacebookPage(
        metaPageId: '1001',
        name: 'Boutique Awa',
        category: 'Commerce',
      ),
      FacebookPage(metaPageId: '1002', name: 'Atelier Kofi'),
    ],
    this.listError,
    this.connectError,
  }) : connected = connected ?? [];

  bool authorized;
  final List<ConnectedFacebookPage> connected;
  final List<FacebookPage> available;
  final Object? listError;
  final Object? connectError;

  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  int reauthorizeCalls = 0;

  @override
  bool get hasFacebookAuthorization => authorized;

  @override
  Stream<void> get sessionChanges => const Stream<void>.empty();

  @override
  Future<List<ConnectedFacebookPage>> loadConnected(String workspaceId) async =>
      List.of(connected);

  @override
  Future<List<FacebookPage>> listAvailablePages() async {
    final error = listError;
    if (error != null) throw error;
    return available;
  }

  @override
  Future<ConnectedFacebookPage> connectPage({
    required String workspaceId,
    required FacebookPage page,
  }) async {
    final error = connectError;
    if (error != null) throw error;
    connectCalls.add(page.metaPageId);
    final created = ConnectedFacebookPage(
      id: 'row-${page.metaPageId}',
      metaPageId: page.metaPageId,
      name: page.name,
      category: page.category,
    );
    // Une seule Page active par espace : la nouvelle remplace la précédente.
    connected
      ..clear()
      ..add(created);
    return created;
  }

  @override
  Future<void> disconnect(String workspaceId) async {
    disconnectCalls.add(workspaceId);
    connected.clear();
  }

  @override
  Future<void> reauthorize() async {
    reauthorizeCalls++;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  FacebookConnectionRepository repository, {
  String role = 'owner',
  Future<void> Function()? onChanged,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: FacebookConnectionPage(
        repository: repository,
        workspaceId: 'ws-1',
        role: role,
        onChanged: onChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('une Page Meta est lue avec ses champs facultatifs', () {
    final page = FacebookPage.fromMap({
      'id': 1001,
      'name': ' Boutique Awa ',
      'category': '',
      'picture_url': 'https://exemple.test/a.png',
    });

    expect(page.metaPageId, '1001');
    expect(page.name, 'Boutique Awa');
    expect(page.category, isNull);
    expect(page.pictureUrl, 'https://exemple.test/a.png');
  });

  testWidgets('un propriétaire voit ses Pages et peut en connecter une',
      (tester) async {
    final repository = FakeFacebookRepository();
    var changed = 0;
    await _pumpPage(
      tester,
      repository,
      onChanged: () async => changed++,
    );

    expect(find.text('Aucune Page n’est connectée pour le moment.'),
        findsOneWidget);
    expect(find.text('Boutique Awa'), findsOneWidget);
    expect(find.text('Atelier Kofi'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Connecter').first);
    await tester.pumpAndSettle();

    expect(repository.connectCalls, ['1001']);
    expect(changed, 1);
    // La Page connectée passe dans la liste du haut et quitte les propositions.
    expect(find.text('Connectée'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connecter'), findsOneWidget);
  });

  testWidgets('un éditeur peut connecter une Page', (tester) async {
    final repository = FakeFacebookRepository();
    await _pumpPage(tester, repository, role: 'editor');

    await tester.tap(find.widgetWithText(FilledButton, 'Connecter').first);
    await tester.pumpAndSettle();

    expect(repository.connectCalls, ['1001']);
  });

  testWidgets('connecter une autre Page remplace la précédente',
      (tester) async {
    final repository = FakeFacebookRepository(
      connected: [
        const ConnectedFacebookPage(
          id: 'row-1',
          metaPageId: '1001',
          name: 'Boutique Awa',
        ),
      ],
    );
    await _pumpPage(tester, repository);

    // Seule la Page non connectée est proposée.
    expect(find.text('Atelier Kofi'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Connecter'));
    await tester.pumpAndSettle();

    expect(repository.connected.map((c) => c.metaPageId), ['1002']);
    expect(find.text('Connectée'), findsOneWidget);
  });

  testWidgets('un lecteur ne peut ni connecter ni déconnecter',
      (tester) async {
    final repository = FakeFacebookRepository(
      connected: [
        const ConnectedFacebookPage(
          id: 'row-1',
          metaPageId: '1001',
          name: 'Boutique Awa',
        ),
      ],
    );
    await _pumpPage(tester, repository, role: 'viewer');

    expect(find.text('Boutique Awa'), findsOneWidget);
    expect(find.textContaining('Seuls les propriétaires'), findsOneWidget);
    expect(find.text('Déconnecter'), findsNothing);
    expect(find.text('Connecter'), findsNothing);
  });

  testWidgets('sans autorisation Facebook, propose de la redemander',
      (tester) async {
    final repository = FakeFacebookRepository(authorized: false);
    await _pumpPage(tester, repository);

    expect(find.text('Connecter'), findsNothing);
    await tester.tap(find.text('Autoriser l’accès à mes Pages'));
    await tester.pumpAndSettle();

    expect(repository.reauthorizeCalls, 1);
  });

  testWidgets('une erreur de liste s’affiche avec un bouton Réessayer',
      (tester) async {
    final repository = FakeFacebookRepository(
      listError: const FacebookConnectionException(
        'L’autorisation Facebook a expiré.',
      ),
    );
    await _pumpPage(tester, repository);

    expect(find.text('L’autorisation Facebook a expiré.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('un refus du serveur à la connexion est signalé',
      (tester) async {
    final repository = FakeFacebookRepository(
      connectError: const FacebookConnectionException(
        'Tu ne gères pas cette Page.',
      ),
    );
    await _pumpPage(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Connecter').first);
    await tester.pumpAndSettle();

    expect(find.text('Tu ne gères pas cette Page.'), findsOneWidget);
    expect(repository.connectCalls, isEmpty);
  });

  testWidgets('la déconnexion demande confirmation puis retire la Page',
      (tester) async {
    final repository = FakeFacebookRepository(
      connected: [
        const ConnectedFacebookPage(
          id: 'row-1',
          metaPageId: '1001',
          name: 'Boutique Awa',
        ),
      ],
    );
    var changed = 0;
    await _pumpPage(
      tester,
      repository,
      onChanged: () async => changed++,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter cette Page ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Déconnecter'));
    await tester.pumpAndSettle();

    expect(repository.disconnectCalls, ['ws-1']);
    expect(changed, 1);
    expect(find.text('Aucune Page n’est connectée pour le moment.'),
        findsOneWidget);
  });

  testWidgets('la rubrique des Réglages ouvre l’écran de connexion',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            facebookRepository: FakeFacebookRepository(),
            workspace: const WorkspaceOverview(
              workspaceId: 'ws-1',
              workspaceName: 'Mon équipe',
              role: 'owner',
              activePageCount: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tap(find.text('Connexion Facebook'));
    await tester.pumpAndSettle();

    expect(find.byType(FacebookConnectionPage), findsOneWidget);
  });

  testWidgets('sans dépôt Facebook, la rubrique reste indisponible',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tap(find.text('Connexion Facebook'));
    await tester.pumpAndSettle();

    expect(find.byType(FacebookConnectionPage), findsNothing);
  });

  testWidgets('le tableau de bord affiche le nom de la Page connectée',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
  onSignOut: () async {},
  workspaceRepository: _FixedWorkspaceRepository(),
  studioPage: const SizedBox.shrink(),
),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Boutique Awa'), findsWidgets);
  });
}

class _FixedWorkspaceRepository implements WorkspaceRepository {
  @override
  Future<WorkspaceOverview> load() async => const WorkspaceOverview(
        workspaceId: 'ws-1',
        workspaceName: 'Mon équipe',
        role: 'owner',
        activePageCount: 1,
        pageName: 'Boutique Awa',
      );
}
