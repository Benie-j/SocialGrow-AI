import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/data/notifications.dart';
import 'package:socialgrow_ai/data/notifications_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/notifications_page.dart';

AppNotification _notification(
  String id,
  String kind,
  String title, {
  String? body,
  Duration ago = const Duration(minutes: 5),
  bool read = false,
}) {
  final created = DateTime.now().subtract(ago);
  return AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: created,
    readAt: read ? created : null,
  );
}

class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository(
    this.overview, {
    this.failLoadTimes = 0,
    this.failSave = false,
  });

  final NotificationsOverview overview;
  int failLoadTimes;
  final bool failSave;
  int loads = 0;
  final List<String> markedRead = [];
  bool markedAll = false;
  NotificationPreferences? saved;

  @override
  Future<NotificationsOverview> load() async {
    loads++;
    if (failLoadTimes > 0) {
      failLoadTimes--;
      throw Exception('hors ligne');
    }
    return overview;
  }

  @override
  Future<void> savePreferences(
    String workspaceId,
    NotificationPreferences preferences,
  ) async {
    if (failSave) throw Exception('refusé');
    saved = preferences;
  }

  @override
  Future<void> markRead(String notificationId) async =>
      markedRead.add(notificationId);

  @override
  Future<void> markAllRead(String workspaceId) async => markedAll = true;
}

NotificationsOverview _overview({List<AppNotification>? items}) {
  return NotificationsOverview(
    workspaceId: 'ws-1',
    preferences: const NotificationPreferences(),
    items: items ??
        [
          _notification(
            'n1',
            NotificationKinds.aiDraftReady,
            'Nouveau brouillon IA',
            body: 'Un brouillon t’attend dans le Studio.',
          ),
          _notification(
            'n2',
            NotificationKinds.publishSuccess,
            'Publication réussie',
            ago: const Duration(hours: 3),
            read: true,
          ),
        ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  FakeNotificationsRepository repository,
) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: NotificationsPage(repository: repository)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('modèle', () {
    test('sans préférence enregistrée, tout est activé', () {
      final prefs = NotificationPreferences.fromRow(null);
      expect(prefs.publishSuccess, isTrue);
      expect(prefs.publishFailure, isTrue);
      expect(prefs.aiDraftReady, isTrue);
      expect(prefs.facebookIssue, isTrue);
    });

    test('lit les préférences de la base', () {
      final prefs = NotificationPreferences.fromRow({
        'publish_success': false,
        'publish_failure': true,
        'ai_draft_ready': false,
        'facebook_issue': true,
      });
      expect(prefs.publishSuccess, isFalse);
      expect(prefs.aiDraftReady, isFalse);
      expect(prefs.toRow()['publish_success'], isFalse);
    });

    test('lit une notification et compte les non lues', () {
      final n = AppNotification.fromRow({
        'id': 'a',
        'kind': 'publish_failure',
        'title': 'Échec',
        'body': null,
        'post_id': null,
        'created_at': '2026-11-26T10:00:00+00:00',
        'read_at': null,
      });
      expect(n.isUnread, isTrue);
      expect(n.markedRead(DateTime.now()).isUnread, isFalse);
      expect(_overview().unreadCount, 1);
    });

    test('temps relatif', () {
      final now = DateTime(2026, 11, 26, 12);
      expect(relativeTime(now.subtract(const Duration(seconds: 10)), now),
          'À l’instant');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now),
          'Il y a 5 min');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now),
          'Il y a 3 h');
      expect(relativeTime(now.subtract(const Duration(days: 1)), now), 'Hier');
      expect(relativeTime(now.subtract(const Duration(days: 4)), now),
          'Il y a 4 j');
      expect(
        relativeTime(DateTime(2026, 10, 3, 12), now),
        '03/10/2026',
      );
    });
  });

  testWidgets('affiche les alertes et les notifications réelles',
      (tester) async {
    await _pump(tester, FakeNotificationsRepository(_overview()));

    expect(find.text('Publication réussie'), findsNWidgets(2));
    expect(find.text('Nouveau brouillon IA'), findsOneWidget);
    expect(find.text('Un brouillon t’attend dans le Studio.'), findsOneWidget);
    expect(find.text('Il y a 5 min'), findsOneWidget);
    expect(find.text('Il y a 3 h'), findsOneWidget);
    expect(find.text('1 non lue'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(4));
  });

  testWidgets('toucher une notification non lue la marque comme lue',
      (tester) async {
    final repo = FakeNotificationsRepository(_overview());
    await _pump(tester, repo);

    await tester.tap(find.text('Nouveau brouillon IA'));
    await tester.pump();

    expect(repo.markedRead, ['n1']);
    expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    expect(find.text('1 non lue'), findsNothing);
    expect(find.text('Tout marquer comme lu'), findsNothing);
  });

  testWidgets('tout marquer comme lu', (tester) async {
    final repo = FakeNotificationsRepository(
      _overview(
        items: [
          _notification('a', NotificationKinds.publishFailure, 'Échec A'),
          _notification('b', NotificationKinds.facebookIssue, 'Facebook B'),
        ],
      ),
    );
    await _pump(tester, repo);

    expect(find.text('2 non lues'), findsOneWidget);
    await tester.tap(find.text('Tout marquer comme lu'));
    await tester.pump();
    await tester.pump();

    expect(repo.markedAll, isTrue);
    expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    expect(find.text('2 non lues'), findsNothing);
  });

  testWidgets('une alerte se désactive et s’enregistre', (tester) async {
    final repo = FakeNotificationsRepository(_overview());
    await _pump(tester, repo);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(repo.saved?.publishFailure, isFalse);
    expect(repo.saved?.publishSuccess, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
  });

  testWidgets('un échec d’enregistrement annule le changement',
      (tester) async {
    final repo = FakeNotificationsRepository(_overview(), failSave: true);
    await _pump(tester, repo);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(find.textContaining('Une erreur est survenue'), findsOneWidget);
  });

  testWidgets('état vide', (tester) async {
    await _pump(
      tester,
      FakeNotificationsRepository(_overview(items: const [])),
    );

    expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
    expect(find.text('Tout marquer comme lu'), findsNothing);
  });

  testWidgets('une erreur de chargement propose de réessayer', (tester) async {
    final repo = FakeNotificationsRepository(_overview(), failLoadTimes: 1);
    await _pump(tester, repo);

    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.loads, 2);
    expect(find.text('Nouveau brouillon IA'), findsOneWidget);
  });
}
