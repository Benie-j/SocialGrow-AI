import 'package:supabase_flutter/supabase_flutter.dart';

import 'publication_settings_repository.dart';
import 'stats.dart';

/// Tout ce qu'affiche l'onglet Statistiques.
class StatsData {
  const StatsData({
    required this.posts,
    required this.insights,
    required this.hasPage,
  });

  final PostStats posts;

  /// Mesures Meta des 28 derniers jours (vide tant qu'aucune n'est collectée).
  final List<InsightMetric> insights;

  /// Au moins une Page Facebook active est connectée.
  final bool hasPage;
}

abstract class StatsRepository {
  Future<StatsData> load();
}

class SupabaseStatsRepository implements StatsRepository {
  SupabaseStatsRepository(this._client, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _now;

  @override
  Future<StatsData> load() async {
    final access =
        await SupabasePublicationSettingsRepository(_client).loadAccess();
    final id = access.workspaceId;
    final now = _now();
    final from = now.subtract(const Duration(days: kStatWindowDays));
    final since = from.toUtc().toIso8601String();
    final insightsFrom = now.subtract(const Duration(days: 28));
    final day = '${insightsFrom.year.toString().padLeft(4, '0')}-'
        '${insightsFrom.month.toString().padLeft(2, '0')}-'
        '${insightsFrom.day.toString().padLeft(2, '0')}';

    final results = await Future.wait<Object?>([
      _client
          .from('posts')
          .select('status,content_type,source,scheduled_at,published_at')
          .eq('workspace_id', id)
          .or('created_at.gte.$since,scheduled_at.gte.$since,'
              'published_at.gte.$since')
          .limit(1000),
      _client
          .from('facebook_pages')
          .select('id')
          .eq('workspace_id', id)
          .eq('is_active', true),
      _insights(id, day),
    ]);

    final rows = (results[0] as List<dynamic>)
        .map((e) => StatPost.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final pages = results[1] as List<dynamic>;
    final insightRows = results[2] as List<Map<String, dynamic>>;

    return StatsData(
      posts: PostStats.compute(rows, now),
      insights: summarizeInsights(insightRows),
      hasPage: pages.isNotEmpty,
    );
  }

  /// Les mesures Meta sont secondaires : une erreur ne bloque pas l'onglet.
  Future<List<Map<String, dynamic>>> _insights(String id, String day) async {
    try {
      final rows = await _client
          .from('page_insights')
          .select('metric_date,metric_name,metric_value')
          .eq('workspace_id', id)
          .gte('metric_date', day)
          .limit(2000);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } on PostgrestException {
      return const [];
    }
  }
}
