
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
            f"{label} : {count} occurrence(s) trouvée(s), "
            "une seule attendue. Aucun changement appliqué."
        )
    return content.replace(old, new, 1)


# 1. Vérifier le dépôt et la branche
if not (ROOT / ".git").exists():
    abort("Lance le script depuis la racine du dépôt.")

branch = git("branch", "--show-current").stdout.strip()

if not branch or branch == "main":
    abort("Travaille sur une branche dédiée, pas directement sur main.")

status = git("status", "--porcelain")

if status.returncode != 0:
    abort("Impossible de vérifier l'état Git.")

if status.stdout.strip():
    abort(
        "Le dépôt contient des modifications non commitées. "
        "Commite-les ou sauvegarde-les avant de continuer."
    )

studio_path = ROOT / STUDIO
edge_path = ROOT / EDGE

if not studio_path.is_file() or not edge_path.is_file():
    abort("Un fichier attendu est introuvable.")

studio = studio_path.read_text(encoding="utf-8")
edge = edge_path.read_text(encoding="utf-8")


# 2. Vérifier les correctifs précédents
required_studio = [
    "_format = 'post'",
    "Future<void> _improve()",
    "'action': 'improve'",
    "'Améliorer avec JUN AI'",
]

required_edge = [
    "Format demandé :",
    'action !== "improve"',
    "MISSION : améliore le texte fourni.",
]

for marker in required_studio:
    if marker not in studio:
        abort(f"Correctif Studio précédent absent : {marker}")

for marker in required_edge:
    if marker not in edge:
        abort(f"Correctif serveur précédent absent : {marker}")

if "Future<void> _generateVariants()" in studio:
    abort("La génération de variantes semble déjà installée.")

if 'action === "variants"' in edge:
    abort("L'action variants semble déjà installée.")


# 3. Ajouter l'état de chargement
studio = replace_once(
    studio,
    "  bool _improving = false;\n",
    "  bool _improving = false;\n  bool _generatingVariants = false;\n",
    "État de chargement des variantes"
)


# 4. Ajouter la méthode de génération et de sélection
old_method = "  Future<String?> _saveDraft({bool quiet = false}) async {"

new_method = r"""  Future<void> _generateVariants() async {
    final original = _editor.text.trim();

    if (original.length < 3) {
      _message('Écris ou génère un texte avant de créer des variantes.');
      return;
    }

    if (_workspaceId == null) return;

    setState(() {
      _generatingVariants = true;
      _error = null;
    });

    try {
      final response = await _client.functions.invoke(
        'groq-generate-content',
        body: {
          'workspace_id': _workspaceId,
          'topic': original,
          'format': _format,
          'action': 'variants',
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
        throw Exception('Aucune variante reçue.');
      }

      final matches = RegExp(
        r'\[VARIANTE ([1-3])\]\s*([\s\S]*?)(?=\[VARIANTE [1-3]\]|$)',
      ).allMatches(content);

      final variants = <int, String>{};

      for (final match in matches) {
        final number = int.tryParse(match.group(1) ?? '');
        final text = match.group(2)?.trim() ?? '';

        if (number != null && text.isNotEmpty) {
          variants[number] = text;
        }
      }

      if (variants.length != 3 ||
          !variants.containsKey(1) ||
          !variants.containsKey(2) ||
          !variants.containsKey(3)) {
        throw Exception(
          'Les trois variantes n’ont pas été reçues dans le format attendu. Réessaie.',
        );
      }

      if (!mounted) return;

      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Choisir une variante'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: variants.entries.map((entry) {
                  return SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(dialogContext, entry.value);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Variante ${entry.key}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.value,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        setState(() {
          _editor.text = selected;
          _currentPostId = null;
        });

        _message('Variante sélectionnée. Tu peux encore la modifier.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _readableError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _generatingVariants = false);
      }
    }
  }

  Future<String?> _saveDraft({bool quiet = false}) async {"""

studio = replace_once(
    studio,
    old_method,
    new_method,
    "Méthode de génération des variantes"
)


# 5. Ajouter le bouton dans l'éditeur
old_button = """                const SizedBox(height: 12),
                Text('Aperçu de la publication', style: Theme.of(context).textTheme.titleSmall),"""

