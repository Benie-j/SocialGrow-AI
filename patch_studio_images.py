from pathlib import Path
from datetime import datetime
import subprocess
import shutil
import sys

FILE = Path("app/lib/features/studio/presentation/studio_page.dart")

def fail(message):
    print("ERREUR:", message)
    sys.exit(1)

if not FILE.is_file():
    fail("Fichier Studio introuvable.")

branch = subprocess.check_output(
    ["git", "branch", "--show-current"], text=True
).strip()

if branch != "feature/studio-ai-pro":
    fail(f"Branche incorrecte : {branch}. Attendu : feature/studio-ai-pro.")

if subprocess.check_output(
    ["git", "status", "--porcelain"], text=True
).strip():
    fail("Modifications locales non commitées. Sauvegarde-les avant de continuer.")

original = FILE.read_text(encoding="utf-8")

required = [
    "Future<void> _improve()",
    "Future<void> _generateVariants()",
    "'action': 'variants'",
    "'format': _format",
]

for marker in required:
    if marker not in original:
        fail("Version inattendue : marqueur absent : " + marker)

if "_currentImageUrl" in original:
    fail("Le correctif image semble déjà appliqué.")

content = original

def replace_once(old, new, label):
    global content
    count = content.count(old)
    if count != 1:
        fail(f"{label}: {count} occurrence(s), une attendue.")
    content = content.replace(old, new, 1)

# 1. Etat image
replace_once(
    "  String? _currentPostId;\n",
    """  String? _currentPostId;
  String? _currentImageUrl;
  String? _currentImageCredit;
  String? _currentImageSourceUrl;
""",
    "Etat image"
)

# 2. Chargement des publications
content = content.replace(
    "content_type,created_at,scheduled_at",
    "content_type,image_url,image_credit,source_urls,created_at,scheduled_at"
)

if content.count("image_url,image_credit,source_urls") != 2:
    fail("Les deux requêtes de chargement des publications ne sont pas reconnues.")

# 3. Génération du texte puis de l'image
replace_once(
"""      if (!mounted) return;
      setState(() {
        _editor.text = content.trim();
        _currentPostId = null;
      });""",
"""      if (!mounted) return;
      setState(() {
        _editor.text = content.trim();
        _currentPostId = null;
        _currentImageUrl = null;
        _currentImageCredit = null;
        _currentImageSourceUrl = null;
      });

      // La génération du texte reste acquise même si l'image échoue.
      try {
        final imageResponse = await _client.functions.invoke(
          'studio-generate-image',
          body: {
            'workspace_id': _workspaceId,
            'topic': topic,
            'content': content.trim(),
          },
        );

        final imageData = imageResponse.data;

        if (imageData is! Map || imageData['error'] != null) {
          throw Exception(
            imageData is Map
                ? (imageData['message'] ?? imageData['error'])
                : 'Réponse image invalide.',
          );
        }

        final imageUrl = imageData['image_url'];
        if (imageUrl is! String || !imageUrl.startsWith('https://')) {
          throw Exception('URL de l’image invalide.');
        }

        if (!mounted) return;
        setState(() {
          _currentImageUrl = imageUrl;
          _currentImageCredit = imageData['image_credit']?.toString();
          _currentImageSourceUrl = imageData['source_url']?.toString();
        });

        _message(
          imageData['mode'] == 'generated'
              ? 'Image générée par JUN AI.'
              : 'Image libre de droits récupérée.',
        );
      } catch (imageError) {
        if (mounted) {
          _message(
            'Texte créé, mais image indisponible : '
            '${_readableError(imageError)}',
          );
        }
      }""",
    "Génération image"
)

# 4. Enregistrement image dans posts
image_fields = """'content_type': _currentImageUrl == null ? 'text' : 'image',
          'image_url': _currentImageUrl,
          'image_credit': _currentImageCredit,
          'source_urls': [
            if (_currentImageSourceUrl != null) _currentImageSourceUrl,
          ],"""

if content.count("'content_type': 'text',") != 2:
    fail("Les deux écritures de posts ne correspondent pas à la version attendue.")

content = content.replace("'content_type': 'text',", image_fields)

# 5. Restaurer image à l'ouverture d'un brouillon
replace_once(
"""      _editor.text = (post['body'] ?? '').toString();
      final pageId = post['facebook_page_id']?.toString();""",
"""      _editor.text = (post['body'] ?? '').toString();

      final image = post['image_url']?.toString();
      _currentImageUrl = post['content_type'] == 'image' &&
              image != null &&
              image.startsWith('https://')
          ? image
          : null;

      _currentImageCredit = post['image_credit']?.toString();

      final sources = post['source_urls'];
      _currentImageSourceUrl =
          sources is List && sources.isNotEmpty
              ? sources.first.toString()
              : null;

      final pageId = post['facebook_page_id']?.toString();""",
    "Restauration image"
)

# 6. Nettoyage lors de suppression
replace_once(
"""          _currentPostId = null;
          _editor.clear();
          _idea.clear();""",
"""          _currentPostId = null;
          _currentImageUrl = null;
          _currentImageCredit = null;
          _currentImageSourceUrl = null;
          _editor.clear();
          _idea.clear();""",
    "Nettoyage image"
)

# 7. Aperçu dans l'éditeur
replace_once(
"""                TextField(
                  controller: _editor,""",
"""                if (_currentImageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _currentImageUrl!,
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 70,
                        child: Center(
                          child: Text('Image indisponible.'),
                        ),
                      ),
                    ),
                  ),
                  if (_currentImageCredit != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _currentImageCredit!,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _currentImageUrl = null;
                        _currentImageCredit = null;
                        _currentImageSourceUrl = null;
                      }),
                      icon: const Icon(Icons.hide_image_outlined),
                      label: const Text('Retirer l’image'),
                    ),
                  ),
                ],
                TextField(
                  controller: _editor,""",
    "Aperçu image"
)

# Sauvegarde avant écriture
backup_dir = Path("backups") / (
    "studio-images-" + datetime.now().strftime("%Y%m%d-%H%M%S")
)
backup_dir.mkdir(parents=True, exist_ok=False)
shutil.copy2(FILE, backup_dir / FILE.name)

try:
    FILE.write_text(content, encoding="utf-8")

    subprocess.run(
        ["git", "diff", "--check", "--", str(FILE)],
        check=True
    )

    print("CORRECTIF APPLIQUE.")
    print("Sauvegarde :", backup_dir)
    print("Fichier :", FILE)
    print("Aucun commit automatique.")

except Exception as error:
    shutil.copy2(backup_dir / FILE.name, FILE)
    fail("Echec, fichier restauré : " + str(error))
