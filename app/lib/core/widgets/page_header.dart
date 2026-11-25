import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// En-tête de page : trait d'accent, grand titre, sous-titre et action.
class SgPageHeader extends StatelessWidget {
  const SgPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final sub = subtitle;
    final action = trailing;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 7,
                decoration: BoxDecoration(
                  color: SgPalette.lime,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: p.ink.withValues(alpha: 0.9)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 34),
              ),
              if (sub != null) ...[
                const SizedBox(height: 8),
                Text(
                  sub,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: p.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }
}