new_button = """                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _generatingVariants ||
                            _generating ||
                            _improving
                        ? null
                        : _generateVariants,
                    icon: _generatingVariants
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compare_arrows),
                    label: Text(
                      _generatingVariants
                          ? 'Création des variantes…'
                          : 'Générer 3 variantes',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Aperçu de la publication', style: Theme.of(context).textTheme.titleSmall),"""

studio = replace_once(
    studio,
    old_button,
    new_button,
    "Bouton de génération des variantes"
)


# 6. Autoriser l'action côté serveur
old_action = """    if (action !== "create" && action !== "improve") {
      return json({ error: "invalid_action", message: "Action non prise en charge." }, 400);
    }"""

new_action = """    if (!["create", "improve", "variants"].includes(action)) {
      return json({ error: "invalid_action", message: "Action non prise en charge." }, 400);
    }"""

edge = replace_once(
    edge,
    old_action,
    new_action,
    "Validation des actions serveur"
)


# 7. Ajouter les instructions de génération des variantes
old_mission = """      action === "improve"
        ? "MISSION : améliore le texte fourni. Corrige les fautes, améliore la clarté, la fluidité, l'accroche et l'impact. Conserve le sujet, les informations vérifiables, l'intention et le sens. N'invente aucun fait. Ne réponds pas par une analyse : renvoie uniquement la version retravaillée."
        : "MISSION : crée un nouveau contenu à partir du brief fourni.","""

new_mission = """      action === "improve"
        ? "MISSION : améliore le texte fourni. Corrige les fautes, améliore la clarté, la fluidité, l'accroche et l'impact. Conserve le sujet, les informations vérifiables, l'intention et le sens. N'invente aucun fait. Ne réponds pas par une analyse : renvoie uniquement la version retravaillée."
        : action === "variants"
          ? "MISSION : crée exactement trois variantes différentes du contenu fourni. Elles doivent conserver le même sujet, les mêmes faits et le même objectif, mais proposer des approches rédactionnelles distinctes. Respecte le format demandé pour chacune. N'invente aucune information. Sépare impérativement les propositions avec les marqueurs exacts [VARIANTE 1], [VARIANTE 2] et [VARIANTE 3]. N'ajoute aucun texte avant le premier marqueur ni après la troisième variante."
          : "MISSION : crée un nouveau contenu à partir du brief fourni.","""

edge = replace_once(
    edge,
    old_mission,
    new_mission,
    "Consignes de génération des variantes"
)


# 8. Adapter la consigne de sortie
old_output = """      `Format demandé : ${format}. ${formatInstructions[format]}`,
      "Respecte la structure du format demandé. N’ajoute pas de commentaire sur ta méthode.","""

new_output = """      `Format demandé : ${format}. ${formatInstructions[format]}`,
      action === "variants"
        ? "Retourne exactement trois propositions avec les marqueurs [VARIANTE 1], [VARIANTE 2] et [VARIANTE 3]."
        : "Respecte la structure du format demandé. N’ajoute pas de commentaire sur ta méthode.","""

edge = replace_once(
    edge,
    old_output,
    new_output,
    "Consigne de sortie des variantes"
)


# 9. Sauvegarder les originaux
backup_dir = ROOT / (
    "backups/studio-ai-03-" + datetime.now().strftime("%Y%m%d-%H%M%S")
)

backup_dir.mkdir(parents=True, exist_ok=False)

shutil.copy2(studio_path, backup_dir / "studio_page.dart")
shutil.copy2(edge_path, backup_dir / "index.ts")


# 10. Appliquer les modifications
try:
    studio_path.write_text(studio, encoding="utf-8")
    edge_path.write_text(edge, encoding="utf-8")
except Exception as exc:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort(f"Écriture interrompue ; restauration effectuée : {exc}")


# 11. Vérification Git
check = git("diff", "--check")

if check.returncode != 0:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort("git diff --check a échoué. Fichiers restaurés.")

print("\nPATCH 03 APPLIQUÉ.")
print("Branche :", branch)
print("Sauvegarde :", backup_dir)
print("\nFichiers modifiés :")
print(" -", STUDIO)
print(" -", EDGE)
print("\nContrôle git diff --check : OK")
print("\nRésumé :")
print(git("diff", "--stat").stdout)
print("\nCompilation, tests et déploiement non effectués.")
