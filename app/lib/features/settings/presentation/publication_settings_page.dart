import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/publication_settings.dart';
import '../../../data/publication_settings_repository.dart';
import 'settings_widgets.dart';

const _languages = {
  'fr': 'Français',
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
};

const _tones = {
  'professional': 'Professionnel',
  'friendly': 'Amical',
  'casual': 'Décontracté',
  'inspirational': 'Inspirant',
  'humorous': 'Humoristique',
  'informative': 'Informatif',
};

const _lengths = {'short': 'Court', 'medium': 'Moyen', 'long': 'Long'};

const _styles = {
  'conversational': 'Conversationnel',
  'storytelling': 'Narratif',
  'direct': 'Direct',
  'educational': 'Pédagogique',
};

const _goals = {
  'followers': 'Abonnés',
  'engagement': 'Engagement',
  'reach': 'Visibilité',
  'sales': 'Ventes',
};

const _roles = {
  'owner': 'Propriétaire',
  'admin': 'Administrateur',
  'editor': 'Éditeur',
  'viewer': 'Lecteur',
};

const _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

const _timezones = [
  'Africa/Abidjan',
  'Africa/Dakar',
  'Africa/Lagos',
  'Africa/Kinshasa',
  'Africa/Casablanca',
  'Africa/Nairobi',
  'Africa/Johannesburg',
  'Europe/London',
  'Europe/Paris',
  'Europe/Brussels',
  'America/New_York',
  'America/Toronto',
  'America/Sao_Paulo',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Tokyo',
  'UTC',
];

/// Rubrique unique des réglages de publication (source de vérité : Supabase).
class PublicationSettingsPage extends StatefulWidget {
  const PublicationSettingsPage({super.key, this.repository});

  /// Injectable pour les tests ; par défaut, Supabase.
  final PublicationSettingsRepository? repository;

  @override
  State<PublicationSettingsPage> createState() =>
      _PublicationSettingsPageState();
}

