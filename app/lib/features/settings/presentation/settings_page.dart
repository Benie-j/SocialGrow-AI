import 'package:material_ui/material_ui.dart';

import '../../../data/publication_settings_repository.dart';
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
  const SettingsPage({super.key, this.repository});

  /// Injectable pour les tests ; par défaut, Supabase.
  final PublicationSettingsRepository? repository;

  void _open(BuildContext context, _Entry entry) {
    if (entry.title == 'Paramètres de publication') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicationSettingsPage(repository: repository),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in _entries)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              enabled: entry.available,
              leading: Icon(entry.icon),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              trailing: entry.available
                  ? const Icon(Icons.chevron_right)
                  : const Text('Bientôt'),
              onTap: entry.available ? () => _open(context, entry) : null,
            ),
          ),
      ],
    );
  }
}
