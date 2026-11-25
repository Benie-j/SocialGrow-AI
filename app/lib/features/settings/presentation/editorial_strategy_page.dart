import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/editorial_strategy.dart';
import '../../../data/editorial_strategy_repository.dart';
import '../../../data/publication_settings.dart';
import '../../../data/publication_settings_repository.dart';
import 'settings_widgets.dart';

const _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Écran « Stratégie éditoriale » : la boussole de la marque.
///
/// Il regroupe ce qui guide le contenu (activité, phrase de marque, piliers
/// pondérés, voix, formules à bannir) et montre en direct ce que ces choix
/// donnent sur une semaine type, d'après la fréquence des réglages de
/// publication. Source de vérité : la table `editorial_strategy`.
class EditorialStrategyPage extends StatefulWidget {
  const EditorialStrategyPage({
    super.key,
    this.settingsRepository,
    this.repository,
  });

  /// Espace, rôle, fréquence et public cible ; par défaut, Supabase.
  final PublicationSettingsRepository? settingsRepository;

  /// Stratégie éditoriale ; par défaut, Supabase.
  final EditorialStrategyRepository? repository;

  @override
  State<EditorialStrategyPage> createState() => _EditorialStrategyPageState();
}

class _EditorialStrategyPageState extends State<EditorialStrategyPage> {
  late final PublicationSettingsRepository _settingsRepo;
  late final EditorialStrategyRepository _repo;
  final _descriptionController = TextEditingController();
  final _taglineController = TextEditingController();

  WorkspaceAccess? _access;
  EditorialStrategy? _draft;
  PublicationSettings _publication = PublicationSettings();
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
    _repo = widget.repository ?? SupabaseEditorialStrategyRepository(client);
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  String _encode(EditorialStrategy s) => jsonEncode(s.toMap());

  bool get _canEdit => _access?.canEdit ?? false;

