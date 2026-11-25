import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/facebook_connection.dart';
import '../../../data/publication_settings_repository.dart';
import '../../../data/workspace_overview.dart';
import 'facebook_connection_page.dart';
import 'publication_settings_page.dart';

class _Entry {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.available = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool available;
}

const _entries = [
  _Entry(
    icon: Icons.person_outline,
    title: 'Compte et profil',
    subtitle: 'Informations de ton compte',
  ),
  _Entry(
    icon: Icons.link,
    title: 'Connexion Facebook',
    subtitle: 'Page à gérer et autorisations Meta',
  ),
  _Entry(
    icon: Icons.tune,
    title: 'Paramètres de publication',
    subtitle: 'Fréquence, horaires, contenu, formats, automatisation, '
        'stratégie et doublons',
    available: true,
  ),
  _Entry(
    icon: Icons.lightbulb_outline,
    title: 'Stratégie éditoriale',
    subtitle: 'Objectif et public se règlent dans « Paramètres de '
        'publication »',
  ),
  _Entry(
    icon: Icons.auto_awesome_outlined,
    title: 'Paramètres Groq',
    subtitle: 'Modèle et options de génération',
  ),
  _Entry(
    icon: Icons.notifications_none,
    title: 'Notifications',
    subtitle: 'Alertes de publication et d’erreur',
  ),
  _Entry(
    icon: Icons.security_outlined,
    title: 'Sécurité',
    subtitle: 'Connexion et protection du compte',
  ),
  _Entry(
    icon: Icons.info_outline,
    title: 'À propos',
    subtitle: 'Version de l’application',
    available: true,
  ),
];

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.repository,
    this.onSignOut,
    this.facebookRepository,
    this.workspace,
    this.onWorkspaceChanged,
  });

  /// Injectable pour les tests ; par défaut, Supabase.
  final PublicationSettingsRepository? repository;

  /// Dépôt de la connexion Facebook ; sans lui, la rubrique reste « Bientôt ».
  final FacebookConnectionRepository? facebookRepository;

  /// Espace de travail chargé (identifiant et rôle) ; requis pour la rubrique
  /// « Connexion Facebook ».
  final WorkspaceOverview? workspace;

  /// Appelé après une connexion ou une déconnexion de Page.
  final Future<void> Function()? onWorkspaceChanged;

  bool _isAvailable(_Entry entry) {
    if (entry.title == 'Connexion Facebook') {
      return facebookRepository != null && workspace != null;
    }
    return entry.available;
  }

  /// Action de déconnexion ; le bouton n'apparaît que si elle est fournie.
  final Future<void> Function()? onSignOut;

  void _open(BuildContext context, _Entry entry) {
    if (entry.title == 'Paramètres de publication') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicationSettingsPage(repository: repository),
        ),
      );
    } else if (entry.title == 'Connexion Facebook') {
      final repo = facebookRepository;
      final space = workspace;
      if (repo == null || space == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FacebookConnectionPage(
            repository: repo,
            workspaceId: space.workspaceId,
            role: space.role,
            onChanged: onWorkspaceChanged,
          ),
        ),
      );
    } else if (entry.title == 'À propos') {
      showAboutDialog(
        context: context,
        applicationName: 'SocialGrow AI',
        applicationVersion: '0.1.0',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final signOut = onSignOut;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 100),
      children: [
        const SgReveal(
          child: SgPageHeader(
            title: 'Paramètres',
            subtitle: 'Personnalise ton espace SocialGrow.',
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < _entries.length; i++) ...[
          SgReveal(
            order: 1 + (i < 4 ? i : 4),
            child: _EntryTile(
              entry: _entries[i],
              enabled: _isAvailable(_entries[i]),
              onTap: _isAvailable(_entries[i])
                  ? () => _open(context, _entries[i])
                  : null,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (signOut != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.glassBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'SocialGrow AI • version 0.1.0',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final _Entry entry;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        radius: 22,
        highlight: enabled && entry.title == 'Paramètres de publication',
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: enabled ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(entry.icon, color: p.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    entry.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (enabled)
              Icon(Icons.chevron_right, color: p.textSecondary)
            else
              const SgPill(label: 'Bientôt'),
          ],
        ),
      ),
    );
  }
}
