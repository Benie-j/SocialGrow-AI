
from pathlib import Path
from datetime import datetime

root = Path(__file__).resolve().parent.parent
target = root / "app/lib/core/auth/auth_gate.dart"

if not target.exists():
    raise SystemExit("ERREUR : auth_gate.dart introuvable.")

original = target.read_text(encoding="utf-8")

backup = target.with_name(
    "auth_gate.dart.backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
)
backup.write_text(original, encoding="utf-8")

replacement = r"""import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String _lastEvent = 'Initialisation';
  String _diagnostic = 'Vérification de la session...';
  String? _lastError;

  @override
  void initState() {
    super.initState();

    _session = _client.auth.currentSession;

    _diagnostic = _session == null
        ? 'Aucune session trouvée au démarrage.'
        : 'Session existante récupérée au démarrage.';

    _subscription = _client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;

        setState(() {
          _lastEvent = data.event.name;
          _session = data.session;
          _lastError = null;

          if (data.session != null) {
            _diagnostic = 'Session Supabase reçue.';
          } else {
            _diagnostic = 'Événement reçu sans session.';
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;

        setState(() {
          _lastError = error.runtimeType.toString();
          _diagnostic = 'Erreur pendant l’écoute des événements Auth.';
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Widget _diagnosticPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagnostic de connexion',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('Dernier événement : $_lastEvent'),
            const SizedBox(height: 6),
            Text(
              'Session : ${_session == null ? "ABSENTE" : "PRÉSENTE"}',
            ),
            const SizedBox(height: 6),
            Text(
              'Utilisateur : ${_client.auth.currentUser == null ? "ABSENT" : "PRÉSENT"}',
            ),
            const SizedBox(height: 6),
            Text('État : $_diagnostic'),
            if (_lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Erreur : $_lastError',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const Expanded(child: AuthPage()),
              _diagnosticPanel(),
            ],
          ),
        ),
      );
    }

    return AppShell(
      userEmail: _client.auth.currentUser?.email,
      onSignOut: () async {
        await _client.auth.signOut();
      },
    );
  }
}
"""

target.write_text(replacement, encoding="utf-8")

print("Correctif de diagnostic OAuth appliqué.")
print("Fichier :", target)
print("Sauvegarde :", backup)
print("Aucun jeton ni secret n'a été modifié.")
