import 'package:supabase_flutter/supabase_flutter.dart';

import 'publication_settings_repository.dart';
import 'workspace_overview.dart';

abstract class WorkspaceRepository {
  /// Charge le profil, l'espace de travail, le rôle et les Pages connectées.
  ///
  /// Lance [NoWorkspaceException] si aucun espace n'est associé au compte.
  Future<WorkspaceOverview> load();
}

class SupabaseWorkspaceRepository implements WorkspaceRepository {
  SupabaseWorkspaceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<WorkspaceOverview> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const NoWorkspaceException();
    }

    // Espace le plus ancien de l'utilisateur (même règle que les réglages).
    final access =
        await SupabasePublicationSettingsRepository(_client).loadAccess();

    final results = await Future.wait<Object?>([
      _profile(userId),
      _client
          .from('facebook_pages')
          .select('id, page_name')
          .eq('workspace_id', access.workspaceId)
          .eq('is_active', true)
          .order('connected_at', ascending: true),
      _hasStrategy(access.workspaceId),
      _hasAiActivity(access.workspaceId),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final pages = results[1] as List<dynamic>;
    final hasStrategy = results[2] as bool;
    final hasAi = results[3] as bool;

    return WorkspaceOverview(
      workspaceId: access.workspaceId,
      workspaceName: access.workspaceName,
      role: access.role,
      activePageCount: pages.length,
      hasEditorialStrategy: hasStrategy,
      hasAiActivity: hasAi,
      pageName: pages.isEmpty ? null : _text((pages.first as Map)['page_name']),
      displayName: _text(profile?['display_name']),
      avatarUrl: _text(profile?['avatar_url']),
    );
  }

  /// La stratégie est secondaire : une erreur de lecture ne bloque pas l'espace
  /// (l'étape reste simplement « à faire »).
  Future<bool> _hasStrategy(String workspaceId) async {
    try {
      final row = await _client
          .from('editorial_strategy')
          .select('business_description')
          .eq('workspace_id', workspaceId)
          .maybeSingle();
      return _text(row?['business_description']) != null;
    } on PostgrestException {
      return false;
    }
  }

  /// L'assistant est « activé » quand une génération a réellement réussi.
  /// Secondaire : une erreur de lecture laisse simplement l'étape à faire.
  Future<bool> _hasAiActivity(String workspaceId) async {
    try {
      final rows = await _client
          .from('ai_generation_logs')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('success', true)
          .limit(1);
      return rows.isNotEmpty;
    } on PostgrestException {
      return false;
    }
  }

  /// Le profil est secondaire : une erreur de lecture ne bloque pas l'espace.
  Future<Map<String, dynamic>?> _profile(String userId) async {
    try {
      return await _client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', userId)
          .maybeSingle();
    } on PostgrestException {
      return null;
    }
  }

  static String? _text(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
