
#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
import subprocess
import shutil
import sys

ROOT = Path.cwd()

STUDIO = Path("app/lib/features/studio/presentation/studio_page.dart")
EDGE = Path("supabase/functions/groq-generate-content/index.ts")


def abort(message):
    print(f"\nERREUR : {message}")
    sys.exit(1)


def git(*args):
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def replace_once(content, old, new, label):
    count = content.count(old)
    if count != 1:
        abort(
            f"{label} : contexte trouvé {count} fois "
            "(une seule occurrence attendue). Aucun changement appliqué."
        )
    return content.replace(old, new, 1)


# 1. Vérifications Git
if not (ROOT / ".git").exists():
    abort("Lance le script depuis la racine du dépôt.")

branch = git("branch", "--show-current").stdout.strip()

if not branch or branch == "main":
    abort("Utilise une branche de travail, pas main.")

status = git("status", "--porcelain")
if status.returncode != 0:
    abort("Impossible de vérifier Git.")

if status.stdout.strip():
    abort(
        "Le dépôt contient des modifications non commitées. "
        "Commite-les ou sauvegarde-les avant de continuer."
    )

studio_path = ROOT / STUDIO
edge_path = ROOT / EDGE

if not studio_path.is_file() or not edge_path.is_file():
    abort("Fichier Studio ou Edge Function introuvable.")

studio = studio_path.read_text(encoding="utf-8")
edge = edge_path.read_text(encoding="utf-8")

# 2. Vérifier la présence du premier patch
if "_format = 'post'" not in studio:
    abort("Le premier patch du Studio AI n'a pas été détecté.")

if "Format demandé :" not in edge:
    abort("Le premier patch de l'Edge Function n'a pas été détecté.")

if "Future<void> _improve()" in studio:
    abort("La fonction d'amélioration existe déjà.")

# 3. Ajouter l'état de chargement
studio = replace_once(
    studio,
    "  bool _generating = false;\n",
    "  bool _generating = false;\n  bool _improving = false;\n",
    "État de chargement de l'amélioration"
)

# 4. Ajouter la méthode _improve
old_method = """  Future<String?> _saveDraft({bool quiet = false}) async {"""

new_method = r"""  Future<void> _improve() async {
    final original = _editor.text.trim();

    if (original.length < 3) {
      _message('Écris ou génère un texte avant de demander son amélioration.');
      return;
    }

    if (_workspaceId == null) return;

    setState(() {
      _improving = true;
      _error = null;
    });

    try {
      final response = await _client.functions.invoke(
        'groq-generate-content',
        body: {
          'workspace_id': _workspaceId,
          'topic': original,
          'format': _format,
          'action': 'improve',
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw Exception('Réponse du générateur invalide.');
      }

      if (data['error'] != null) {
        throw Exception(data['message'] ?? data['error']);
      }

      final content = data['content'];

      if (content is! String || content.trim().isEmpty) {
        throw Exception('L’IA n’a renvoyé aucun texte.');
      }

      if (!mounted) return;

      setState(() {
        _editor.text = content.trim();
        _currentPostId = null;
      });

      _message('Texte amélioré. Vérifie-le avant de publier.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = _readableError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _improving = false);
      }
    }
  }

  Future<String?> _saveDraft({bool quiet = false}) async {"""

studio = replace_once(
    studio,
    old_method,
    new_method,
    "Insertion de la méthode _improve"
)

# 5. Ajouter le bouton dans l'éditeur
old_editor = """                const SizedBox(height: 12),
                Text('Aperçu de la publication', style: Theme.of(context).textTheme.titleSmall),"""

new_editor = """                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _improving || _generating ? null : _improve,
                    icon: _improving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: Text(
                      _improving
                          ? 'Amélioration en cours…'
                          : 'Améliorer avec JUN AI',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Aperçu de la publication', style: Theme.of(context).textTheme.titleSmall),"""

studio = replace_once(
    studio,
    old_editor,
    new_editor,
    "Bouton d'amélioration dans l'éditeur"
)

# 6. Ajouter l'action côté serveur
old_topic = """    const topic = String(body.topic ?? "").trim();
    const format = String(body.format ?? "post");"""

new_topic = """    const topic = String(body.topic ?? "").trim();
    const format = String(body.format ?? "post");
    const action = String(body.action ?? "create");

    if (action !== "create" && action !== "improve") {
      return json({ error: "invalid_action", message: "Action non prise en charge." }, 400);
    }"""

edge = replace_once(
    edge,
    old_topic,
    new_topic,
    "Lecture et validation de l'action"
)

# 7. Adapter le prompt à l'action
old_prompt = """      "Tu es le directeur de création social media de JUN AI. Produis un contenu directement exploitable dans le format demandé.",
      "Réponds dans la langue demandée. N'invente aucun chiffre, témoignage, résultat ou caractéristique produit.","""

new_prompt = """      "Tu es le directeur de création social media de JUN AI. Produis un contenu directement exploitable dans le format demandé.",
      action === "improve"
        ? "MISSION : améliore le texte fourni. Corrige les fautes, améliore la clarté, la fluidité, l'accroche et l'impact. Conserve le sujet, les informations vérifiables, l'intention et le sens. N'invente aucun fait. Ne réponds pas par une analyse : renvoie uniquement la version retravaillée."
        : "MISSION : crée un nouveau contenu à partir du brief fourni.",
      "Réponds dans la langue demandée. N'invente aucun chiffre, témoignage, résultat ou caractéristique produit.","""

edge = replace_once(
    edge,
    old_prompt,
    new_prompt,
    "Consignes du prompt selon l'action"
)

# 8. Sauvegarder avant écriture
backup_dir = ROOT / (
    "backups/studio-ai-02-" + datetime.now().strftime("%Y%m%d-%H%M%S")
)
backup_dir.mkdir(parents=True, exist_ok=False)

shutil.copy2(studio_path, backup_dir / "studio_page.dart")
shutil.copy2(edge_path, backup_dir / "index.ts")

# 9. Écrire les deux fichiers
try:
    studio_path.write_text(studio, encoding="utf-8")
    edge_path.write_text(edge, encoding="utf-8")
except Exception as exc:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort(f"Écriture interrompue ; restauration effectuée : {exc}")

# 10. Contrôle de cohérence
check = git("diff", "--check")

if check.returncode != 0:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort("git diff --check a échoué. Fichiers restaurés.")

print("\nPATCH 02 APPLIQUÉ.")
print("Branche :", branch)
print("Sauvegarde :", backup_dir)
print("\nFichiers modifiés :")
print(" -", STUDIO)
print(" -", EDGE)
print("\nContrôle git diff --check : OK")
print("\nRésumé :")
print(git("diff", "--stat").stdout)
print("\nCompilation et tests non exécutés.")
print("Aucun déploiement Supabase effectué.")
