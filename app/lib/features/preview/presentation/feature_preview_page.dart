import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_pill.dart';

class FeatureHighlight {
  const FeatureHighlight({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;
}

/// Écran d'une rubrique pas encore ouverte : annonce ce qui arrive.
class FeaturePreviewPage extends StatelessWidget {
  const FeaturePreviewPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.highlights,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<FeatureHighlight> highlights;

  static List<Color> _tints(SgPalette p) =>
      [p.accent, p.accentWarm, p.accentCool];

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 100),
      children: [
        SgReveal(
          child: SgPageHeader(
            title: title,
            subtitle: description,
            trailing: SgPill(
              label: 'En préparation',
              icon: Icons.bolt,
              color: p.accentWarm,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SgReveal(order: 1, child: _StickerArt(icon: icon)),
        const SizedBox(height: 8),
        SgReveal(
          order: 2,
          child: Text('Ce qui arrive', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < highlights.length; i++) ...[
          SgReveal(
            order: 3 + i,
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _tints(p)[i % 3].withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(highlights[i].icon, color: _tints(p)[i % 3]),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          highlights[i].title,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          highlights[i].text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: p.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 6),
        Text(
          'Ces fonctions seront activées au fil des prochaines étapes.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

/// Illustration de rubrique : un sticker incliné entouré de petites étincelles.
class _StickerArt extends StatelessWidget {
  const _StickerArt({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    const ink = SgPalette.inkDark;

    Widget spark(double size, Color color, double angle) => Transform.rotate(
          angle: angle,
          child: Icon(Icons.auto_awesome, size: size, color: color),
        );

    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.12,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: p.accentWarm.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(color: p.ink, width: 1.6),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.07,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: SgPalette.lime,
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: p.isDark ? SgPalette.lime : ink,
                  width: 1.6,
                ),
                boxShadow: [
                  if (!p.isDark)
                    const BoxShadow(
                      color: ink,
                      offset: Offset(6, 6),
                      blurRadius: 0,
                    ),
                ],
              ),
              child: Icon(icon, size: 70, color: ink),
            ),
          ),
          Align(
            alignment: const Alignment(0.74, -0.7),
            child: spark(30, p.accent, 0.2),
          ),
          Align(
            alignment: const Alignment(-0.8, 0.5),
            child: spark(22, p.accentCool, -0.3),
          ),
          Align(
            alignment: const Alignment(0.62, 0.85),
            child: spark(16, p.accentWarm, 0.5),
          ),
        ],
      ),
    );
  }
}
