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
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final pages = results[1] as List<dynamic>;

    return WorkspaceOverview(
      workspaceId: access.workspaceId,
      workspaceName: access.workspaceName,
      role: access.role,
      activePageCount: pages.length,
      pageName: pages.isEmpty ? null : _text((pages.first as Map)['page_name']),
      displayName: _text(profile?['display_name']),
      avatarUrl: _text(profile?['avatar_url']),
    );
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
