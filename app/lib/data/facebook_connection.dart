import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'facebook_oauth.dart';

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// Page Facebook actuellement connectée à l'espace de travail.
class ConnectedFacebookPage {
  const ConnectedFacebookPage({
    required this.id,
    required this.metaPageId,
    required this.name,
    this.category,
    this.pictureUrl,
  });

  /// Ligne `public.facebook_pages` (lecture directe, autorisée par la RLS).
  factory ConnectedFacebookPage.fromRow(Map<String, dynamic> row) {
    return ConnectedFacebookPage(
      id: row['id'] as String,
      metaPageId: row['meta_page_id'] as String,
      name: row['page_name'] as String,
      category: _text(row['category']),
      pictureUrl: _text(row['picture_url']),
    );
  }

  /// Réponse de l'Edge Function `facebook-connect-page`.
  factory ConnectedFacebookPage.fromFunction(Map<String, dynamic> page) {
    return ConnectedFacebookPage(
      id: page['id'] as String,
      metaPageId: page['meta_page_id'] as String,
      name: page['name'] as String,
      category: _text(page['category']),
      pictureUrl: _text(page['picture_url']),
    );
  }

  /// Identifiant interne (base de données).
  final String id;

  /// Identifiant de la Page chez Meta.
  final String metaPageId;
  final String name;
  final String? category;
  final String? pictureUrl;
}

/// Page proposée au choix, issue de Facebook (sans aucun jeton).
class FacebookPageChoice {
  const FacebookPageChoice({
    required this.metaPageId,
    required this.name,
    this.category,
    this.pictureUrl,
  });

  factory FacebookPageChoice.fromMap(Map<String, dynamic> map) {
    return FacebookPageChoice(
      metaPageId: map['id'] as String,
      name: map['name'] as String,
      category: _text(map['category']),
      pictureUrl: _text(map['picture_url']),
    );
  }

  final String metaPageId;
  final String name;
  final String? category;
  final String? pictureUrl;
}

class FacebookConnectResult {
  const FacebookConnectResult({required this.page, required this.longLived});

  final ConnectedFacebookPage page;

  /// Faux : la connexion expirera au bout de quelques heures.
  final bool longLived;
}

/// Erreur lisible par l'utilisateur, avec un code stable côté serveur.
class FacebookConnectionException implements Exception {
  const FacebookConnectionException(this.code, this.message);

  final String code;
  final String message;

  static const _reconnectCodes = {
    'facebook_token_missing',
    'facebook_token_invalid',
    'facebook_permission_missing',
    'unauthenticated',
  };

  /// Une nouvelle connexion Facebook est nécessaire pour continuer.
  bool get needsReauth => _reconnectCodes.contains(code);

  @override
  String toString() => message;
}

/// Convertit n'importe quelle erreur en [FacebookConnectionException].
FacebookConnectionException facebookErrorFrom(Object error) {
  if (error is FacebookConnectionException) return error;

  if (error is FunctionException) {
    Object? details = error.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } catch (_) {
        details = null;
      }
    }
    if (details is Map) {
      final inner = details['error'];
      if (inner is Map) {
        final code = inner['code'];
        final message = inner['message'];
        if (code is String && message is String && message.isNotEmpty) {
          return FacebookConnectionException(code, message);
        }
      }
    }
    if (error.status == 401) {
      return const FacebookConnectionException(
        'unauthenticated',
        'Ta session a expiré. Reconnecte-toi avec Facebook.',
      );
    }
    return const FacebookConnectionException(
      'server_error',
      'Le serveur a refusé la demande. Réessaie dans un instant.',
    );
  }

  return const FacebookConnectionException(
    'network',
    'Impossible de joindre le serveur. Vérifie ta connexion et réessaie.',
  );
}

abstract class FacebookConnectionRepository {
  /// Une session Facebook est disponible pour interroger les Pages.
  bool get hasFacebookSession;

  /// Pages que l'utilisateur gère sur Facebook.
  Future<List<FacebookPageChoice>> listPages(String workspaceId);

  /// Connecte la Page choisie (remplace la Page déjà connectée).
  Future<FacebookConnectResult> connect(String workspaceId, String metaPageId);

  Future<void> disconnect(String workspaceId);

  /// Relance la connexion Facebook dans le navigateur.
  Future<void> reauthenticate();
}

class SupabaseFacebookConnectionRepository
    implements FacebookConnectionRepository {
  SupabaseFacebookConnectionRepository(this._client);

  final SupabaseClient _client;

  String? get _providerToken {
    final token = _client.auth.currentSession?.providerToken;
    if (token == null || token.trim().isEmpty) return null;
    return token;
  }

  @override
  bool get hasFacebookSession => _providerToken != null;

  Future<Map<String, dynamic>> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      throw const FacebookConnectionException(
        'bad_response',
        'Réponse inattendue du serveur.',
      );
    } catch (error) {
      throw facebookErrorFrom(error);
    }
  }

  @override
  Future<List<FacebookPageChoice>> listPages(String workspaceId) async {
    final token = _providerToken;
    if (token == null) {
      throw const FacebookConnectionException(
        'facebook_token_missing',
        'Reconnecte-toi avec Facebook pour afficher tes Pages.',
      );
    }

    final data = await _invoke('facebook-list-pages', {
      'workspace_id': workspaceId,
      'provider_token': token,
    });

    final raw = data['pages'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) FacebookPageChoice.fromMap(item),
    ];
  }

  @override
  Future<FacebookConnectResult> connect(
    String workspaceId,
    String metaPageId,
  ) async {
    final token = _providerToken;
    if (token == null) {
      throw const FacebookConnectionException(
        'facebook_token_missing',
        'Reconnecte-toi avec Facebook pour connecter une Page.',
      );
    }

    final data = await _invoke('facebook-connect-page', {
      'action': 'connect',
      'workspace_id': workspaceId,
      'provider_token': token,
      'meta_page_id': metaPageId,
    });

    final page = data['page'];
    if (page is! Map<String, dynamic>) {
      throw const FacebookConnectionException(
        'bad_response',
        'Réponse inattendue du serveur.',
      );
    }
    return FacebookConnectResult(
      page: ConnectedFacebookPage.fromFunction(page),
      longLived: data['long_lived'] == true,
    );
  }

  @override
  Future<void> disconnect(String workspaceId) async {
    await _invoke('facebook-connect-page', {
      'action': 'disconnect',
      'workspace_id': workspaceId,
    });
  }

  @override
  Future<void> reauthenticate() async {
    await signInWithFacebook(_client);
  }
}
