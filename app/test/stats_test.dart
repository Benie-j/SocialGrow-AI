import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/stats.dart';

StatPost _published(DateTime at, {String type = 'text', String source = 'manual'}) =>
    StatPost(
      status: 'published',
      contentType: type,
      source: source,
      publishedAt: at,
    );

void main() {
  // Jeudi 26 novembre 2026.
  final now = DateTime(2026, 11, 26, 12);

  test('sans publication, tout est à zéro et vide', () {
    final s = PostStats.compute(const [], now);
    expect(s.isEmpty, isTrue);
    expect(s.weeks, hasLength(kStatWeeks));
    expect(s.busiestWeekday, isNull);
    expect(s.deltaVsPrev, isNull);
  });

  test('compte les publications sur 30 jours et la période précédente', () {
    final s = PostStats.compute([
      _published(DateTime(2026, 11, 20), type: 'image', source: 'ai'),
      _published(DateTime(2026, 11, 3)),
      _published(DateTime(2026, 10, 15)), // 30–60 jours avant
      _published(DateTime(2026, 10, 10)),
      _published(DateTime(2026, 10, 5)),
    ], now);
    expect(s.published30, 2);
    expect(s.publishedPrev30, 3);
    expect(s.deltaVsPrev, -1);
    expect(s.aiPublished30, 1);
    expect(s.byType, {'image': 1, 'text': 1});
  });

  test('range les publications dans la bonne semaine (lundi)', () {
    final s = PostStats.compute([
      _published(DateTime(2026, 11, 23, 8)), // lundi de la semaine en cours
      _published(DateTime(2026, 11, 22, 23)), // dimanche précédent
    ], now);
    expect(s.weeks.last.monday, DateTime(2026, 11, 23));
    expect(s.weeks.last.count, 1);
    expect(s.weeks[kStatWeeks - 2].count, 1);
  });

  test('compte les statuts à venir, en échec et brouillons', () {
    final s = PostStats.compute([
      StatPost(status: 'scheduled', contentType: 'text', source: 'manual', scheduledAt: DateTime(2026, 11, 28)),
      const StatPost(status: 'pending_approval', contentType: 'text', source: 'ai'),
      const StatPost(status: 'failed', contentType: 'text', source: 'manual'),
      const StatPost(status: 'draft', contentType: 'text', source: 'manual'),
      const StatPost(status: 'cancelled', contentType: 'text', source: 'manual'),
    ], now);
    expect(s.upcoming, 2);
    expect(s.failed, 1);
    expect(s.drafts, 1);
    expect(s.isEmpty, isFalse);
  });

  test('jour le plus actif : seulement avec assez de recul', () {
    final few = PostStats.compute([
      _published(DateTime(2026, 11, 24)),
      _published(DateTime(2026, 11, 17)),
    ], now);
    expect(few.busiestWeekday, isNull);

    final many = PostStats.compute([
      _published(DateTime(2026, 11, 24)), // mardi
      _published(DateTime(2026, 11, 17)), // mardi
      _published(DateTime(2026, 11, 10)), // mardi
      _published(DateTime(2026, 11, 12)), // jeudi
    ], now);
    expect(many.busiestWeekday, DateTime.tuesday);
  });

  test('mesures Meta : somme des flux, dernière valeur des stocks', () {
    final m = summarizeInsights([
      {'metric_date': '2026-11-20', 'metric_name': 'page_impressions_unique', 'metric_value': 100},
      {'metric_date': '2026-11-21', 'metric_name': 'page_impressions_unique', 'metric_value': 50},
      {'metric_date': '2026-11-20', 'metric_name': 'page_fans', 'metric_value': 300},
      {'metric_date': '2026-11-22', 'metric_name': 'page_fans', 'metric_value': 310},
    ]);
    expect(m.first.label, 'Portée');
    expect(m.first.value, 150);
    final fans = m.firstWhere((e) => e.name == 'page_fans');
    expect(fans.value, 310);
    expect(fans.isTotal, isFalse);
  });
}
