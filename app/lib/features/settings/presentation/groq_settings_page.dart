import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../data/groq_settings.dart';
import '../../../data/groq_settings_repository.dart';
import '../../../data/publication_settings_repository.dart';
import 'settings_widgets.dart';

/// Écran « Paramètres Groq » : modèles, créativité, longueur et garde-fou
/// mensuel, avec la consommation réelle du mois (table `ai_generation_logs`).
/// La clé Groq n'apparaît jamais ici : elle reste dans les secrets Supabase.
class GroqSettingsPage extends StatefulWidget {
  const GroqSettingsPage({
    super.key,
    this.settingsRepository,
    this.repository,
  });

  /// Espace et rôle ; par défaut, Supabase.
  final PublicationSettingsRepository? settingsRepository;

  /// Réglages Groq et consommation ; par défaut, Supabase.
  final GroqSettingsRepository? repository;

  @override
  State<GroqSettingsPage> createState() => _GroqSettingsPageState();
}

class _GroqSettingsPageState extends State<GroqSettingsPage> {
  late final PublicationSettingsRepository _settingsRepo;
  late final GroqSettingsRepository _repo;
  final _modelController = TextEditingController();
  final _draftController = TextEditingController();

  WorkspaceAccess? _access;
  GroqSettings? _draft;
  GroqUsage? _usage;
  Object? _usageError;
  String _saved = '';
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  List<String> _problems = const [];

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _settingsRepo =
        widget.settingsRepository ?? SupabasePublicationSettingsRepository(client);
    _repo = widget.repository ?? SupabaseGroqSettingsRepository(client);
    _load();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  String _encode(GroqSettings s) => jsonEncode(s.toMap());

  bool get _canEdit => _access?.canEdit ?? false;

