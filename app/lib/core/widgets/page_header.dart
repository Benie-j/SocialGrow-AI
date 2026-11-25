import 'package:material_ui/material_ui.dart';

import '../theme/sg_palette.dart';

/// En-tête de page : grand titre, sous-titre et action optionnelle.
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
              Text(title, style: theme.textTheme.headlineMedium),
              if (sub != null) ...[
                const SizedBox(height: 6),
                Text(
                  sub,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: p.textSecondary,
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
