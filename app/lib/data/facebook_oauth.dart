import 'package:supabase_flutter/supabase_flutter.dart';

/// Retour dans l'application après l'autorisation Facebook (deep link Android).
const String facebookRedirectUrl = 'socialgrowai://login-callback';

/// Configuration « Facebook Login for Business » (autorisations demandées).
const String facebookLoginConfigId = '1678260010520297';

/// Lance la connexion Facebook (navigateur). Sert à la première connexion
/// et à la reconnexion quand la session Facebook a expiré.
Future<bool> signInWithFacebook(SupabaseClient client) {
  return client.auth.signInWithOAuth(
    OAuthProvider.facebook,
    redirectTo: facebookRedirectUrl,
    queryParams: {'config_id': facebookLoginConfigId},
  );
}
