import 'package:material_ui/material_ui.dart';
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.userEmail});

  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    final email = userEmail ?? 'Compte utilisateur';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Bienvenue 👋',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          email,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2563EB),
                Color(0xFF4F46E5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(height: 18),
              Text(
                'Ta croissance commence ici.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Prépare tes contenus, organise tes publications '
                'et développe ta communauté.',
                style: TextStyle(
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Ton espace de travail',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 14),
        const _DashboardCard(
          icon: Icons.facebook,
          title: 'Page Facebook',
          subtitle: 'La connexion de ta Page sera configurée ici.',
        ),
        const SizedBox(height: 12),
        const _DashboardCard(
          icon: Icons.edit_note,
          title: 'Tes publications',
          subtitle: 'Tes contenus seront regroupés dans cet espace.',
        ),
        const SizedBox(height: 12),
        const _DashboardCard(
          icon: Icons.auto_awesome,
          title: 'Assistant IA',
          subtitle: 'L’assistant Groq sera intégré à la création.',
        ),
        const SizedBox(height: 24),
        Text(
          'Les fonctions Facebook et Groq seront activées dans les '
          'prochaines étapes.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