  Future<void> _load() async {
    try {
      final access = await _settingsRepo.loadAccess();
      final strategy = await _repo.load(access.workspaceId);
      final publication = await _settingsRepo.load(access.workspaceId);
      if (!mounted) {
        return;
      }
      _descriptionController.text = strategy.businessDescription;
      _taglineController.text = strategy.brandTagline;
      setState(() {
        _access = access;
        _draft = strategy;
        _publication = publication;
        _saved = _encode(strategy);
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

  void _edit(void Function(EditorialStrategy s) change) {
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
        const SnackBar(content: Text('Stratégie enregistrée.')),
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
      appBar: AppBar(title: const Text('Stratégie éditoriale')),
      body: content,
      bottomNavigationBar: bottomBar,
    );
  }

  Widget _buildForm(
    BuildContext context,
    EditorialStrategy d,
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
              'Lecture seule : ton rôle ne permet pas de modifier la '
              'stratégie.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
              ),
            ),
          ),
        if (_problems.isNotEmpty) _buildProblems(p, theme),
        _buildCompass(d, p, theme),
        const SizedBox(height: 14),
        _editable(_buildActivity(d, p, theme)),
        const SizedBox(height: 14),
        _editable(_buildPillars(d, p, theme)),
        const SizedBox(height: 14),
        _buildWeek(d, p, theme),
        const SizedBox(height: 14),
        _editable(_buildVoice(d, p, theme)),
      ],
    );
  }

  Widget _editable(Widget child) {
    return IgnorePointer(
      ignoring: !_canEdit,
      child: Opacity(opacity: _canEdit ? 1 : 0.65, child: child),
    );
  }

  Widget _buildProblems(SgPalette p, ThemeData theme) {
    return Padding(
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
    );
  }

  Widget _buildCompass(EditorialStrategy d, SgPalette p, ThemeData theme) {
    final steps = d.compass(audience: _publication.targetAudience);
    final done = steps.where((step) => step.done).length;
    final complete = done == steps.length;

    return GlassPanel(
      highlight: complete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: done / steps.length,
                        strokeWidth: 6,
                        backgroundColor: p.glassBorder,
                        color: p.accent,
                      ),
                    ),
                    Text(
                      '$done/${steps.length}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ta boussole éditoriale',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      complete
                          ? 'Cap fixé : le contenu suivra ta ligne.'
                          : 'Plus elle est claire, plus les textes générés '
                              'te ressemblent.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    step.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: step.done ? p.success : p.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step.label)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivity(EditorialStrategy d, SgPalette p, ThemeData theme) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ton activité', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Objectif, public cible et fréquence se règlent dans Paramètres '
            'de publication.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            maxLength: kMaxDescription,
            maxLines: 4,
            minLines: 3,
            onChanged: (v) => _edit((s) => s.businessDescription = v),
            decoration: const InputDecoration(
              labelText: 'Ce que tu fais, pour qui',
              hintText: 'Ex. : boulangerie artisanale à Abidjan, pains au '
                  'levain et viennoiseries du matin',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _taglineController,
            maxLength: kMaxTagline,
            onChanged: (v) => _edit((s) => s.brandTagline = v),
            decoration: const InputDecoration(
              labelText: 'Ta marque en une phrase',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Color _pillarColor(SgPalette p, int index) {
    final colors = [p.accent, p.accentCool, p.accentWarm, p.success, p.ink];
    return colors[index % colors.length];
  }

  Widget _buildPillars(EditorialStrategy d, SgPalette p, ThemeData theme) {
    final total = d.totalWeight;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Piliers de contenu', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Dose chaque famille de publications : la répartition ci-dessous '
            'guide la génération.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: total <= 0
                  ? Container(color: p.glassBorder)
                  : Row(
                      children: [
                        for (var i = 0; i < kPillars.length; i++)
                          if ((d.pillarWeights[kPillars[i].id] ?? 0) > 0)
                            Expanded(
                              flex: d.pillarWeights[kPillars[i].id] ?? 0,
                              child: Container(color: _pillarColor(p, i)),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in kPillarPresets.entries)
                ActionChip(
                  label: Text(entry.key),
                  onPressed: () => _edit(
                    (s) => s.pillarWeights = {...entry.value},
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < kPillars.length; i++)
            _buildPillarRow(d, p, theme, i, total),
        ],
      ),
    );
  }

  Widget _buildPillarRow(
    EditorialStrategy d,
    SgPalette p,
    ThemeData theme,
    int index,
    int total,
  ) {
    final pillar = kPillars[index];
    final weight = d.pillarWeights[pillar.id] ?? 0;
    final percent = total > 0 ? (weight * 100 / total).round() : 0;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _pillarColor(p, index),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(pillar.label, style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pillar.hint,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ),
              Text('$percent %', style: theme.textTheme.titleSmall),
            ],
          ),
          Slider(
            value: weight.toDouble(),
            min: 0,
            max: kMaxWeight.toDouble(),
            divisions: kMaxWeight,
            label: '$weight',
            onChanged: (v) => _edit((s) => s.pillarWeights[pillar.id] = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildWeek(EditorialStrategy d, SgPalette p, ThemeData theme) {
    final days = {
      for (final day in _publication.preferredDays)
        if (day >= 1 && day <= 7) day,
    }.toList()
      ..sort();
    final perDay = _publication.postsPerDay;
    final slots = perDay * days.length;
    final plan = planWeek(d.pillarWeights, slots);

    Widget body;
    if (plan.isEmpty) {
      body = Text(
        slots <= 0
            ? 'Règle d’abord les jours et le nombre de publications dans '
                'Paramètres de publication.'
            : 'Donne du poids à au moins un pilier pour voir ta semaine.',
        style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
      );
    } else {
      final rows = <MapEntry<int, List<String>>>[
        for (var i = 0; i < days.length; i++)
          MapEntry(days[i], plan.sublist(i * perDay, (i + 1) * perDay)),
      ];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.length} publication${plan.length > 1 ? 's' : ''} par '
            'semaine, réparties selon tes piliers.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      _dayLabels[row.key - 1],
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in row.value)
                          SgPill(
                            label: kPillars
                                .firstWhere((pillar) => pillar.id == id)
                                .label,
                            color: _pillarColor(
                              p,
                              kPillars.indexWhere((pillar) => pillar.id == id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ta semaine type', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _buildVoice(EditorialStrategy d, SgPalette p, ThemeData theme) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Voix de marque', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Ta voix : ${describeVoice(d.voiceFormality, d.voiceWarmth)}.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 10),
          _voiceSlider(
            left: 'Décontracté',
            right: 'Formel',
            value: d.voiceFormality,
            onChanged: (v) => _edit((s) => s.voiceFormality = v),
          ),
          _voiceSlider(
            left: 'Sobre',
            right: 'Chaleureux',
            value: d.voiceWarmth,
            onChanged: (v) => _edit((s) => s.voiceWarmth = v),
          ),
          const SizedBox(height: 8),
          TagEditor(
            label: 'Formules à bannir',
            hint: 'Un mot ou une expression à ne jamais écrire',
            tags: d.bannedPhrases,
            onChanged: (tags) => _edit((s) => s.bannedPhrases = tags),
          ),
        ],
      ),
    );
  }

  Widget _voiceSlider({
    required String left,
    required String right,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(left), Text(right)],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
