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

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 28),
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
        SgReveal(order: 1, child: _OrbArt(icon: icon)),
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
                      color: p.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(highlights[i].icon, color: p.accent),
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

class _OrbArt extends StatelessWidget {
  const _OrbArt({required this.icon});

  final IconData icon;

  Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }

  Widget _dot(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(214, p.accent.withValues(alpha: 0.10)),
          _ring(160, p.accent.withValues(alpha: 0.18)),
          _ring(112, p.accent.withValues(alpha: 0.30)),
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              gradient: SgPalette.brand,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.55),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(icon, size: 38, color: Colors.white),
          ),
          Align(
            alignment: const Alignment(0.78, -0.55),
            child: _dot(11, p.accentCool),
          ),
          Align(
            alignment: const Alignment(-0.82, 0.35),
            child: _dot(9, p.accentWarm),
          ),
          Align(
            alignment: const Alignment(0.55, 0.78),
            child: _dot(7, p.accent),
          ),
        ],
      ),
    );
  }
}
