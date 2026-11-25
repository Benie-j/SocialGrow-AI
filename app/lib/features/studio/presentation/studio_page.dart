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
  final _idea = TextEditingController();
  final _editor = TextEditingController();
  final _settings = SupabasePublicationSettingsRepository(
    Supabase.instance.client,
  );

  String? _workspaceId;
  String? _workspaceName;
  String? _selectedPageId;
  String? _currentPostId;
  bool _canDelete = false;
  String? _error;
  bool _loading = true;
  bool _generating = false;
  bool _saving = false;
  bool _publishing = false;
  int _view = 0;
  String _filter = 'all';
  List<Map<String, dynamic>> _pages = [];
  List<Map<String, dynamic>> _posts = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idea.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final access = await _settings.loadAccess();
      final pages = await _client
          .from('facebook_pages')
          .select('id,page_name,picture_url')
          .eq('workspace_id', access.workspaceId)
          .eq('is_active', true)
          .order('page_name');
      final posts = await _client
          .from('posts')
          .select('id,title,body,status,content_type,created_at,scheduled_at,published_at,error_message,meta_post_id,facebook_page_id')
          .eq('workspace_id', access.workspaceId)
          .order('updated_at', ascending: false)
          .limit(60);

      if (!mounted) return;
      final pageRows = pages.map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        _workspaceId = access.workspaceId;
        _workspaceName = access.workspaceName;
        _canDelete = access.role == 'owner' || access.role == 'admin';
        _pages = pageRows;
        _posts = posts.map((e) => Map<String, dynamic>.from(e)).toList();
        _selectedPageId ??= pageRows.isNotEmpty ? pageRows.first['id'].toString() : null;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    final topic = _idea.text.trim();
    if (topic.length < 3) {
      _message('Décris ton idée en quelques mots avant de lancer la création.');
      return;
    }
    if (_workspaceId == null) return;

    setState(() {
      _generating = true;
      _error = null;
      _view = 0;
    });

    try {
      // Le serveur relit les paramètres et la stratégie à chaque génération.
      // Aucun ton, objectif, modèle ou réseau n'est choisi dans le Studio.
      final response = await _client.functions.invoke(
        'groq-generate-content',
        body: {'workspace_id': _workspaceId, 'topic': topic},
      );
      final data = response.data;
      if (data is! Map) throw Exception('Réponse du générateur invalide.');
      if (data['error'] != null) {
        throw Exception(data['message'] ?? data['error']);
      }
      final content = data['content'];
      if (content is! String || content.trim().isEmpty) {
        throw Exception('Le générateur n’a renvoyé aucun texte.');
      }
      if (!mounted) return;
      setState(() {
        _editor.text = content.trim();
        _currentPostId = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _readableError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<String?> _saveDraft({bool quiet = false}) async {
    final body = _editor.text.trim();
    if (body.isEmpty || _workspaceId == null) {
      if (!quiet) _message('Le texte de la publication est vide.');
      return null;
    }
    setState(() => _saving = true);
    try {
      final title = _idea.text.trim().isEmpty
          ? body.split('\n').first
          : _idea.text.trim();
      if (_currentPostId == null) {
        final user = _client.auth.currentUser;
        if (user == null) throw Exception('Session expirée.');
        final row = await _client.from('posts').insert({
          'workspace_id': _workspaceId,
          'created_by': user.id,
          'title': title,
          'body': body,
          'content_type': 'text',
          'status': 'draft',
          'source': 'ai',
        }).select('id').single();
        _currentPostId = row['id'].toString();
      } else {
        await _client.from('posts').update({
          'title': title,
          'body': body,
          'content_type': 'text',
          'status': 'draft',
          'error_message': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _currentPostId!).eq('workspace_id', _workspaceId!);
      }
      await _loadPosts();
      if (!quiet && mounted) _message('Brouillon enregistré.');
      return _currentPostId;
    } catch (e) {
      if (!quiet && mounted) _message('Enregistrement impossible : ${_readableError(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    if (_selectedPageId == null) {
      _message('Connecte d’abord une Page Facebook dans les paramètres.');
      return;
    }
    if (_editor.text.trim().isEmpty) {
      _message('Écris ou génère une publication avant de publier.');
      return;
    }

    final page = _pages.firstWhere(
      (p) => p['id'].toString() == _selectedPageId,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publier maintenant ?'),
        content: Text(
          'Cette publication sera envoyée immédiatement sur « ${page['page_name']} ». '
          'Elle ne pourra pas être annulée depuis JUN AI. Si une tentative précédente s’est interrompue, vérifie d’abord la Page pour éviter un doublon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer la publication'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final postId = await _saveDraft(quiet: true);
    if (postId == null) return;

    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final response = await _client.functions.invoke(
        'facebook-publish-post',
        body: {
          'workspace_id': _workspaceId,
          'post_id': postId,
          'facebook_page_id': _selectedPageId,
        },
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw Exception(
          data is Map ? (data['message'] ?? data['error']) : 'Réponse de publication invalide.',
        );
      }
      if (!mounted) return;
      _message(data['already_published'] == true
          ? 'Cette publication est déjà publiée.'
          : 'Publication confirmée par Facebook.');
      setState(() => _view = 1);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _readableError(e));
      await _loadPosts();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _loadPosts() async {
    if (_workspaceId == null) return;
    final rows = await _client
        .from('posts')
        .select('id,title,body,status,content_type,created_at,scheduled_at,published_at,error_message,meta_post_id,facebook_page_id')
        .eq('workspace_id', _workspaceId!)
        .order('updated_at', ascending: false)
        .limit(60);
    if (!mounted) return;
    setState(() => _posts = rows.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  void _openPost(Map<String, dynamic> post) {
    setState(() {
      _currentPostId = post['status'] == 'draft' ? post['id'].toString() : null;
      _error = post['status'] == 'failed' ? post['error_message']?.toString() : null;
      _idea.text = (post['title'] ?? '').toString();
      _editor.text = (post['body'] ?? '').toString();
      final pageId = post['facebook_page_id']?.toString();
      if (pageId != null && _pages.any((p) => p['id'].toString() == pageId)) {
        _selectedPageId = pageId;
      }
      _view = 0;
    });
  }

  Future<void> _deleteDraft(Map<String, dynamic> post) async {
    if (post['status'] != 'draft') return;
    final id = post['id'].toString();
    try {
      await _client.from('posts').delete()
          .eq('id', id).eq('workspace_id', _workspaceId!);
      if (_currentPostId == id) {
        setState(() {
          _currentPostId = null;
          _editor.clear();
          _idea.clear();
        });
      }
      await _loadPosts();
    } catch (e) {
      _message('Suppression impossible : ${_readableError(e)}');
    }
  }

  String _readableError(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        return details['message'].toString();
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _panel({required Widget child}) {
    final p = SgPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.glassBorder),
      ),
      child: child,
    );
  }

  Widget _buildComposer() {
    final p = SgPalette.of(context);
    final selectedPage = _pages.where(
      (e) => e['id'].toString() == _selectedPageId,
    );
    final pageName = selectedPage.isEmpty
        ? 'Aucune Page sélectionnée'
        : selectedPage.first['page_name'].toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Atelier de création',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('GROQ', style: TextStyle(color: p.textSecondary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Décris ton idée. JUN AI applique automatiquement la stratégie, le ton et les règles définis dans tes paramètres.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _idea,
                minLines: 2,
                maxLines: 4,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Ton idée ou ton brief',
                  hintText: 'Ex. : présenter le nouveau service et donner envie de découvrir la page…',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_generating ? 'Création en cours…' : 'Créer avec JUN AI'),
                ),
              ),
            ],
          ),
        ),
        if (_editor.text.isNotEmpty) ...[
          const SizedBox(height: 14),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Éditeur', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Copier le texte',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _editor.text));
                        _message('Texte copié.');
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                TextField(
                  controller: _editor,
                  minLines: 9,
                  maxLines: 22,
                  maxLength: 63206,
                  decoration: const InputDecoration(
                    hintText: 'Ta publication apparaîtra ici…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Aperçu de la publication', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.glassBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 17,
                            backgroundColor: SgPalette.lime,
                            child: Icon(Icons.auto_awesome, color: SgPalette.inkDark, size: 18),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(pageName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          const Icon(Icons.public, size: 16),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(_editor.text),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPageId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Page Facebook de destination',
                    border: OutlineInputBorder(),
                  ),
                  items: _pages.map((page) {
                    return DropdownMenuItem<String>(
                      value: page['id'].toString(),
                      child: Text(page['page_name'].toString(), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: _publishing || _saving
                      ? null
                      : (value) => setState(() => _selectedPageId = value),
                ),
                if (_pages.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Aucune Page active. Connecte une Page Facebook depuis les paramètres.',
                    style: TextStyle(color: p.accentWarm),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _publishing ? null : _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Enregistrement…' : 'Brouillon'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _publishing || _saving || _pages.isEmpty ? null : _publish,
                        icon: _publishing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: Text(_publishing ? 'Publication…' : 'Publier'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: p.accentWarm)),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> get _visiblePosts {
    if (_filter == 'all') return _posts;
    return _posts.where((p) => p['status'] == _filter).toList();
  }

  Widget _buildLibrary() {
    final p = SgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bibliothèque', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Retrouve tes brouillons et l’état de tes publications.', style: TextStyle(color: p.textSecondary)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                ('all', 'Tout'),
                ('draft', 'Brouillons'),
                ('published', 'Publiés'),
                ('failed', 'Échecs'),
                ('scheduled', 'Programmés'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: _filter == entry.$1,
                    onSelected: (_) => setState(() => _filter = entry.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_visiblePosts.isEmpty)
          _panel(child: Text('Aucune publication dans cette catégorie.', style: TextStyle(color: p.textSecondary))),
        for (final post in _visiblePosts)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (post['title'] ?? 'Sans titre').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _statusBadge(post['status'].toString()),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    (post['body'] ?? '').toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary),
                  ),
                  if (post['error_message'] != null && post['status'] == 'failed') ...[
                    const SizedBox(height: 6),
                    Text(post['error_message'].toString(), style: TextStyle(color: p.accentWarm, fontSize: 12)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _openPost(post),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Ouvrir'),
                      ),
                      const Spacer(),
                      if (post['status'] == 'draft' && _canDelete)
                        IconButton(
                          tooltip: 'Supprimer le brouillon',
                          onPressed: () => _deleteDraft(post),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final p = SgPalette.of(context);
    final labels = {
      'draft': 'Brouillon',
      'pending_approval': 'À valider',
      'scheduled': 'Programmé',
      'publishing': 'En cours',
      'published': 'Publié',
      'failed': 'Échec',
      'cancelled': 'Annulé',
    };
    final color = status == 'published'
        ? p.success
        : status == 'failed'
            ? p.accentWarm
            : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity66666666666666666666(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(labels[status] ?? status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_workspaceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspaces_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Aucun espace de travail disponible.'),
              if (_error != null) Text(_error!, textAlign: TextAlign.center),
              TextButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Studio IA', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 3),
                    Text(_workspaceName ?? 'Espace de travail', style: TextStyle(color: p.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.edit_note), label: Text('Créer')),
              ButtonSegment(value: 1, icon: Icon(Icons.library_books_outlined), label: Text('Bibliothèque')),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
          const SizedBox(height: 16),
          if (_view == 0) _buildComposer() else _buildLibrary(),
        ],
      ),
    );
  }
}
