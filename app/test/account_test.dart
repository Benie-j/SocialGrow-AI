import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/data/account.dart';
import 'package:socialgrow_ai/data/account_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/account_page.dart';

AccountDetails _details({
  String role = 'owner',
  String? displayName = 'Awa Koné',
  int? memberCount = 3,
}) {
  return AccountDetails(
    email: 'awa@example.com',
    providers: const ['google'],
    createdAt: DateTime(2026, 11, 20, 9, 5),
    lastSignInAt: DateTime(2026, 11, 26, 10, 53),
    emailConfirmed: true,
    displayName: displayName,
    avatarUrl: null,
    workspaceId: 'ws-1',
    workspaceName: 'Atelier Awa',
    role: role,
    workspaceCreatedAt: DateTime(2026, 11, 20),
    memberCount: memberCount,
    activePageCount: 1,
    pageName: 'Atelier Awa Officiel',
  );
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this.details, {this.failLoad = false});

  final AccountDetails details;
  final bool failLoad;
  String? savedName;
  String? renamedTo;

  @override
  Future<AccountDetails> load() async {
    if (failLoad) throw Exception('hors ligne');
    return details;
  }

  @override
  Future<void> saveDisplayName(String name) async => savedName = name;

  @override
  Future<void> renameWorkspace(String workspaceId, String name) async =>
      renamedTo = name;
}

Future<void> _pump(
  WidgetTester tester,
  FakeAccountRepository repository, {
  Future<void> Function()? onSignOut,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // L'écran est poussé par-dessus une route de base, comme dans l'application.
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AccountPage(
                repository: repository,
                onSignOut: onSignOut,
              ),
            ),
          ),
          child: const Text('ouvrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('outils de compte', () {
    test('formate les dates en français', () {
      final date = DateTime(2026, 11, 26, 8, 5);
      expect(formatFrenchDate(date), '26 novembre 2026');
      expect(formatFrenchDateTime(date), '26 novembre 2026 à 08:05');
      expect(formatFrenchDate(DateTime(2027, 2, 1)), '1 février 2027');
    });

    test('libellés de méthode de connexion et de rôle', () {
      expect(providerLabel('email'), 'E-mail et mot de passe');
      expect(providerLabel('google'), 'Google');
      expect(providerLabel('discord'), 'Discord');
      expect(accountRoleLabel('admin'), 'Administrateur');
      expect(accountRoleLabel('autre'), 'autre');
    });

    test('initiales : nom d’abord, sinon e-mail', () {
      expect(initialsOf('awa koné', 'x@y.z'), 'AK');
      expect(initialsOf('  Awa  ', null), 'A');
      expect(initialsOf(null, 'bob@y.z'), 'B');
      expect(initialsOf(null, null), '?');
    });

    test('seuls propriétaire et admin peuvent renommer l’espace', () {
      expect(_details(role: 'owner').canRenameWorkspace, isTrue);
      expect(_details(role: 'admin').canRenameWorkspace, isTrue);
      expect(_details(role: 'editor').canRenameWorkspace, isFalse);
      expect(_details(role: 'viewer').canRenameWorkspace, isFalse);
    });
  });

  group('écran', () {
    testWidgets('affiche les données réelles du compte', (tester) async {
      await _pump(tester, FakeAccountRepository(_details()));

      expect(find.text('Awa Koné'), findsWidgets);
      expect(find.text('awa@example.com'), findsWidgets);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('20 novembre 2026'), findsWidgets);
      expect(find.text('26 novembre 2026 à 10:53'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1 (Atelier Awa Officiel)'), findsOneWidget);
    });

    testWidgets('enregistre le nom affiché', (tester) async {
      final repository = FakeAccountRepository(_details());
      await _pump(tester, repository);

      final before = tester.widget<FilledButton>(
        find.byKey(const ValueKey('save_name')),
      );
      expect(before.onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('display_name')),
        '  Awa K.  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save_name')));
      await tester.pumpAndSettle();

      expect(repository.savedName, 'Awa K.');
      expect(find.text('Nom enregistré.'), findsOneWidget);
    });

    testWidgets('le propriétaire peut renommer l’espace', (tester) async {
      final repository = FakeAccountRepository(_details());
      await _pump(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('workspace_name')),
        'Studio Awa',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rename_workspace')));
      await tester.pumpAndSettle();

      expect(repository.renamedTo, 'Studio Awa');
    });

    testWidgets('un éditeur ne peut pas renommer l’espace', (tester) async {
      await _pump(
        tester,
        FakeAccountRepository(_details(role: 'editor', memberCount: null)),
      );

      expect(find.byKey(const ValueKey('workspace_name')), findsNothing);
      expect(find.text('Atelier Awa'), findsOneWidget);
      expect(find.text('Membres'), findsNothing);
    });

    testWidgets('sans nom, affiche un texte explicite', (tester) async {
      await _pump(
        tester,
        FakeAccountRepository(_details(displayName: null)),
      );

      expect(find.text('Nom non renseigné'), findsOneWidget);
    });

    testWidgets('la déconnexion demande une confirmation', (tester) async {
      var signedOut = false;
      await _pump(
        tester,
        FakeAccountRepository(_details()),
        onSignOut: () async => signedOut = true,
      );

      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Se déconnecter ?'), findsOneWidget);
      expect(signedOut, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });

    testWidgets('une erreur de chargement propose de réessayer', (tester) async {
      await _pump(
        tester,
        FakeAccountRepository(_details(), failLoad: true),
      );

      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}