class _PublicationSettingsPageState extends State<PublicationSettingsPage> {
  late final PublicationSettingsRepository _repo;
  WorkspaceAccess? _access;
  PublicationSettings? _draft;
  String _saved = '';
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  List<String> _problems = const [];

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ??
        SupabasePublicationSettingsRepository(Supabase.instance.client);
    _load();
  }

  String _encode(PublicationSettings s) => jsonEncode(s.toMap());

  bool get _canEdit => _access?.canEdit ?? false;

  Future<void> _load() async {
    try {
      final access = await _repo.loadAccess();
      final settings = await _repo.load(access.workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _access = access;
        _draft = settings;
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

  void _edit(void Function(PublicationSettings s) change) {
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
        const SnackBar(content: Text('Réglages enregistrés.')),
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
    final access = _access;
    final draft = _draft;

    Widget content;
    Widget? bottomBar;

    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (access == null || draft == null) {
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
      content = _buildForm(context, access, draft);
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
      appBar: AppBar(title: const Text('Paramètres de publication')),
      body: content,
      bottomNavigationBar: bottomBar,
    );
  }

  Widget _buildForm(
    BuildContext context,
    WorkspaceAccess access,
    PublicationSettings d,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timezones =
        _timezones.contains(d.timezone) ? _timezones : [d.timezone, ..._timezones];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          color: scheme.secondaryContainer,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Espace : ${access.workspaceName}',
                  style: textTheme.titleSmall,
                ),
                Text('Rôle : ${_roles[access.role] ?? access.role}'),
                if (!access.canEdit)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Lecture seule : ton rôle ne permet pas de modifier '
                      'ces réglages.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_problems.isNotEmpty)
          Card(
            color: scheme.errorContainer,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'À corriger avant d’enregistrer',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final problem in _problems)
                    Text(
                      '• $problem',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                ],
              ),
            ),
          ),
        _section(
          title: 'Fréquence',
          subtitle: 'Combien, quels jours, à quel rythme',
          icon: Icons.repeat,
          expanded: true,
          children: [
            NumberStepper(
              label: 'Publications par jour',
              value: d.postsPerDay,
              min: 0,
              max: 50,
              onChanged: (v) => _edit((s) => s.postsPerDay = v),
            ),
            NumberStepper(
              label: 'Maximum par jour',
              subtitle: 'Limite de sécurité contre les abus',
              value: d.dailyPostLimit,
              min: 0,
              max: 50,
              onChanged: (v) => _edit((s) => s.dailyPostLimit = v),
            ),
            NumberStepper(
              label: 'Intervalle minimum entre deux publications',
              value: d.minIntervalMinutes,
              min: 0,
              max: 1440,
              step: 15,
              suffix: ' min',
              onChanged: (v) => _edit((s) => s.minIntervalMinutes = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text('Jours de publication', style: textTheme.bodyLarge),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _dayLabels.length; i++)
                  FilterChip(
                    label: Text(_dayLabels[i]),
                    selected: d.preferredDays.contains(i + 1),
                    onSelected: (selected) => _edit((s) {
                      final day = i + 1;
                      s.preferredDays = selected
                          ? [...s.preferredDays, day]
                          : s.preferredDays.where((x) => x != day).toList();
                    }),
                  ),
              ],
            ),
          ],
        ),
        _section(
          title: 'Horaires',
          subtitle: 'Fuseau, heures et créneaux autorisés',
          icon: Icons.schedule,
          children: [
            PickerTile(
              label: 'Fuseau horaire',
              value: d.timezone,
              options: timezones,
              onChanged: (v) => _edit((s) => s.timezone = v),
            ),
            TimeListEditor(
              label: 'Heures de publication',
              times: d.preferredTimes,
              onChanged: (v) => _edit((s) => s.preferredTimes = v),
            ),
            WindowsEditor(
              label: 'Créneaux autorisés',
              windows: d.allowedTimeWindows,
              onChanged: (v) => _edit((s) => s.allowedTimeWindows = v),
            ),
          ],
        ),
        _section(
          title: 'Contenu',
          subtitle: 'Langue, ton, thématiques, hashtags',
          icon: Icons.edit_note,
          children: [
            ChoiceField(
              label: 'Langue des publications',
              value: d.language,
              options: _languages,
              onChanged: (v) => _edit((s) => s.language = v),
            ),
            ChoiceField(
              label: 'Ton rédactionnel',
              value: d.defaultTone,
              options: _tones,
              onChanged: (v) => _edit((s) => s.defaultTone = v),
            ),
            ChoiceField(
              label: 'Longueur',
              value: d.defaultLength,
              options: _lengths,
              onChanged: (v) => _edit((s) => s.defaultLength = v),
            ),
            ChoiceField(
              label: 'Style de rédaction',
              value: d.writingStyle,
              options: _styles,
              onChanged: (v) => _edit((s) => s.writingStyle = v),
            ),
            TagEditor(
              label: 'Catégories autorisées',
              hint: 'Ex. Astuces, Actualités',
              tags: d.allowedCategories,
              onChanged: (v) => _edit((s) => s.allowedCategories = v),
            ),
            TagEditor(
              label: 'Thématiques à privilégier',
              hint: 'Ajoute une thématique',
              tags: d.preferredTopics,
              onChanged: (v) => _edit((s) => s.preferredTopics = v),
            ),
            TagEditor(
              label: 'Thématiques à éviter',
              hint: 'Ajoute une thématique',
              tags: d.avoidedTopics,
              onChanged: (v) => _edit((s) => s.avoidedTopics = v),
            ),
            SwitchRow(
              label: 'Utiliser des hashtags',
              value: d.hashtagsEnabled,
              onChanged: (v) => _edit((s) => s.hashtagsEnabled = v),
            ),
            if (d.hashtagsEnabled)
              NumberStepper(
                label: 'Nombre maximal de hashtags',
                value: d.maxHashtags,
                min: 0,
                max: 30,
                onChanged: (v) => _edit((s) => s.maxHashtags = v),
              ),
            SwitchRow(
              label: 'Ajouter un appel à l’action',
              value: d.ctaEnabled,
              onChanged: (v) => _edit((s) => s.ctaEnabled = v),
            ),
          ],
        ),
        _section(
          title: 'Formats',
          subtitle: 'Types de publications autorisés',
          icon: Icons.perm_media_outlined,
          children: [
            SwitchRow(
              label: 'Texte seul',
              value: d.formatTextEnabled,
              onChanged: (v) => _edit((s) => s.formatTextEnabled = v),
            ),
            SwitchRow(
              label: 'Texte avec images',
              value: d.formatImageEnabled,
              onChanged: (v) => _edit((s) => s.formatImageEnabled = v),
            ),
            SwitchRow(
              label: 'Vidéos',
              subtitle: 'Dépend des formats et permissions accordés par Meta.',
              value: d.formatVideoEnabled,
              onChanged: (v) => _edit((s) => s.formatVideoEnabled = v),
            ),
          ],
        ),
        _section(
          title: 'Automatisation',
          subtitle: 'Génération, validation, erreurs',
          icon: Icons.smart_toy_outlined,
          children: [
            SwitchRow(
              label: 'Publication automatique',
              value: d.autoPublish,
              onChanged: (v) => _edit((s) => s.autoPublish = v),
            ),
            SwitchRow(
              label: 'Génération automatique des contenus',
              value: d.autoGenerate,
              onChanged: (v) => _edit((s) => s.autoGenerate = v),
            ),
            SwitchRow(
              label: 'Validation obligatoire avant publication',
              value: d.requireApproval,
              onChanged: (v) => _edit((s) => s.requireApproval = v),
            ),
            if (d.autoPublish && !d.requireApproval)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Les contenus seront publiés sans validation préalable.',
                  style: textTheme.bodySmall,
                ),
              ),
            SwitchRow(
              label: 'Suspendre temporairement les publications',
              value: d.publishingPaused,
              onChanged: (v) => _edit((s) => s.publishingPaused = v),
            ),
            NumberStepper(
              label: 'Nouvelles tentatives en cas d’erreur',
              value: d.maxRetries,
              min: 0,
              max: 10,
              onChanged: (v) => _edit((s) => s.maxRetries = v),
            ),
            NumberStepper(
              label: 'Délai entre deux tentatives',
              value: d.retryDelayMinutes,
              min: 1,
              max: 1440,
              step: 5,
              suffix: ' min',
              onChanged: (v) => _edit((s) => s.retryDelayMinutes = v),
            ),
          ],
        ),
        _section(
          title: 'Stratégie',
          subtitle: 'Objectif, public, adaptation',
          icon: Icons.flag_outlined,
          children: [
            ChoiceField(
              label: 'Objectif prioritaire',
              value: d.primaryGoal,
              options: _goals,
              onChanged: (v) => _edit((s) => s.primaryGoal = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('target_audience'),
              initialValue: d.targetAudience ?? '',
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Public cible',
                hintText: 'Ex. entrepreneurs de 25 à 40 ans',
              ),
              onChanged: (v) => _edit((s) => s.targetAudience = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('preferred_content_type'),
              initialValue: d.preferredContentType ?? '',
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Type de contenu privilégié',
                hintText: 'Ex. conseils pratiques',
              ),
              onChanged: (v) => _edit((s) => s.preferredContentType = v),
            ),
            NumberStepper(
              label: 'Renouvellement des sujets',
              subtitle: 'Jours avant de changer de thématique',
              value: d.topicRenewalDays,
              min: 0,
              max: 365,
              suffix: ' j',
              onChanged: (v) => _edit((s) => s.topicRenewalDays = v),
            ),
            SwitchRow(
              label: 'S’adapter aux performances passées',
              subtitle: 'Ajuste les contenus selon les résultats réels.',
              value: d.adaptToPerformance,
              onChanged: (v) => _edit((s) => s.adaptToPerformance = v),
            ),
          ],
        ),
        _section(
          title: 'Gestion des doublons',
          subtitle: 'Éviter les contenus répétitifs',
          icon: Icons.content_copy_outlined,
          children: [
            SwitchRow(
              label: 'Détecter les publications similaires',
              value: d.duplicateDetectionEnabled,
              onChanged: (v) => _edit((s) => s.duplicateDetectionEnabled = v),
            ),
            if (d.duplicateDetectionEnabled) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Seuil de similarité : '
                  '${(d.duplicateSimilarityThreshold * 100).round()} %',
                  style: textTheme.bodyLarge,
                ),
              ),
              Slider(
                value: d.duplicateSimilarityThreshold.clamp(0.5, 1.0),
                min: 0.5,
                max: 1.0,
                divisions: 10,
                label: '${(d.duplicateSimilarityThreshold * 100).round()} %',
                onChanged: (v) =>
                    _edit((s) => s.duplicateSimilarityThreshold = v),
              ),
            ],
            NumberStepper(
              label: 'Délai minimum avant de réutiliser une idée',
              value: d.topicReuseMinDays,
              min: 0,
              max: 3650,
              step: 10,
              suffix: ' j',
              onChanged: (v) => _edit((s) => s.topicReuseMinDays = v),
            ),
            SwitchRow(
              label: 'Interdire la republication à l’identique',
              value: d.blockIdenticalRepublish,
              onChanged: (v) => _edit((s) => s.blockIdenticalRepublish = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    bool expanded = false,
  }) {
    return Card(
      key: ValueKey(title),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            ignoring: !_canEdit,
            child: Opacity(
              opacity: _canEdit ? 1 : 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
