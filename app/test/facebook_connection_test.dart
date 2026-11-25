import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';
import 'package:socialgrow_ai/data/facebook_connection.dart';
import 'package:socialgrow_ai/data/workspace_overview.dart';
import 'package:socialgrow_ai/data/workspace_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/facebook_connection_page.dart';

const _soleil = FacebookPageChoice(
  metaPageId: '100000000000001',
  name: 'Boulangerie Soleil',
  category: 'Boulangerie',
);

const _port = FacebookPageChoice(
  metaPageId: '100000000000002',
  name: 'Café du Port',
  category: 'Café',
);

const _connectedPort = ConnectedFacebookPage(
  id: 'db-2',
  metaPageId: '100000000000002',
  name: 'Café du Port',
  category: 'Café',
);

class _FakeFacebookRepository implements FacebookConnectionRepository {
  _FakeFacebookRepository({
    this.hasSession = true,
    this.pages = const [_soleil, _port],
    this.listError,
    this.connectError,
    this.longLived = true,
  });

  bool hasSession;
  List<FacebookPageChoice> pages;
  Object? listError;
  Object? connectError;
  bool longLived;

  int listCalls = 0;
  int disconnectCalls = 0;
  int reauthCalls = 0;
  final List<String> connectCalls = [];

  @override
  bool get hasFacebookSession => hasSession;

