
#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
import subprocess
import shutil
import sys

ROOT = Path.cwd()

STUDIO = Path("app/lib/features/studio/presentation/studio_page.dart")
EDGE = Path("supabase/functions/groq-generate-content/index.ts")

def run(*args):
    return subprocess.run(
        args, cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

def abort(message):
    print(f"\nERREUR : {message}")
    sys.exit(1)

# 1. Vérifier le dépôt et la branche
if not (ROOT / ".git").exists():
    abort("Lance ce script depuis la racine du dépôt Git.")

branch = run("git", "branch", "--show-current").stdout.strip()
if not branch or branch == "main":
    abort("Crée une branche de travail avant d'appliquer le patch.")

status = run("git", "status", "--porcelain")
if status.returncode != 0:
    abort("Impossible de vérifier l'état Git.")

# Refuser les modifications locales sur les deux fichiers ciblés.
for line in status.stdout.splitlines():
    path = line[3:].strip()
    if path in (str(STUDIO), str(EDGE)):
        abort(f"{path} contient déjà des modifications locales. Sauvegarde-les ou examine-les avant de continuer.")

studio_path = ROOT / STUDIO
edge_path = ROOT / EDGE

if not studio_path.is_file() or not edge_path.is_file():
    abort("Un des deux fichiers attendus est introuvable.")

studio = studio_path.read_text(encoding="utf-8")
edge = edge_path.read_text(encoding="utf-8")

# 2. Vérifier que le patch n'a pas déjà été appliqué
if "_format = 'post'" in studio or "Format demandé :" in edge:
    abort("Le patch semble déjà appliqué. Aucun fichier modifié.")

# 3. Préparer les remplacements exacts
changes = [
    (
        studio,
        "  int _view = 0;\n  String _filter = 'all';",
        "  int _view = 0;\n  String _filter = 'all';\n  String _format = 'post';",
        "État du format dans Studio"
    ),
    (
        studio,
        "body: {'workspace_id': _workspaceId, 'topic': topic},",
        "body: {\n"
        "          'workspace_id': _workspaceId,\n"
        "          'topic': topic,\n"
        "          'format': _format,\n"
        "        },",
        "Transmission du format à l'Edge Function"
    ),
    (
        studio,
        """              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(""",
        """              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _format,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Format de création',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'post',
                    child: Text('Publication classique'),
                  ),
                  DropdownMenuItem(
                    value: 'carousel',
                    child: Text('Carrousel — diapositives'),
                  ),
                  DropdownMenuItem(
                    value: 'video_script',
                    child: Text('Vidéo — scénario et voix off'),
                  ),
                  DropdownMenuItem(
                    value: 'ad',
                    child: Text('Annonce publicitaire'),
                  ),
                ],
                onChanged: _generating
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _format = value);
                        }
                      },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(""",
        "Sélecteur de format dans l'interface"
    ),
]

for original, old, new, label in changes:
    if original.count(old) != 1:
        abort(f"Contexte introuvable ou ambigu : {label}")
    studio = studio.replace(old, new, 1)

# 4. Ajouter les formats et leurs consignes côté serveur
old_validation = """    const topic = String(body.topic ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(workspaceId))"""
new_validation = """    const topic = String(body.topic ?? "").trim();
    const format = String(body.format ?? "post");

    const formatInstructions: Record<string, string> = {
      post: "Rédige une publication classique, claire et engageante.",
      carousel: "Produis un carrousel textuel structuré en diapositives numérotées. Pour chaque diapositive, indique un titre et un texte court. Termine par une conclusion et un appel à l'action si pertinent.",
      video_script: "Produis un scénario vidéo avec scènes numérotées, indications visuelles et texte de voix off. Prévois une accroche, un développement et une conclusion.",
      ad: "Produis une annonce publicitaire avec accroche, proposition de valeur fondée uniquement sur les informations fournies, texte principal et appel à l'action pertinent.",
    };

    if (!Object.prototype.hasOwnProperty.call(formatInstructions, format)) {
      return json({ error: "invalid_format", message: "Format de création non pris en charge." }, 400);
    }

    if (!/^[0-9a-f-]{36}$/i.test(workspaceId))"""
if edge.count(old_validation) != 1:
    abort("Contexte de validation du sujet introuvable ou ambigu.")
edge = edge.replace(old_validation, new_validation, 1)

old_role = '"Tu es le rédacteur social media de JUN AI. Rédige une publication prête à relire, pas une analyse.",'
new_role = '"Tu es le directeur de création social media de JUN AI. Produis un contenu directement exploitable dans le format demandé.",'
if edge.count(old_role) != 1:
    abort("Consigne système d'origine introuvable ou ambiguë.")
edge = edge.replace(old_role, new_role, 1)

old_output = '"Format de sortie : uniquement le texte de la publication, avec paragraphes et hashtags si adaptés.",'
new_output = '`Format demandé : ${format}. ${formatInstructions[format]}`,\n      "Respecte la structure du format demandé. N’ajoute pas de commentaire sur ta méthode.",'
if edge.count(old_output) != 1:
    abort("Consigne de sortie d'origine introuvable ou ambiguë.")
edge = edge.replace(old_output, new_output, 1)

# 5. Sauvegarder les fichiers originaux
backup_dir = ROOT / (
    "backups/studio-ai-" + datetime.now().strftime("%Y%m%d-%H%M%S")
)
backup_dir.mkdir(parents=True, exist_ok=False)

shutil.copy2(studio_path, backup_dir / "studio_page.dart")
shutil.copy2(edge_path, backup_dir / "index.ts")

# 6. Écrire les deux fichiers
try:
    studio_path.write_text(studio, encoding="utf-8")
    edge_path.write_text(edge, encoding="utf-8")
except Exception as exc:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort(f"Écriture interrompue ; restauration effectuée : {exc}")

# 7. Contrôle Git
check = run("git", "diff", "--check")
if check.returncode != 0:
    shutil.copy2(backup_dir / "studio_page.dart", studio_path)
    shutil.copy2(backup_dir / "index.ts", edge_path)
    abort("git diff --check a échoué. Les fichiers originaux ont été restaurés.")

print("\nPATCH APPLIQUÉ.")
print("Branche :", branch)
print("Sauvegarde :", backup_dir)
print("\nFichiers modifiés :")
print(" -", STUDIO)
print(" -", EDGE)
print("\nContrôle git diff --check : OK")
print("\nRésumé du diff :")
print(run("git", "diff", "--stat").stdout)
print("\nLe code n'a pas encore été compilé ni déployé.")
