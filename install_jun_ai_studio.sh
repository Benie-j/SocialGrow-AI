
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$HOME/SocialGrow-AI"
BACKUP="$HOME/SocialGrow-AI-backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
SAVE="$BACKUP/jun-ai-studio-$STAMP"

die() { echo "ERREUR: $*" >&2; exit 1; }

cd "$ROOT" || die "Dépôt introuvable: $ROOT"

[ "$(git branch --show-current)" = "main" ] || die "Tu dois être sur main."
git diff --check || die "Le dépôt contient déjà des erreurs de diff."
git rev-parse --verify HEAD >/dev/null || die "Dépôt Git invalide."

NAV="app/lib/core/navigation/app_shell.dart"
STUDIO="app/lib/features/studio/presentation/studio_page.dart"

[ -f "$NAV" ] || die "Fichier de navigation introuvable."
[ ! -e "$STUDIO" ] || die "Le fichier Studio existe déjà. Arrêt pour préserver son contenu."

grep -Fq "const FeaturePreviewPage(" "$NAV" || die "Écran de prévisualisation introuvable."
grep -Fq "title: 'Studio IA'" "$NAV" || die "Bloc Studio attendu introuvable."
grep -Fq "description: 'Ton atelier de création pour ta Page Facebook.'" "$NAV" || die "Description Studio différente de la version attendue."

mkdir -p "$SAVE"
cp -a "$NAV" "$SAVE/app_shell.dart"
echo "Sauvegarde: $SAVE"

mkdir -p "$(dirname "$STUDIO")"

cat > "$STUDIO" <<'DART'
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../data/publication_settings_repository.dart';

class StudioPage extends StatefulWidget {
   const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _topic = TextEditingController();
  final _content = TextEditingController();

  final _settings = SupabasePublicationSettingsRepository(
    Supabase.instance.client,
  );

  String _platform = 'Facebook';
  String _objective = 'engagement';
  String _tone = 'professionnel';

  String? _workspaceId;
  bool _loading = true;
  bool _generating = false;
  bool _saving = false;
  String? _error;
  String? _model;
  List<Map<String, dynamic>> _drafts = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topic.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final access = await _settings.loadAccess();
      final rows = await _client
          .from('posts')
          .select('id,title,body,created_at')
          .eq('workspace_id', access.workspaceId)
          .eq('status', 'draft')
          .order('created_at', ascending: false)
          .limit(30);

      if (!mounted) return;