  Future<void> _load() async {
    try {
      final access = await _settingsRepo.loadAccess();
      final settings = await _repo.load(access.workspaceId);
      GroqUsage? usage;
      Object? usageError;
      try {
        final now = DateTime.now();
        usage = await _repo.loadUsage(
          access.workspaceId,
          DateTime(now.year, now.month),
        );
      } catch (error) {
        usageError = error;
      }
      if (!mounted) {
        return;
      }
      _modelController.text = settings.model;
      _draftController.text = settings.draftModel;
      setState(() {
        _access = access;
        _draft = settings;
        _usage = usage;
        _usageError = usageError;
        _saved = _encode(settings);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _edit(void Function(GroqSettings s) change) {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    setState(() => change(draft));
  }

  Future<void> _save() async {
    final draft = _draft;
    final access = _access;
    if (draft == null || access == null) {
      return;
    }

    final problems = draft.validate();
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }

    setState(() {
      _problems = const [];
      _saving = true;
    });
    try {
      final stored = await _repo.save(access.workspaceId, draft);
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = stored;
        _saved = _encode(stored);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réglages Groq enregistrés.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final access = _access;

    Widget content;
    Widget? bottomBar;

    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (draft == null || access == null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                describeError(_loadError ?? 'inconnue'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    } else {
      content = _buildForm(context, draft, access);
      if (access.canEdit) {
        final dirty = _encode(draft) != _saved;
        bottomBar = SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (dirty && !_saving) ? _save : null,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres Groq')),
      body: content,
      bottomNavigationBar: bottomBar,
    );
  }

  Widget _buildForm(
    BuildContext context,
    GroqSettings d,
    WorkspaceAccess access,
  ) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
      children: [
        if (!access.canEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Lecture seule : ton rôle ne permet pas de modifier ces '
              'réglages.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
              ),
            ),
          ),
        if (_problems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: GlassPanel(
              color: p.accentWarm.withValues(alpha: 0.14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'À corriger avant d’enregistrer',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  for (final problem in _problems) Text('• $problem'),
                ],
              ),
            ),
          ),
        _buildUsage(d, p, theme),
        const SizedBox(height: 14),
        _editable(_buildModels(d, p, theme)),
        const SizedBox(height: 14),
        _editable(_buildGeneration(d, p, theme)),
        const SizedBox(height: 14),
        GlassPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ta clé Groq n’est jamais saisie ni stockée dans l’app : '
                  'elle reste dans les secrets du serveur, et seul le '
                  'serveur appelle Groq.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editable(Widget child) {
    return IgnorePointer(
      ignoring: !_canEdit,
      child: Opacity(opacity: _canEdit ? 1 : 0.65, child: child),
    );
  }

  Widget _stat(String value, String label, SgPalette p, ThemeData theme) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildUsage(GroqSettings d, SgPalette p, ThemeData theme) {
    final usage = _usage;
    final limit = d.monthlyGenerationLimit;

    Widget body;
    if (usage == null) {
      body = Text(
        _usageError == null
            ? 'Consommation indisponible.'
            : 'Consommation indisponible : ${describeError(_usageError!)}',
        style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
      );
    } else if (usage.generations == 0) {
      body = Text(
        'Aucune génération ce mois-ci. Le compteur se remplira dès que '
        'Groq produira des publications.',
        style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
      );
    } else {
      final ratio = usage.generations / limit;
      final latency = usage.averageLatencyMs;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${usage.generations} / $limit générations',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio > 1 ? 1 : ratio,
              minHeight: 10,
              backgroundColor: p.glassBorder,
              color: ratio >= 1 ? p.accentWarm : p.accent,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('${usage.totalTokens}', 'tokens', p, theme),
              _stat('${usage.successPercent ?? 0} %', 'réussies', p, theme),
              _stat(
                latency == null ? '–' : '$latency ms',
                'durée moyenne',
                p,
                theme,
              ),
            ],
          ),
        ],
      );
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consommation du mois', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _buildModels(GroqSettings d, SgPalette p, ThemeData theme) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modèles', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'La liste de Groq évolue : vérifie l’identifiant sur '
            'console.groq.com/docs/models avant de le saisir.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _modelController,
            autocorrect: false,
            onChanged: (v) => _edit((s) => s.model = v),
            decoration: const InputDecoration(
              labelText: 'Modèle des textes finaux',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _draftController,
            autocorrect: false,
            onChanged: (v) => _edit((s) => s.draftModel = v),
            decoration: const InputDecoration(
              labelText: 'Modèle des brouillons (plus léger)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Exemples (touche pour choisir le modèle final) :',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final example in kGroqModelExamples)
                ActionChip(
                  label: Text(example),
                  onPressed: () {
                    _modelController.text = example;
                    _edit((s) => s.model = example);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeneration(GroqSettings d, SgPalette p, ThemeData theme) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Génération', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            describeCreativity(d.creativity),
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          Slider(
            value: d.creativity.toDouble(),
            min: 0,
            max: kMaxCreativity.toDouble(),
            divisions: kMaxCreativity,
            label: '${d.creativity}',
            onChanged: (v) => _edit((s) => s.creativity = v.round()),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Fiable'), Text('Créatif')],
            ),
          ),
          const SizedBox(height: 8),
          NumberStepper(
            label: 'Longueur maximale d’un texte',
            subtitle: 'En tokens (environ 4 caractères chacun)',
            value: d.maxOutputTokens,
            min: kMinOutputTokens,
            max: kMaxOutputTokens,
            step: 100,
            onChanged: (v) => _edit((s) => s.maxOutputTokens = v),
          ),
          NumberStepper(
            label: 'Garde-fou mensuel',
            subtitle: 'Nombre maximum de générations par mois',
            value: d.monthlyGenerationLimit,
            min: kMinMonthlyLimit,
            max: kMaxMonthlyLimit,
            step: 50,
            onChanged: (v) => _edit((s) => s.monthlyGenerationLimit = v),
          ),
        ],
      ),
    );
  }
}
