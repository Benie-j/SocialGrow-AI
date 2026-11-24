import 'package:supabase_flutter/supabase_flutter.dart';

import 'publication_settings.dart';

/// Espace de travail de l’utilisateur connecté et son rôle.
class WorkspaceAccess {
  const WorkspaceAccess({
    required this.workspaceId,
    required this.workspaceName,
    required this.role,
  });

  final String workspaceId;
  final String workspaceName;

  /// owner, admin, editor ou viewer.
  final String role;

  /// Les politiques RLS n’autorisent l’écriture qu’à ces rôles.
  bool get canEdit => role == 'owner' || role == 'admin' || role == 'editor';
}

class NoWorkspaceException implements Exception {
  const NoWorkspaceException();
}

abstract class PublicationSettingsRepository {
  Future<WorkspaceAccess> loadAccess();

  /// Réglages de l’espace, ou valeurs par défaut s’ils n’existent pas encore.
  Future<PublicationSettings> load(String workspaceId);

  Future<PublicationSettings> save(
    String workspaceId,
    PublicationSettings settings,
  );
}

class SupabasePublicationSettingsRepository
    implements PublicationSettingsRepository {
  SupabasePublicationSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<WorkspaceAccess> loadAccess() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const NoWorkspaceException();
    }

    // Si l’utilisateur appartient à plusieurs espaces, on prend le plus ancien.
    final rows = await _client
        .from('workspace_members')
        .select('workspace_id, role, workspaces(name)')
        .eq('user_id', userId)
        .order('joined_at', ascending: true)
        .limit(1);

    if (rows.isEmpty) {
      throw const NoWorkspaceException();
    }

    final row = rows.first;
    final workspace = row['workspaces'];
    final name = workspace is Map ? workspace['name']?.toString() : null;

    return WorkspaceAccess(
      workspaceId: row['workspace_id'] as String,
      workspaceName: name ?? 'Mon espace',
      role: row['role'] as String,
    );
  }

  @override
  Future<PublicationSettings> load(String workspaceId) async {
    final row = await _client
        .from('publication_settings')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();

    return row == null
        ? PublicationSettings()
        : PublicationSettings.fromMap(row);
  }

  @override
  Future<PublicationSettings> save(
    String workspaceId,
    PublicationSettings settings,
  ) async {
    final row = await _client
        .from('publication_settings')
        .upsert(
          {...settings.toMap(), 'workspace_id': workspaceId},
          onConflict: 'workspace_id',
        )
        .select()
        .single();

    return PublicationSettings.fromMap(row);
  }
}

String describeError(Object error) {
  if (error is NoWorkspaceException) {
    return 'Aucun espace de travail n’est associé à ton compte.';
  }
  if (error is PostgrestException) {
    return 'Erreur Supabase : ${error.message}';
  }
  return 'Une erreur est survenue. Vérifie ta connexion et réessaie.';
}
