
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent

AUTH_FILE = ROOT / "app/lib/features/auth/presentation/auth_page.dart"
WORKFLOW_FILE = ROOT / ".github/workflows/android.yml"
DEEPLINK_SCRIPT = ROOT / "scripts/configure_android_deeplink.py"

CONFIG_ID = "1678260010520297"
REDIRECT_URI = "socialgrowai://login-callback"

AUTH_CODE = r"""import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLoading = false;

  SupabaseClient get _client => Supabase.instance.client;

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signInWithFacebook() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: 'socialgrowai://login-callback',
        scopes: 'email,public_profile,pages_show_list,pages_read_engagement,pages_manage_posts',
        queryParams: {
          'config_id': '1678260010520297',
        },
      );
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Impossible de lancer la connexion Facebook. Vérifie ta connexion Internet et réessaie.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Container(
                    width: 82,
                    height: 82,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 42,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'SocialGrow AI',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Développe ta présence sur Facebook grâce à l’intelligence artificielle.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _signInWithFacebook,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.facebook),
                    label: Text(
                      _isLoading
                          ? 'Connexion en cours...'
                          : 'Continuer avec Facebook',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'En continuant, tu autorises SocialGrow AI à accéder '
                    'aux Pages Facebook que tu choisis, selon les permissions accordées.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'SocialGrow AI • Développe ta présence en ligne.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
"""


DEEPLINK_CODE = '''#!/usr/bin/env python3
from pathlib import Path
import re
import sys

manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "app/android/app/src/main/AndroidManifest.xml"
)

if not manifest.exists():
    raise SystemExit(f"ERREUR : manifeste introuvable : {manifest}")

content = manifest.read_text(encoding="utf-8")

if "socialgrowai" in content and "login-callback" in content:
    print("Deep link déjà présent.")
    raise SystemExit(0)

pattern = r'(<activity\\b[^>]*android:name="[^"]*MainActivity"[^>]*>)([\\s\\S]*?)(</activity>)'
match = re.search(pattern, content)

if not match:
    raise SystemExit("Activité MainActivity introuvable.")

intent_filter = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="socialgrowai"
                      android:host="login-callback" />
            </intent-filter>
"""

updated = (
    content[:match.start()]
    + match.group(1)
    + match.group(2)
    + intent_filter
    + match.group(3)
    + content[match.end():]
)

manifest.write_text(updated, encoding="utf-8")
print("Deep link Android ajouté avec succès.")
'''


def main():
    if not AUTH_FILE.exists():
        raise SystemExit(f"Fichier introuvable : {AUTH_FILE}")

    if not WORKFLOW_FILE.exists():
        raise SystemExit(f"Workflow introuvable : {WORKFLOW_FILE}")

    old_auth = AUTH_FILE.read_text(encoding="utf-8")
    if "class AuthPage" not in old_auth:
        raise SystemExit("Structure AuthPage inattendue. Aucun changement effectué.")

    workflow = WORKFLOW_FILE.read_text(encoding="utf-8")

    step_marker = "      - name: Installer les dépendances"
    if step_marker not in workflow:
        raise SystemExit("Étape d'installation introuvable dans le workflow.")

    if "Configurer le deep link Android" not in workflow:
        new_step = """      - name: Configurer le deep link Android
        run: python ../scripts/configure_android_deeplink.py android/app/src/main/AndroidManifest.xml

"""
        workflow = workflow.replace(step_marker, new_step + step_marker, 1)

    # Sauvegardes avant modification
    AUTH_FILE.with_suffix(".dart.bak").write_text(
        old_auth, encoding="utf-8"
    )
    WORKFLOW_FILE.with_suffix(".yml.bak").write_text(
        WORKFLOW_FILE.read_text(encoding="utf-8"),
        encoding="utf-8"
    )

    AUTH_FILE.write_text(AUTH_CODE, encoding="utf-8")
    WORKFLOW_FILE.write_text(workflow, encoding="utf-8")
    DEEPLINK_SCRIPT.write_text(DEEPLINK_CODE, encoding="utf-8")

    print("Correctif appliqué.")
    print(f"- Authentification : {AUTH_FILE.relative_to(ROOT)}")
    print(f"- Workflow : {WORKFLOW_FILE.relative_to(ROOT)}")
    print(f"- Script deep link : {DEEPLINK_SCRIPT.relative_to(ROOT)}")
    print("Sauvegardes .bak créées.")
    print()
    print("Configuration Facebook :", CONFIG_ID)
    print("Redirection :", REDIRECT_URI)

if __name__ == "__main__":
    main()
