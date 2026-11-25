import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Identifiant de configuration « Facebook Login for Business » (le même que
/// celui de l'écran de connexion).
const String kFacebookConfigId = '1678260010520297';

/// Page Facebook proposée par Meta, pas encore forcément connectée.
class FacebookPage {
  const FacebookPage({
    required this.metaPageId,
    required this.name,
    this.category,
    this.pictureUrl,
  });

  factory FacebookPage.fromMap(Map<String, dynamic> map) => FacebookPage(
        metaPageId: map['id'].toString(),
        name: _text(map['name']) ?? 'Page sans nom',
        category: _text(map['category']),
        pictureUrl: _text(map['picture_url']),
      );

  final String metaPageId;
  final String name;
  final String? category;
  final String? pictureUrl;
}

/// Page Facebook connectée à l'espace de travail (ligne de facebook_pages).
class ConnectedFacebookPage {
  const ConnectedFacebookPage({
    required this.id,
    required this.metaPageId,
    required this.name,
    this.category,
    this.pictureUrl,
  });

  factory ConnectedFacebookPage.fromRow(Map<String, dynamic> row) =>
      ConnectedFacebookPage(
        id: row['id'].toString(),
        metaPageId: row['meta_page_id'].toString(),
        name: _text(row['page_name']) ?? 'Page sans nom',
        category: _text(row['category']),
        pictureUrl: _text(row['picture_url']),
      );

  /// Identifiant interne (uuid) de la Page dans la base.
  final String id;
  final String metaPageId;
  final String name;
  final String? category;
  final String? pictureUrl;
}

/// Erreur à afficher telle quelle à l'utilisateur.
class FacebookConnectionException implements Exception {
  const FacebookConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FacebookConnectionRepository {
  /// Vrai si la session contient une autorisation Facebook utilisable pour
  /// lister les Pages (elle n'est disponible qu'après une connexion Facebook).
  bool get hasFacebookAuthorization;

  /// Émet à chaque changement de session (retour de la connexion Facebook).
  Stream<void> get sessionChanges;

  /// Pages actives de l'espace de travail.
  Future<List<ConnectedFacebookPage>> loadConnected(String workspaceId);

  /// Pages que l'utilisateur gère chez Meta (Edge Function facebook-list-pages).
  Future<List<FacebookPage>> listAvailablePages();

  /// Connecte une Page (Edge Function facebook-connect-page). Le serveur
  /// revérifie auprès de Meta que l'utilisateur gère bien cette Page. Une seule
  /// Page est active par espace : connecter celle-ci remplace la précédente.
  Future<ConnectedFacebookPage> connectPage({
    required String workspaceId,
    required FacebookPage page,
  });

  /// Déconnecte la Page active de l'espace (Edge Function
  /// facebook-disconnect-page : désactivation et suppression de son jeton).
  Future<void> disconnect(String workspaceId);

  /// Relance la connexion Facebook pour obtenir une nouvelle autorisation.
  Future<void> reauthorize();
}

class SupabaseFacebookConnectionRepository
    implements FacebookConnectionRepository {
  SupabaseFacebookConnectionRepository(this._client);

  final SupabaseClient _client;

  String? get _providerToken {
    final token = _client.auth.currentSession?.providerToken;
    return token != null && token.isNotEmpty ? token : null;
  }

  @override
  bool get hasFacebookAuthorization => _providerToken != null;

  @override
  Stream<void> get sessionChanges =>
      _client.auth.onAuthStateChange.map((_) {});

  @override
  Future<List<ConnectedFacebookPage>> loadConnected(String workspaceId) async {
    final rows = await _client
        .from('facebook_pages')
        .select('id, meta_page_id, page_name, category, picture_url')
        .eq('workspace_id', workspaceId)
        .eq('is_active', true)
        .order('connected_at', ascending: true);

    return [
      for (final row in rows) ConnectedFacebookPage.fromRow(row),
    ];
  }

  @override
  Future<List<FacebookPage>> listAvailablePages() async {
    final data = await _invoke('facebook-list-pages', {
      'provider_token': _requireToken(),
    });
    final pages = data['pages'];
    if (pages is! List) {
      throw const FacebookConnectionException(
        'Réponse inattendue du serveur.',
      );
    }
    final result = [
      for (final page in pages)
        if (page is Map<String, dynamic>) FacebookPage.fromMap(page),
    ];
    if (result.isEmpty) {
      final message = _emptyListMessage(data['diagnostic']);
      if (message != null) throw FacebookConnectionException(message);
    }
    return result;
  }

  @override
  Future<ConnectedFacebookPage> connectPage({
    required String workspaceId,
    required FacebookPage page,
  }) async {
    final data = await _invoke('facebook-connect-page', {
      'workspace_id': workspaceId,
      'meta_page_id': page.metaPageId,
      'provider_token': _requireToken(),
    });
    final created = data['page'];
    if (created is! Map<String, dynamic>) {
      throw const FacebookConnectionException(
        'Réponse inattendue du serveur.',
      );
    }
    return ConnectedFacebookPage(
      id: created['id'].toString(),
      metaPageId: page.metaPageId,
      name: page.name,
      category: page.category,
      pictureUrl: page.pictureUrl,
    );
  }

  @override
  Future<void> disconnect(String workspaceId) async {
    await _invoke('facebook-disconnect-page', {'workspace_id': workspaceId});
  }

  @override
  Future<void> reauthorize() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'socialgrowai://login-callback',
      queryParams: {'config_id': kFacebookConfigId},
    );
  }

  String _requireToken() {
    final token = _providerToken;
    if (token == null) {
      throw const FacebookConnectionException(
        'Autorisation Facebook manquante. Autorise de nouveau l’accès à '
        'tes Pages.',
      );
    }
    return token;
  }

  Future<Map<String, dynamic>> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['message']?.toString() : null;
      throw FacebookConnectionException(
        message ?? 'Le serveur a refusé la demande (code ${error.status}).',
      );
    }
    throw const FacebookConnectionException('Réponse inattendue du serveur.');
  }
}

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// Explique pourquoi Meta ne renvoie aucune Page, d'après le diagnostic du
/// serveur. Renvoie null si le serveur n'en donne pas (ancienne version).
String? _emptyListMessage(Object? diagnostic) {
  if (diagnostic is! Map) return null;
  final reason = diagnostic['reason'];
  final granted = diagnostic['granted_permissions'];
  final received = granted is List && granted.isNotEmpty
      ? ' Permissions reçues : ${granted.join(', ')}.'
      : '';
  switch (reason) {
    case 'missing_pages_permission':
      return 'Facebook n’a pas accordé la permission de voir tes Pages '
          '(pages_show_list).$received Autorise de nouveau l’accès et '
          'accepte-la.';
    case 'no_publish_rights':
      return 'Facebook renvoie des Pages, mais aucune où tu peux publier. '
          'Il te faut un accès complet ou la tâche « Créer du contenu » '
          'sur la Page.$received';
    case 'no_pages_shared':
      return 'La permission est accordée, mais aucune Page n’a été partagée '
          'avec l’app. Autorise de nouveau l’accès et coche ta Page dans la '
          'fenêtre Facebook.$received';
  }
  return null;
}
