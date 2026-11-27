import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/data/agenda.dart';
import 'package:socialgrow_ai/data/agenda_repository.dart';
import 'package:socialgrow_ai/data/publication_settings.dart';
import 'package:socialgrow_ai/features/agenda/presentation/agenda_page.dart';

// Mercredi 25 novembre 2026, 10 h.
final _now = DateTime(2026, 11, 25, 10);

AgendaPost _post(
  String id,
  String headline,
  DateTime at, {
  String status = 'scheduled',
  String? body,
}) {
  return AgendaPost(
    id: id,
    status: status,
    contentType: 'text',
    body: body ?? headline,
    scheduledAt: status == 'published' ? null : at,
    publishedAt: status == 'published' ? at : null,
  );
}

class _FakeAgendaRepository implements AgendaRepository {
  _FakeAgendaRepository({
    this.role = 'owner',
    this.failFirst = false,
    List<AgendaPost>? posts,
  }) : posts = posts ?? [];

  final String role;
  bool failFirst;
  final List<AgendaPost> posts;
  final List<DateTime> rescheduledTo = [];

  @override
  Future<AgendaContext> loadContext() async {
    if (failFirst) {
      failFirst = false;
      throw Exception('réseau');
    }
    return AgendaContext(
      workspaceId: 'ws-1',
      role: role,
      settings: PublicationSettings(),
    );
  }

  @override
  Future<List<AgendaPost>> loadRange(
    String workspaceId,
    DateTime from,
    DateTime to,
  ) async {
    return posts
        .where((p) => !p.when!.isBefore(from) && p.when!.isBefore(to))
        .toList();
  }

  @override
  Future<void> reschedule({
    required String workspaceId,
    required String postId,
    required DateTime at,
  }) async {
    rescheduledTo.add(at);
  }
}

Future<void> _pumpAgenda(
  WidgetTester tester,
  AgendaRepository? repository,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AgendaPage(
          repository: repository,
          now: () => _now,
          onOpenStudio: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

List<AgendaPost> _samplePosts() => [
      _post('a', 'Publication matinale', DateTime(2026, 11, 25, 7),
          status: 'published'),
      _post('b', 'Offre du jeudi', DateTime(2026, 11, 26, 9, 30)),
    ];

void main() {
  group('logique de l’agenda', () {
    test('lundi de la semaine et libellés français', () {
      final monday = mondayOf(DateTime(2026, 11, 25));
      expect(monday, DateTime(2026, 11, 23));
      expect(FrDate.weekRange(monday), '23 – 29 nov. 2026');
      expect(FrDate.weekRange(DateTime(2026, 11, 30)), '30 nov. – 6 déc. 2026');
      expect(FrDate.dayLong(DateTime(2026, 11, 25)), 'mercredi 25 novembre');
      expect(FrDate.dayCompact(DateTime(2026, 11, 26)), 'jeu. 26 nov.');
      expect(FrDate.time(DateTime(2026, 11, 26, 9, 5)), '09:05');
    });

    test('créneaux libres : futurs, sur les jours préférés, espacés', () {
      final settings = PublicationSettings();

      final today = freeSlotsFor(
        DateTime(2026, 11, 25),
        settings: settings,
        posts: const [],
        now: _now,
      );
      expect(today.map((s) => FrDate.time(s.at)), ['12:00', '18:00']);

      final thursday = freeSlotsFor(
        DateTime(2026, 11, 26),
        settings: settings,
        posts: [_post('b', 'x', DateTime(2026, 11, 26, 9, 30))],
        now: _now,
      );
      // 08:00 est à 90 min du post : trop proche (intervalle minimum 120 min).
      expect(thursday.map((s) => FrDate.time(s.at)), ['12:00', '18:00']);

      final saturday = freeSlotsFor(
        DateTime(2026, 11, 28),
        settings: settings,
        posts: const [],
        now: _now,
      );
      expect(saturday, isEmpty);
    });

    test('horaires proposables : fenêtres autorisées par pas de 30 min', () {
      final times = candidateTimes(
        DateTime(2026, 11, 26),
        settings: PublicationSettings(),
      ).map(FrDate.time).toList();

      expect(times.first, '07:00');
      expect(times.last, '21:00');
      expect(times, contains('12:30'));
      expect(times, isNot(contains('06:30')));
    });

    test('un post annulé ou en brouillon ne bloque aucun créneau', () {
      final at = DateTime(2026, 11, 26, 12);
      expect(
        conflictsWithPosts(at, [_post('c', 'x', at, status: 'cancelled')], 120),
        isFalse,
      );
      expect(
        conflictsWithPosts(at, [_post('c', 'x', at)], 120),
        isTrue,
      );
      expect(
        conflictsWithPosts(at, [_post('c', 'x', at)], 120, excludeId: 'c'),
        isFalse,
      );
    });
  });

  group('écran Agenda', () {
    testWidgets('sans dépôt, l’agenda reste vide', (tester) async {
      await _pumpAgenda(tester, null);

      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('mercredi 25 novembre'), findsOneWidget);
      expect(find.text('Rien de prévu ce jour'), findsOneWidget);
    });

    testWidgets('affiche les vraies publications et les créneaux libres',
        (tester) async {
      await _pumpAgenda(tester, _FakeAgendaRepository(posts: _samplePosts()));

      expect(find.text('1 publication'), findsOneWidget);
      expect(find.text('Publication matinale'), findsOneWidget);
      expect(find.text('Publié'), findsOneWidget);
      expect(find.text('Créneau libre'), findsNWidgets(2));

      await tester.tap(find.text('26'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('jeudi 26 novembre'), findsOneWidget);
      expect(find.text('Offre du jeudi'), findsOneWidget);
      expect(find.text('Programmé'), findsOneWidget);
      expect(find.text('Créneau libre'), findsNWidgets(2));
    });

    testWidgets('une erreur de chargement propose de réessayer',
        (tester) async {
      await _pumpAgenda(
        tester,
        _FakeAgendaRepository(posts: _samplePosts(), failFirst: true),
      );

      expect(find.text('Réessayer'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Publication matinale'), findsOneWidget);
    });

    testWidgets('un lecteur ne peut pas reprogrammer', (tester) async {
      await _pumpAgenda(
        tester,
        _FakeAgendaRepository(role: 'viewer', posts: _samplePosts()),
      );
      await tester.tap(find.text('26'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Offre du jeudi'), findsOneWidget);
      expect(find.text('Reprogrammer'), findsNothing);
    });

    testWidgets('reprogramme une publication sur un horaire autorisé',
        (tester) async {
      final repository = _FakeAgendaRepository(posts: _samplePosts());
      await _pumpAgenda(tester, repository);

      await tester.tap(find.text('26'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Reprogrammer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Choisis un horaire'), findsOneWidget);

      await tester.tap(find.text('16:00'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('à 16:00'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(repository.rescheduledTo, [DateTime(2026, 11, 26, 16)]);
      expect(find.text('Publication reprogrammée.'), findsOneWidget);
    });
  });
}
