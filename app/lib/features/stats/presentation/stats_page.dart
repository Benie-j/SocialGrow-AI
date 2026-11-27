import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/publication_settings_repository.dart';
import '../../../data/stats.dart';
import '../../../data/stats_repository.dart';

const _weekdayNames = [
  '',
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _typeLabels = {
  'text': 'Texte',
  'image': 'Image',
  'video': 'Vidéo',
  'link': 'Lien',
  'carousel': 'Carrousel',
};

String _monthShort(DateTime d) => const [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ][d.month - 1];

String _number(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u202f');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Statistiques : ce que tu publies (chiffres réels de tes publications) et,
/// quand Meta les a transmises, la portée et l'engagement de ta Page.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.repository});

  /// Sans dépôt (tests), l'onglet n'invente aucun chiffre.
  final StatsRepository? repository;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsData? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repo.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final data = _data;

    final children = <Widget>[
      const SgReveal(
        child: SgPageHeader(
          title: 'Statistiques',
          subtitle: 'Ce que tu publies, et ce que ta Page en retire.',
        ),
      ),
      const SizedBox(height: 18),
    ];

    if (widget.repository == null) {
      children.add(_note(p, theme, Icons.insights,
          'Aucune donnée à afficher pour le moment.'));
    } else if (data == null && _loading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (data == null) {
      children.add(_errorCard(p, theme));
    } else {
      children.addAll(_content(data, p, theme));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 100),
        children: children,
      ),
    );
  }

  Widget _note(SgPalette p, ThemeData theme, IconData icon, String text) {
    return GlassPanel(
      child: Row(
        children: [
          Icon(icon, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(SgPalette p, ThemeData theme) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error ?? 'Chargement impossible.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  List<Widget> _content(StatsData data, SgPalette p, ThemeData theme) {
    final s = data.posts;
    final out = <Widget>[];
    var order = 1;

    if (s.isEmpty) {
      out.add(SgReveal(
        order: order++,
        child: _note(p, theme, Icons.edit_note,
            'Rien n’a encore été publié ni planifié. Crée une première publication dans le Studio : tes chiffres apparaîtront ici.'),
      ));
    } else {
      out.add(SgReveal(order: order++, child: _summary(s, p, theme)));
      out.add(const SizedBox(height: 14));
      out.add(SgReveal(order: order++, child: _weeksCard(s, p, theme)));
      if (s.byType.isNotEmpty) {
        out.add(const SizedBox(height: 14));
        out.add(SgReveal(order: order++, child: _typesCard(s, p, theme)));
      }
      if (s.busiestWeekday != null) {
        out.add(const SizedBox(height: 14));
        out.add(SgReveal(
          order: order++,
          child: _note(
            p,
            theme,
            Icons.calendar_today_outlined,
            'Tu publies surtout le ${_weekdayNames[s.busiestWeekday!]} '
            '(${s.weekdayCounts[s.busiestWeekday!]} publications sur '
            '${s.publishedInWindow} ces 12 dernières semaines).',
          ),
        ));
      }
    }

    out.add(const SizedBox(height: 14));
    out.add(SgReveal(order: order, child: _insightsCard(data, p, theme)));
    return out;
  }

  Widget _stat(
    SgPalette p,
    ThemeData theme,
    String value,
    String label, {
    Color? color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _summary(PostStats s, SgPalette p, ThemeData theme) {
    final delta = s.deltaVsPrev;
    return GlassPanel(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('30 derniers jours',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (delta != null)
                SgPill(
                  label: delta == 0
                      ? 'Stable'
                      : '${delta > 0 ? '+' : '−'}${delta.abs()} vs 30 j précédents',
                  icon: delta >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: delta >= 0 ? p.success : p.accentWarm,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(p, theme, '${s.published30}', 'publiées'),
              _stat(p, theme, '${s.upcoming}', 'à venir'),
              _stat(p, theme, '${s.aiPublished30}', 'créées avec l’IA'),
            ],
          ),
          if (s.failed > 0 || s.drafts > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(p, theme, '${s.failed}', 'en échec',
                    color: s.failed > 0 ? p.accentWarm : null),
                _stat(p, theme, '${s.drafts}', 'brouillons'),
                const Spacer(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _weeksCard(PostStats s, SgPalette p, ThemeData theme) {
    final max = s.weekMax == 0 ? 1 : s.weekMax;
    const barArea = 96.0;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Publications par semaine',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SizedBox(
            height: barArea + 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < s.weeks.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${s.weeks[i].count}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: p.textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          height: s.weeks[i].count == 0
                              ? 3
                              : 6 + (barArea - 6) * s.weeks[i].count / max,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == s.weeks.length - 1
                                ? p.accent
                                : p.accent.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${s.weeks[i].monday.day}\n'
                          '${_monthShort(s.weeks[i].monday)}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: p.textSecondary, fontSize: 10, height: 1.1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Semaines commençant le lundi indiqué.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }

  Widget _typesCard(PostStats s, SgPalette p, ThemeData theme) {
    final entries = s.byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = s.published30 == 0 ? 1 : s.published30;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Formats publiés (30 jours)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final e in entries) ...[
            Row(
              children: [
                SizedBox(
                  width: 86,
                  child: Text(_typeLabels[e.key] ?? e.key,
                      style: theme.textTheme.bodyMedium),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: e.value / total,
                      minHeight: 8,
                      color: p.accent,
                      backgroundColor: p.glassBorder,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${e.value}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _insightsCard(StatsData data, SgPalette p, ThemeData theme) {
    if (data.insights.isEmpty) {
      return GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Portée et engagement',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                SgPill(
                  label: 'Pas encore reçus',
                  icon: Icons.hourglass_empty,
                  color: p.accentWarm,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data.hasPage
                  ? 'Meta n’a pas encore transmis les performances de ta Page. Elles s’afficheront ici dès qu’elles seront collectées.'
                  : 'Connecte une Page Facebook (Paramètres) pour suivre sa portée et son engagement.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      );
    }
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ta Page · 28 derniers jours',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final m in data.insights)
                SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_number(m.value),
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(m.label,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
