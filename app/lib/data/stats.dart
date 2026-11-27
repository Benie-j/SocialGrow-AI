import 'agenda.dart' show addDays, mondayOf;

/// Nombre de semaines affichées dans le graphique.
const int kStatWeeks = 8;

/// Fenêtre de lecture des publications (assez large pour comparer 2 × 30 j).
const int kStatWindowDays = 84;

/// Une publication, réduite à ce qu'il faut pour compter.
class StatPost {
  const StatPost({
    required this.status,
    required this.contentType,
    required this.source,
    this.scheduledAt,
    this.publishedAt,
  });

  factory StatPost.fromMap(Map<String, dynamic> m) {
    DateTime? date(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return StatPost(
      status: (m['status'] ?? 'draft').toString(),
      contentType: (m['content_type'] ?? 'text').toString(),
      source: (m['source'] ?? 'manual').toString(),
      scheduledAt: date(m['scheduled_at']),
      publishedAt: date(m['published_at']),
    );
  }

  final String status;
  final String contentType;
  final String source;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;

  /// Date réelle de publication si elle existe, sinon la date prévue.
  DateTime? get when => publishedAt ?? scheduledAt;
}

class WeekBar {
  const WeekBar(this.monday, this.count);

  final DateTime monday;
  final int count;
}

int _dayIndex(DateTime d, DateTime base) => DateTime.utc(d.year, d.month, d.day)
    .difference(DateTime.utc(base.year, base.month, base.day))
    .inDays;

/// Chiffres calculés à partir des publications réelles (rien d'inventé).
class PostStats {
  const PostStats({
    required this.published30,
    required this.publishedPrev30,
    required this.aiPublished30,
    required this.upcoming,
    required this.failed,
    required this.drafts,
    required this.weeks,
    required this.byType,
    required this.publishedInWindow,
    required this.weekdayCounts,
  });

  final int published30;
  final int publishedPrev30;
  final int aiPublished30;
  final int upcoming;
  final int failed;
  final int drafts;
  final List<WeekBar> weeks;

  /// Publications des 30 derniers jours, par format.
  final Map<String, int> byType;
  final int publishedInWindow;

  /// Publications de la fenêtre par jour de semaine (index 1 = lundi … 7).
  final List<int> weekdayCounts;

  bool get isEmpty =>
      publishedInWindow == 0 && upcoming == 0 && failed == 0 && drafts == 0;

  int get weekMax =>
      weeks.fold<int>(0, (m, w) => w.count > m ? w.count : m);

  /// Jour où tu publies le plus, seulement s'il y a assez de recul.
  int? get busiestWeekday {
    if (publishedInWindow < 3) return null;
    var best = 1;
    for (var d = 2; d <= 7; d++) {
      if (weekdayCounts[d] > weekdayCounts[best]) best = d;
    }
    return weekdayCounts[best] == 0 ? null : best;
  }

  /// Écart avec les 30 jours précédents ; null sans point de comparaison.
  int? get deltaVsPrev => publishedPrev30 == 0 ? null : published30 - publishedPrev30;

  static PostStats compute(List<StatPost> posts, DateTime now) {
    final firstMonday = addDays(mondayOf(now), -7 * (kStatWeeks - 1));
    final from30 = now.subtract(const Duration(days: 30));
    final from60 = now.subtract(const Duration(days: 60));
    final counts = List<int>.filled(kStatWeeks, 0);
    final weekdays = List<int>.filled(8, 0);
    final byType = <String, int>{};
    var published30 = 0;
    var prev30 = 0;
    var ai30 = 0;
    var upcoming = 0;
    var failed = 0;
    var drafts = 0;
    var inWindow = 0;

    for (final p in posts) {
      switch (p.status) {
        case 'published':
          final w = p.when;
          if (w == null || w.isAfter(now)) break;
          final idx = _dayIndex(w, firstMonday) ~/ 7;
          if (idx >= 0 && idx < kStatWeeks) {
            counts[idx]++;
            weekdays[w.weekday]++;
            inWindow++;
          }
          if (w.isAfter(from30)) {
            published30++;
            byType[p.contentType] = (byType[p.contentType] ?? 0) + 1;
            if (p.source == 'ai') ai30++;
          } else if (w.isAfter(from60)) {
            prev30++;
          }
        case 'scheduled' || 'pending_approval' || 'publishing':
          upcoming++;
        case 'failed':
          failed++;
        case 'draft':
          drafts++;
      }
    }

    return PostStats(
      published30: published30,
      publishedPrev30: prev30,
      aiPublished30: ai30,
      upcoming: upcoming,
      failed: failed,
      drafts: drafts,
      weeks: [
        for (var i = 0; i < kStatWeeks; i++)
          WeekBar(addDays(firstMonday, 7 * i), counts[i]),
      ],
      byType: byType,
      publishedInWindow: inWindow,
      weekdayCounts: weekdays,
    );
  }
}

/// Une mesure de Page collectée auprès de Meta (table `page_insights`).
class InsightMetric {
  const InsightMetric({
    required this.name,
    required this.label,
    required this.value,
    required this.isTotal,
  });

  final String name;
  final String label;
  final num value;

  /// Vrai pour une somme sur 28 jours, faux pour une valeur du jour (stock).
  final bool isTotal;
}

// Meta a retiré page_impressions*, page_fans et page_fan_adds : on lit les
// mesures actuelles (et les anciennes, pour l'historique déjà collecté).
const Map<String, String> _insightLabels = {
  'page_total_media_view_unique': 'Portée',
  'page_impressions_unique': 'Portée',
  'page_media_view': 'Vues',
  'page_impressions': 'Vues',
  'page_post_engagements': 'Interactions',
  'page_daily_follows': 'Nouveaux abonnés',
  'page_fan_adds': 'Nouveaux abonnés',
  'page_follows': 'Abonnés',
  'page_fans': 'Abonnés',
};

const Set<String> _stockMetrics = {'page_follows', 'page_fans'};

/// Agrège les lignes brutes de `page_insights` sur la fenêtre lue.
List<InsightMetric> summarizeInsights(List<Map<String, dynamic>> rows) {
  final sums = <String, num>{};
  final latest = <String, (String, num)>{};
  for (final row in rows) {
    final name = (row['metric_name'] ?? '').toString();
    if (name.isEmpty) continue;
    final raw = row['metric_value'];
    final value = raw is num ? raw : num.tryParse('$raw') ?? 0;
    final date = (row['metric_date'] ?? '').toString();
    if (_stockMetrics.contains(name)) {
      final seen = latest[name];
      if (seen == null || date.compareTo(seen.$1) > 0) {
        latest[name] = (date, value);
      }
    } else {
      sums[name] = (sums[name] ?? 0) + value;
    }
  }
  final out = <InsightMetric>[
    for (final e in sums.entries)
      InsightMetric(
        name: e.key,
        label: _insightLabels[e.key] ?? e.key,
        value: e.value,
        isTotal: true,
      ),
    for (final e in latest.entries)
      InsightMetric(
        name: e.key,
        label: _insightLabels[e.key] ?? e.key,
        value: e.value.$2,
        isTotal: false,
      ),
  ];
  out.sort((a, b) {
    final ia = _insightLabels.keys.toList().indexOf(a.name);
    final ib = _insightLabels.keys.toList().indexOf(b.name);
    return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
  });
  return out.take(6).toList();
}
