import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/facebook_connection.dart';
import '../../data/workspace_repository.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../navigation/app_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final SupabaseClient _client = Supabase.instance.client;

  Session? _session;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();

    _session = _client.auth.currentSession;

    _subscription = _client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;
        setState(() => _session = data.session);
      },
      // En cas d'erreur d'écoute, l'état courant est conservé.
      onError: (Object error, StackTrace stackTrace) {},
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Valeur texte non vide des métadonnées du compte (nom, photo…).
  String? _metadata(String key) {
    final value = _client.auth.currentUser?.userMetadata?[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return const AuthPage();
    }

    return AppShell(
      workspaceRepository: SupabaseWorkspaceRepository(_client),
      facebookRepository: SupabaseFacebookConnectionRepository(_client),
      userEmail: _client.auth.currentUser?.email,
      userName: _metadata('full_name') ?? _metadata('name'),
      userAvatarUrl: _metadata('avatar_url') ?? _metadata('picture'),
      onSignOut: () async {
        await _client.auth.signOut();
      },
    );
  }
}
