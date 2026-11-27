import 'package:material_ui/material_ui.dart';

import '../../../core/push/push_service.dart';
import '../../../core/theme/sg_palette.dart';

/// Propose d'activer les alertes instantanées (une fois, puis dans 7 jours
/// si l'utilisateur repousse).
Future<void> showPushPrompt(BuildContext context, PushService service) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      final p = SgPalette.of(context);
      final theme = Theme.of(context);

      return AlertDialog(
        icon: Icon(Icons.notifications_active_outlined, color: p.accent),
        title: const Text('Reste informé instantanément'),
        content: Text(
          'JUN AI te prévient dès qu’un post est publié, qu’un brouillon est '
          'prêt ou qu’un problème apparaît — même écran verrouillé ou '
          'application fermée.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activer'),
          ),
        ],
      );
    },
  );

  if (accepted == true) {
    await service.enable();
  } else {
    await service.dismissPrompt();
  }
}