      setState(() {
        _workspaceId = access.workspaceId;
        _drafts = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    final topic = _topic.text.trim();

    if (topic.length < 3) {
      _message('Décris d’abord le sujet de ta publication.');
      return;
    }

    if (_workspaceId == null) return;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final response = await _client.functions.invoke(
        'groq-generate-content',
        body: {
          'workspace_id': _workspaceId,
          'topic': topic,
          'platform': _platform,
          'objective': _objective,
          'tone': _tone,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Réponse du serveur invalide.');
      }

      if (data['error'] != null) {
        throw Exception(data['message'] ?? data['error']);
      }

      final generated = data['content'];
      if (generated is! String || generated.trim().isEmpty) {
        throw Exception('Aucun texte généré.');
      }

      if (!mounted) return;

      setState(() {
        _content.text = generated.trim();
        _model = data['model']?.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveDraft() async {
    final body = _content.text.trim();
    final user = _client.auth.currentUser;

    if (body.isEmpty || _workspaceId == null || user == null) return;

    setState(() => _saving = true);

    try {
      await _client.from('posts').insert({
        'workspace_id': _workspaceId,
        'created_by': user.id,
        'title': _topic.text.trim(),
        'body': body,
        'content_type': 'text',
        'status': 'draft',
        'source': 'ai',
      });

      if (!mounted) return;
      _message('Brouillon enregistré.');
      await _load();
    } catch (e) {
      if (mounted) _message('Enregistrement impossible : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteDraft(String id) async {
    try {
      await _client
          .from('posts')
          .delete()
          .eq('id', id)
          .eq('workspace_id', _workspaceId!);
      await _load();
    } catch (e) {
      if (mounted) _message('Suppression impossible : $e');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Widget _section(String title, Widget child) {
    final p = SgPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _choice(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_workspaceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              const Text('Impossible de charger ton espace de travail.'),
              if (_error != null) Text(_error!),
              TextButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        Text(
          'Studio IA',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Transforme tes idées en publications prêtes à être retravaillées.',
          style: TextStyle(color: p.textSecondary),
        ),
        const SizedBox(height: 22),
        _section(
          '1. Ta publication',
          Column(
            children: [
              TextField(
                controller: _topic,
                minLines: 3,
                maxLines: 6,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Quel sujet veux-tu aborder ?',
                  hintText: 'Décris ton produit, ton idée ou ton actualité…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              _choice(
                'Réseau social',
                _platform,
                ['Facebook', 'Instagram', 'LinkedIn', 'TikTok'],
                (v) => setState(() => _platform = v!),
              ),
              const SizedBox(height: 12),
              _choice(
                'Objectif',
                _objective,
                ['engagement', 'notoriete', 'ventes', 'abonnes', 'education'],
                (v) => setState(() => _objective = v!),
              ),
              const SizedBox(height: 12),
              _choice(
                'Ton',
                _tone,
                [
                  'professionnel',
                  'commercial',
                  'chaleureux',
                  'humoristique',
                  'informatif',
                  'inspirant',
                ],
                (v) => setState(() => _tone = v!),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _generating
                        ? 'Génération en cours…'
                        : 'Générer avec l’IA',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: p.accentWarm)),
        ],
        if (_content.text.isNotEmpty) ...[
          const SizedBox(height: 18),
          _section(
            '2. Ta publication générée',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_model != null)
                  Text(
                    'Modèle : $_model',
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _content,
                  minLines: 8,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _content.text),
                          );
                          _message('Texte copié.');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copier'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Mes brouillons', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_drafts.isEmpty)
          Text(
            'Aucun brouillon enregistré pour le moment.',
            style: TextStyle(color: p.textSecondary),
          ),
        for (final draft in _drafts)
          Card(
            color: p.glass,
            child: ListTile(
              title: Text(
                (draft['title'] ?? 'Sans titre').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                (draft['body'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                setState(() {
                  _topic.text = (draft['title'] ?? '').toString();
                  _content.text = (draft['body'] ?? '').toString();
                });
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteDraft(draft['id'].toString()),
              ),
            ),
          ),
      ],
    );
  }
}
DART

python - "$NAV" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_import = "import '../../features/preview/presentation/feature_preview_page.dart';"
new_import = old_import + "\nimport '../../features/studio/presentation/studio_page.dart';"

if new_import not in text:
    if text.count(old_import) != 1:
        raise SystemExit("Import preview absent ou ambigu. Aucune modification navigation.")
    text = text.replace(old_import, new_import, 1)

start_marker = "      const FeaturePreviewPage(\n        title: 'Studio IA',"
start = text.find(start_marker)
if start < 0:
    raise SystemExit("Début du bloc Studio introuvable.")

# Repère la fin du widget grâce à l'indentation et au prochain écran Agenda.
end_marker = "      const FeaturePreviewPage(\n        title: 'Agenda',"
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("Fin du bloc Studio introuvable.")

replacement = "      const StudioPage(),\n"
text = text[:start] + replacement + text[end:]
path.write_text(text)
PY

echo
echo "Fichiers installés. Vérification du diff..."
git diff --check || die "Diff invalide. Restaure depuis $SAVE"
git status --short
git diff --stat

if command -v dart >/dev/null 2>&1; then
  dart format "$STUDIO" "$NAV"
else
  echo "Dart absent : formatage non exécuté."
fi

if command -v flutter >/dev/null 2>&1; then
  (
    cd app
    flutter analyze
  ) || die "flutter analyze a échoué. Sauvegarde disponible: $SAVE"
else
  echo "Flutter absent : analyse non exécutée."
fi

echo
echo "Correctif local appliqué."
echo "Sauvegarde: $SAVE"
echo "Contrôle ensuite avec: git diff"
echo "Aucun commit ni push n'a été effectué."
