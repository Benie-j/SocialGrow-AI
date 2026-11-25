import 'package:supabase_flutter/supabase_flutter.dart';

import 'agenda.dart';
import 'publication_settings.dart';
import 'publication_settings_repository.dart';

/// Ce qu'il faut savoir de l'espace pour afficher l'agenda.
class AgendaContext {
  const AgendaContext({
    required this.workspaceId,
    required this.role,
    required this.settings,
    this.pageNames = const {},
  });

  final String workspaceId;

  /// owner, admin, editor ou viewer.
  final String role;
  final PublicationSettings settings;

  /// Noms des Pages Facebook actives, par identifiant interne.
  final Map<String, String> pageNames;

  /// Peut reprogrammer (mêmes droits que la modification des publications).
  bool get canEdit =>
      role == 'owner' || role == 'admin' || role == 'editor';
}

abstract class AgendaRepository {
  Future<AgendaContext> loadContext();

  /// Publications datées dans [from, to[ (planifiées ou déjà publiées).
  Future<List<AgendaPost>> loadRange(
    String workspaceId,
    DateTime from,
    DateTime to,
  );

  Future<void> reschedule({
    required String workspaceId,
    required String postId,
    required DateTime at,
  });
}

class SupabaseAgendaRepository implements AgendaRepository {
  SupabaseAgendaRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      'id,title,body,status,content_type,scheduled_at,published_at,'
      'error_message,facebook_page_id';

  @override
  Future<AgendaContext> loadContext() async {
    final settingsRepository = SupabasePublicationSettingsRepository(_client);
    final access = await settingsRepository.loadAccess();
    final settings = await settingsRepository.load(access.workspaceId);

    final pages = await _client
        .from('facebook_pages')
        .select('id,page_name')
        .eq('workspace_id', access.workspaceId)
        .eq('is_active', true);

    return AgendaContext(
      workspaceId: access.workspaceId,
      role: access.role,
      settings: settings,
      pageNames: {
        for (final row in pages)
          row['id'].toString(): (row['page_name'] ?? '').toString(),
      },
    );
  }

  @override
  Future<List<AgendaPost>> loadRange(
    String workspaceId,
    DateTime from,
    DateTime to,
  ) async {
    final start = from.toUtc().toIso8601String();
    final end = to.toUtc().toIso8601String();

    final results = await Future.wait([
      _client
          .from('posts')
          .select(_columns)
          .eq('workspace_id', workspaceId)
          .gte('scheduled_at', start)
          .lt('scheduled_at', end),
      _client
          .from('posts')
          .select(_columns)
          .eq('workspace_id', workspaceId)
          .gte('published_at', start)
          .lt('published_at', end),
    ]);

    final byId = <String, AgendaPost>{};
    for (final rows in results) {
      for (final row in rows) {
        final post = AgendaPost.fromMap(Map<String, dynamic>.from(row));
        final when = post.when;
        if (when == null || when.isBefore(from) || !when.isBefore(to)) continue;
        byId[post.id] = post;
      }
    }

    final posts = byId.values.toList()
      ..sort((a, b) => a.when!.compareTo(b.when!));
    return posts;
  }

  @override
  Future<void> reschedule({
    required String workspaceId,
    required String postId,
    required DateTime at,
  }) async {
    // select() renvoie les lignes modifiées : vide = droits insuffisants (RLS).
    final rows = await _client
        .from('posts')
        .update({'scheduled_at': at.toUtc().toIso8601String()})
        .eq('id', postId)
        .eq('workspace_id', workspaceId)
        .select('id');

    if (rows.isEmpty) {
      throw const AgendaPermissionException();
    }
  }
}
