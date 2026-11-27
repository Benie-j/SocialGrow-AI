import 'package:supabase_flutter/supabase_flutter.dart';

import 'account.dart';
import 'publication_settings_repository.dart';

abstract class AccountRepository {
  /// Charge le compte, le profil et l'espace de travail.
  ///
  /// Lance [NoWorkspaceException] si aucun espace n'est associé au compte.
  Future<AccountDetails> load();

  /// Enregistre le nom affiché dans `profiles` (vide = retirer le nom).
  Future<void> saveDisplayName(String name);

  /// Renomme l'espace de travail (propriétaire ou administrateur).
  Future<void> renameWorkspace(String workspaceId, String name);
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountDetails> load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const NoWorkspaceException();
    }

    final access =
        await SupabasePublicationSettingsRepository(_client).loadAccess();
    final isAdmin = access.role == 'owner' || access.role == 'admin';

    final results = await Future.wait<Object?>([
      _profile(user.id),
      _client
          .from('workspaces')
          .select('created_at')
          .eq('id', access.workspaceId)
          .maybeSingle(),
      _client
          .from('facebook_pages')
          .select('page_name')
          .eq('workspace_id', access.workspaceId)
          .eq('is_active', true)
          .order('connected_at', ascending: true),
      if (isAdmin)
        _client
            .from('workspace_members')
            .select('user_id')
            .eq('workspace_id', access.workspaceId),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final workspace = results[1] as Map<String, dynamic>?;
    final pages = results[2] as List<dynamic>;
    final members = isAdmin ? results[3] as List<dynamic> : null;

    return AccountDetails(
      email: user.email,
      providers: _providers(user),
      createdAt: _date(user.createdAt),
      lastSignInAt: _date(user.lastSignInAt),
      emailConfirmed: user.emailConfirmedAt != null,
      displayName: _text(profile?['display_name']),
      avatarUrl: _text(profile?['avatar_url']),
      workspaceId: access.workspaceId,
      workspaceName: access.workspaceName,
      role: access.role,
      workspaceCreatedAt: _date(workspace?['created_at']),
      memberCount: members?.length,
      activePageCount: pages.length,
      pageName: pages.isEmpty ? null : _text((pages.first as Map)['page_name']),
    );
  }

  @override
  Future<void> saveDisplayName(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const NoWorkspaceException();
    }
    final value = name.trim();
    await _client.from('profiles').upsert(
      {'id': userId, 'display_name': value.isEmpty ? null : value},
      onConflict: 'id',
    );
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String name) async {
    // Une politique RLS qui refuse la modification ne renvoie aucune erreur :
    // on vérifie donc qu'une ligne a bien été mise à jour.
    final rows = await _client
        .from('workspaces')
        .update({'name': name.trim()})
        .eq('id', workspaceId)
        .select('id');
    if (rows.isEmpty) {
      throw const AccountUpdateException(
        'Tu n’as pas les droits pour renommer cet espace.',
      );
    }
  }

  /// Le profil est secondaire : une erreur de lecture ne bloque pas l'écran.
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

  static List<String> _providers(User user) {
    final raw = user.appMetadata['providers'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    final single = user.appMetadata['provider'];
    return single is String && single.isNotEmpty ? [single] : const [];
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static String? _text(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