  @override
  Future<List<FacebookPageChoice>> listPages(String workspaceId) async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return pages;
  }

  @override
  Future<FacebookConnectResult> connect(
    String workspaceId,
    String metaPageId,
  ) async {
    connectCalls.add(metaPageId);
    final error = connectError;
    if (error != null) throw error;
    final choice = pages.firstWhere((p) => p.metaPageId == metaPageId);
    return FacebookConnectResult(
      page: ConnectedFacebookPage(
        id: 'db-$metaPageId',
        metaPageId: metaPageId,
        name: choice.name,
        category: choice.category,
      ),
      longLived: longLived,
    );
  }

  @override
  Future<void> disconnect(String workspaceId) async {
    disconnectCalls++;
  }

  @override
  Future<void> reauthenticate() async {
    reauthCalls++;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeFacebookRepository repository, {
  bool canEdit = true,
  ConnectedFacebookPage? connected,
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
        canEdit: canEdit,
        connectedPage: connected,
        onChanged: onChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('erreurs', () {
    test('les codes de session ou de permission demandent une reconnexion', () {
      for (final code in [
        'facebook_token_missing',
        'facebook_token_invalid',
        'facebook_permission_missing',
        'unauthenticated',
      ]) {
        expect(FacebookConnectionException(code, 'x').needsReauth, isTrue);
      }
      for (final code in ['forbidden', 'page_not_found', 'network']) {
        expect(FacebookConnectionException(code, 'x').needsReauth, isFalse);
      }
    });

    test('une erreur inconnue devient un message réseau lisible', () {
      final error = facebookErrorFrom(StateError('boom'));
      expect(error.code, 'network');
      expect(error.message, contains('Impossible de joindre le serveur'));
    });

    test('une erreur déjà typée est conservée', () {
      const original = FacebookConnectionException('forbidden', 'Non.');
      expect(identical(facebookErrorFrom(original), original), isTrue);
    });
  });

  group('modèles', () {
    test('une ligne facebook_pages devient une Page connectée', () {
      final page = ConnectedFacebookPage.fromRow({
        'id': 'db-1',
        'meta_page_id': '100000000000001',
        'page_name': 'Boulangerie Soleil',
        'category': '  ',
        'picture_url': 'https://cdn.test/a.jpg',
      });
      expect(page.name, 'Boulangerie Soleil');
      expect(page.metaPageId, '100000000000001');
      expect(page.category, isNull);
      expect(page.pictureUrl, 'https://cdn.test/a.jpg');
    });

    test('la réponse de la fonction de liste ne contient aucun jeton', () {
      final choice = FacebookPageChoice.fromMap({
        'id': '100000000000001',
        'name': 'Boulangerie Soleil',
        'category': 'Bakery',
        'picture_url': null,
      });
      expect(choice.metaPageId, '100000000000001');
      expect(choice.pictureUrl, isNull);
    });

    test('seuls propriétaire, admin et éditeur gèrent la Page', () {
      WorkspaceOverview withRole(String role) => WorkspaceOverview(
            workspaceId: 'w',
            workspaceName: 'n',
            role: role,
            activePageCount: 0,
          );
      expect(withRole('owner').canManagePage, isTrue);
      expect(withRole('admin').canManagePage, isTrue);
      expect(withRole('editor').canManagePage, isTrue);
      expect(withRole('viewer').canManagePage, isFalse);
    });
  });

  group('écran Connexion Facebook', () {
    testWidgets('liste les Pages sans Page connectée', (tester) async {
      final repository = _FakeFacebookRepository();
      await _pumpPage(tester, repository);

      expect(find.text('Aucune Page connectée'), findsOneWidget);
      expect(find.text('Choisis ta Page'), findsOneWidget);
      expect(find.text('Boulangerie Soleil'), findsOneWidget);
      expect(find.text('Café du Port'), findsOneWidget);
      expect(repository.listCalls, 1);

      // Rien n'est choisi : le bouton reste inactif.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('choisir une Page puis la connecter', (tester) async {
      final repository = _FakeFacebookRepository();
      var changed = 0;
      await _pumpPage(
        tester,
        repository,
        onChanged: () async {
          changed++;
        },
      );

      await tester.tap(find.text('Boulangerie Soleil'));
      await tester.pump();
      await tester.tap(find.text('Connecter cette Page'));
      await tester.pumpAndSettle();

      expect(repository.connectCalls, ['100000000000001']);
      expect(changed, 1);
      expect(find.text('Connectée'), findsOneWidget);
      expect(find.text('Déconnecter la Page'), findsOneWidget);
      expect(find.text('Page connectée : Boulangerie Soleil.'), findsOneWidget);
    });

    testWidgets('prévient quand la connexion est temporaire', (tester) async {
      final repository = _FakeFacebookRepository(longLived: false);
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Café du Port'));
      await tester.pump();
      await tester.tap(find.text('Connecter cette Page'));
      await tester.pumpAndSettle();

      expect(find.textContaining('temporaire'), findsOneWidget);
    });

    testWidgets('la Page connectée n’est pas reproposée', (tester) async {
      final repository = _FakeFacebookRepository();
      await _pumpPage(tester, repository, connected: _connectedPort);

      expect(find.text('Changer de Page'), findsOneWidget);
      // Une seule fois : dans la carte « connectée », pas dans la liste.
      expect(find.text('Café du Port'), findsOneWidget);
      expect(find.text('Boulangerie Soleil'), findsOneWidget);
      expect(find.text('Connectée'), findsOneWidget);
    });

    testWidgets('changer de Page remplace la Page connectée', (tester) async {
      final repository = _FakeFacebookRepository();
      await _pumpPage(tester, repository, connected: _connectedPort);

      await tester.tap(find.text('Boulangerie Soleil'));
      await tester.pump();
      await tester.tap(find.text('Utiliser cette Page'));
      await tester.pumpAndSettle();

      expect(repository.connectCalls, ['100000000000001']);
      // La carte du haut affiche maintenant la nouvelle Page.
      expect(find.text('Boulangerie Soleil'), findsOneWidget);
      expect(find.text('Café du Port'), findsOneWidget);
    });

    testWidgets('déconnexion : confirmation puis appel', (tester) async {
      final repository = _FakeFacebookRepository();
      var changed = 0;
      await _pumpPage(
        tester,
        repository,
        connected: _connectedPort,
        onChanged: () async {
          changed++;
        },
      );

      await tester.tap(find.text('Déconnecter la Page'));
      await tester.pumpAndSettle();
      expect(find.text('Déconnecter la Page ?'), findsOneWidget);
      expect(repository.disconnectCalls, 0);

      await tester.tap(find.text('Déconnecter'));
      await tester.pumpAndSettle();

      expect(repository.disconnectCalls, 1);
      expect(changed, 1);
      expect(find.text('Aucune Page connectée'), findsOneWidget);
      expect(find.text('Page déconnectée.'), findsOneWidget);
    });

    testWidgets('annuler la déconnexion ne fait rien', (tester) async {
      final repository = _FakeFacebookRepository();
      await _pumpPage(tester, repository, connected: _connectedPort);

      await tester.tap(find.text('Déconnecter la Page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repository.disconnectCalls, 0);
      expect(find.text('Déconnecter la Page'), findsOneWidget);
    });

    testWidgets('un lecteur est en lecture seule et n’appelle rien',
        (tester) async {
      final repository = _FakeFacebookRepository();
      await _pumpPage(
        tester,
        repository,
        canEdit: false,
        connected: _connectedPort,
      );

      expect(find.textContaining('Lecture seule'), findsOneWidget);
      expect(find.text('Déconnecter la Page'), findsNothing);
      expect(find.text('Boulangerie Soleil'), findsNothing);
      expect(repository.listCalls, 0);
    });

    testWidgets('sans session Facebook : reconnexion proposée', (tester) async {
      final repository = _FakeFacebookRepository(hasSession: false);
      await _pumpPage(tester, repository);

      expect(repository.listCalls, 0);
      expect(find.text('Se reconnecter avec Facebook'), findsOneWidget);

      await tester.tap(find.text('Se reconnecter avec Facebook'));
      await tester.pump();
      expect(repository.reauthCalls, 1);
    });

    testWidgets('session expirée côté Facebook : reconnexion proposée',
        (tester) async {
      final repository = _FakeFacebookRepository(
        listError: const FacebookConnectionException(
          'facebook_token_invalid',
          'La session Facebook a expiré.',
        ),
      );
      await _pumpPage(tester, repository);

      expect(find.text('La session Facebook a expiré.'), findsOneWidget);
      expect(find.text('Se reconnecter avec Facebook'), findsOneWidget);
    });

    testWidgets('une erreur réseau propose de réessayer', (tester) async {
      final repository = _FakeFacebookRepository(
        listError: const FacebookConnectionException(
          'network',
          'Impossible de joindre le serveur.',
        ),
      );
      await _pumpPage(tester, repository);

      expect(find.text('Impossible de joindre le serveur.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      repository.listError = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
      expect(find.text('Boulangerie Soleil'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('un refus du serveur à la connexion affiche son message',
        (tester) async {
      final repository = _FakeFacebookRepository(
        connectError: const FacebookConnectionException(
          'page_not_found',
          'Cette Page ne fait pas partie de celles que tu gères.',
        ),
      );
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Boulangerie Soleil'));
      await tester.pump();
      await tester.tap(find.text('Connecter cette Page'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cette Page ne fait pas partie de celles que tu gères.'),
        findsOneWidget,
      );
      expect(find.text('Aucune Page connectée'), findsOneWidget);
    });

    testWidgets('aucune Page gérée : message explicite', (tester) async {
      final repository = _FakeFacebookRepository(pages: const []);
      await _pumpPage(tester, repository);

      expect(find.textContaining('aucune Page que tu gères'), findsOneWidget);
      expect(find.text('Actualiser'), findsOneWidget);
    });
  });

  group('intégration dans l’application', () {
    const withoutPage = WorkspaceOverview(
      workspaceId: 'ws-1',
      workspaceName: 'Mon équipe',
      role: 'owner',
      activePageCount: 0,
    );
    const withPage = WorkspaceOverview(
      workspaceId: 'ws-1',
      workspaceName: 'Mon équipe',
      role: 'owner',
      activePageCount: 1,
      connectedPage: ConnectedFacebookPage(
        id: 'db-1',
        metaPageId: '100000000000001',
        name: 'Boulangerie Soleil',
        category: 'Boulangerie',
      ),
    );

    Future<void> pumpShell(
      WidgetTester tester, {
      required WorkspaceRepository workspace,
      required FacebookConnectionRepository facebook,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            onSignOut: () async {},
            userName: 'Bénie Jean',
            workspaceRepository: workspace,
            facebookRepository: facebook,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
    }

    testWidgets('le tableau de bord affiche la Page connectée', (tester) async {
      await pumpShell(
        tester,
        workspace: _SequenceWorkspaceRepository([withPage]),
        facebook: _FakeFacebookRepository(),
      );

      expect(find.text('Boulangerie Soleil est connectée.'), findsOneWidget);
      expect(find.text('Boulangerie Soleil'), findsOneWidget);
      expect(find.text('Connectée'), findsOneWidget);
    });

    testWidgets('sans Page, le tableau de bord invite à en connecter une',
        (tester) async {
      await pumpShell(
        tester,
        workspace: _SequenceWorkspaceRepository([withoutPage]),
        facebook: _FakeFacebookRepository(),
      );

      expect(find.text('Choisis la Page à faire grandir.'), findsOneWidget);
      expect(find.text('À connecter'), findsOneWidget);
    });

    testWidgets('connecter une Page depuis les Réglages met l’accueil à jour',
        (tester) async {
      final workspace = _SequenceWorkspaceRepository([withoutPage, withPage]);
      final facebook = _FakeFacebookRepository();
      await pumpShell(tester, workspace: workspace, facebook: facebook);
      expect(find.text('À connecter'), findsOneWidget);

      await tester.tap(find.byTooltip('Réglages'));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.text('Connexion Facebook'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Choisis ta Page'), findsOneWidget);
      await tester.tap(find.text('Boulangerie Soleil'));
      await tester.pump();
      await tester.tap(find.text('Connecter cette Page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(facebook.connectCalls, ['100000000000001']);
      // L'espace de travail a été rechargé après la connexion.
      expect(workspace.calls, 2);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Accueil'));
      await tester.pump(const Duration(milliseconds: 1500));

      expect(find.text('Boulangerie Soleil est connectée.'), findsOneWidget);
      expect(find.text('Connectée'), findsOneWidget);
    });

    testWidgets('la rubrique Facebook reste fermée sans dépôt', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(onSignOut: () async {}, userName: 'Bénie Jean'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.byTooltip('Réglages'));
      await tester.pump(const Duration(milliseconds: 1500));

      await tester.tap(find.text('Connexion Facebook'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Choisis ta Page'), findsNothing);
    });
  });
}

/// Renvoie successivement les espaces donnés (le dernier se répète).
class _SequenceWorkspaceRepository implements WorkspaceRepository {
  _SequenceWorkspaceRepository(this._results);

  final List<WorkspaceOverview> _results;
  int calls = 0;

  @override
  Future<WorkspaceOverview> load() async {
    final index = calls < _results.length ? calls : _results.length - 1;
    calls++;
    return _results[index];
  }
}
