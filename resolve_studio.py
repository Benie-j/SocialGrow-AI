from pathlib import Path
import subprocess
import sys

FILE = Path("app/lib/features/studio/presentation/studio_page.dart")
TARGET = FILE.as_posix()

def get_stage(n):
    r = subprocess.run(
        ["git", "show", f":{n}:{TARGET}"],
        capture_output=True, text=True
    )
    if r.returncode:
        raise RuntimeError(r.stderr)
    return r.stdout

def once(src, old, new, name):
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f"{name}: {n} occurrence(s), 1 attendue.")
    return src.replace(old, new, 1)

try:
    feature = get_stage(2)
    main = get_stage(3)

    # Vérifier les fonctionnalités sources.
    for token in [
        "_generateVariants()",
        "_improve()",
        "studio-generate-image",
        "image_credit",
        "source_urls",
    ]:
        if token not in feature:
            raise RuntimeError(f"Fonctionnalité Studio IA absente : {token}")

    for token in [
        "Future<void> _schedule()",
        "Future<void> _cancelSchedule(",
        "_scheduledLabel(",
    ]:
        if token not in main:
            raise RuntimeError(f"Fonctionnalité main absente : {token}")

    merged = feature

    # Import et états.
    merged = once(
        merged,
        "import '../../../data/publication_settings_repository.dart';",
        "import '../../../data/publication_settings_repository.dart';\n"
        "import '../../../data/schedule.dart';",
        "Import schedule"
    )

    merged = once(
        merged,
        "  bool _publishing = false;\n",
        "  bool _publishing = false;\n"
        "  bool _scheduling = false;\n"
        "  bool _canEdit = false;\n",
        "États schedule"
    )

    merged = once(
        merged,
        "        _canDelete = access.role == 'owner' || access.role == 'admin';\n",
        "        _canDelete = access.role == 'owner' || access.role == 'admin';\n"
        "        _canEdit = _canDelete || access.role == 'editor';\n",
        "Droits d'édition"
    )

    # Récupérer les méthodes de programmation de main.
    a = main.index("  Future<void> _schedule() async {")
    b = main.index("  Future<void> _loadPosts() async {", a)
    methods = main[a:b]

    if "Future<void> _cancelSchedule(" not in methods:
        raise RuntimeError("La méthode d'annulation n'est pas dans le bloc extrait.")
    if "_scheduledLabel(" not in methods:
        raise RuntimeError("La méthode d'affichage de date n'est pas dans le bloc extrait.")

    merged = once(
        merged,
        "  Future<void> _loadPosts() async {",
        methods + "  Future<void> _loadPosts() async {",
        "Insertion des méthodes de programmation"
    )

    # Ajouter le bouton Programmer sans retirer Publier.
    start_marker = """                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _publishing ? null : _saveDraft,"""

    start = merged.find(start_marker)
    if start < 0:
        raise RuntimeError("Rangée des boutons introuvable.")

    end_marker = """                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...["""

    end = merged.find(end_marker, start)
    if end < 0:
        raise RuntimeError("Fin de la rangée des boutons introuvable.")

    end += len("                ),")

    old_row = merged[start:end]

    if "_publish" not in old_row or "_saveDraft" not in old_row:
        raise RuntimeError("La rangée trouvée ne contient pas les boutons attendus.")

    new_row = """                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _publishing || _scheduling
                            ? null
                            : _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Enregistrement…' : 'Brouillon',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _publishing || _scheduling ||
                                _pages.isEmpty || !_canEdit
                            ? null
                            : _schedule,
                        icon: _scheduling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.schedule),
                        label: Text(
                          _scheduling ? 'Programmation…' : 'Programmer',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _publishing || _saving || _scheduling ||
                                _pages.isEmpty
                            ? null
                            : _publish,
                        icon: _publishing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _publishing ? 'Publication…' : 'Publier',
                        ),
                      ),
                    ),
                  ],
                )"""

    merged = merged[:start] + new_row + merged[end:]

    # Afficher la date de programmation dans la bibliothèque.
    old_body = """                  Text(
                    (post['body'] ?? '').toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary),
                  ),
                  if (post['error_message']"""

    new_body = """                  Text(
                    (post['body'] ?? '').toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary),
                  ),
                  if (_scheduledLabel(post) != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 15, color: p.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          _scheduledLabel(post)!,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (post['error_message']"""

    merged = once(merged, old_body, new_body, "Date de programmation")

    # Permettre l'annulation depuis la bibliothèque.
    old_actions = """                      const Spacer(),
                      if (post['status'] == 'draft' && _canDelete)"""

    new_actions = """                      const Spacer(),
                      if (post['status'] == 'scheduled' && _canEdit)
                        TextButton.icon(
                          onPressed: () => _cancelSchedule(post),
                          icon: const Icon(Icons.event_busy_outlined, size: 17),
                          label: const Text('Annuler'),
                        ),
                      if (post['status'] == 'draft' && _canDelete)"""

    merged = once(merged, old_actions, new_actions, "Annulation depuis la bibliothèque")

    # Contrôles structurels avant écriture.
    for marker in ["<<<<<<<", "=======", ">>>>>>>"]:
        if marker in merged:
            raise RuntimeError("Marqueur de conflit restant : " + marker)

    for token in [
        "_generateVariants()",
        "_improve()",
        "studio-generate-image",
        "_currentImageCredit",
        "_currentImageSourceUrl",
        "Future<void> _schedule()",
        "Future<void> _cancelSchedule(",
        "_scheduledLabel(",
        "_canEdit",
        "_publish",
        "Programmer",
    ]:
        if token not in merged:
            raise RuntimeError("Contrôle final absent : " + token)

    current = FILE.read_text()
    if "<<<<<<<" not in current:
        raise RuntimeError("Le fichier local n'est plus dans l'état de conflit attendu.")

    backup = Path("/tmp/studio_page_before_resolution.dart")
    backup.write_text(current)

    FILE.write_text(merged)

    print("CORRECTIF ÉCRIT :", TARGET)
    print("Sauvegarde :", backup)
    print("Nombre de lignes :", len(merged.splitlines()))
    print("Contrôles structurels : OK")

except Exception as exc:
    print("ÉCHEC : aucun correctif écrit.")
    print(str(exc))
    sys.exit(1)


FILE="app/lib/features/studio/presentation/studio_page.dart"

echo "===== MARQUEURS DE CONFLIT ====="
if grep -n -E '^(<<<<<<<|=======|>>>>>>>)' "$FILE"; then
  echo "ERREUR : conflits restants."
  exit 1
fi

echo "===== VÉRIFICATION DU DIFF ====="
git diff --check -- "$FILE" || exit 1

echo "===== FONCTIONS CONSERVÉES ====="
grep -n -E '_generateVariants|_improve|_schedule|_cancelSchedule|_scheduledLabel|studio-generate-image' "$FILE"

echo "===== AJOUT À L'INDEX ====="
git add "$FILE" || exit 1

echo "===== ÉTAT GIT ====="
git status --short

echo "Correctif préparé. Aucun commit ni push."
