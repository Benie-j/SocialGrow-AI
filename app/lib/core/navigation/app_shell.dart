import 'package:material_ui/material_ui.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/placeholder/presentation/placeholder_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onSignOut,
    this.userEmail,
  });

  final Future<void> Function() onSignOut;
  final String? userEmail;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Accueil',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome),
      label: 'Création IA',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Calendrier',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Statistiques',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Paramètres',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(userEmail: widget.userEmail),
      const PlaceholderPage(
        title: 'Création IA',
        description: 'Prépare des publications adaptées à ta Page Facebook.',
        icon: Icons.auto_awesome,
      ),
      const PlaceholderPage(
        title: 'Calendrier',
        description: 'Organise et retrouve tes prochaines publications.',
        icon: Icons.calendar_month,
      ),
      const PlaceholderPage(
        title: 'Statistiques',
        description: 'Retrouve ici les performances de ta Page.',
        icon: Icons.insights,
      ),
      const PlaceholderPage(
        title: 'Paramètres',
        description: 'Configure ton espace et tes préférences.',
        icon: Icons.settings,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SocialGrow AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: () async {
              await widget.onSignOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
        },
        destinations: _destinations,
      ),
    );
  }
}
