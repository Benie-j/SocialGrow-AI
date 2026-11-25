import 'package:supabase_flutter/supabase_flutter.dart';

import 'facebook_connection.dart';
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
          .select('id, meta_page_id, page_name, category, picture_url')
          .eq('workspace_id', access.workspaceId)
          .eq('is_active', true)
          .order('connected_at', ascending: false),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final pages = results[1] as List<dynamic>;

    ConnectedFacebookPage? connectedPage;
    if (pages.isNotEmpty && pages.first is Map<String, dynamic>) {
      connectedPage = ConnectedFacebookPage.fromRow(
        pages.first as Map<String, dynamic>,
      );
    }

    return WorkspaceOverview(
      workspaceId: access.workspaceId,
      workspaceName: access.workspaceName,
      role: access.role,
      activePageCount: pages.length,
      displayName: _text(profile?['display_name']),
      avatarUrl: _text(profile?['avatar_url']),
      connectedPage: connectedPage,
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
