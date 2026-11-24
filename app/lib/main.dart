import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:material_ui/material_ui.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ismatpttxrsbqtravgkr.supabase.co',
    publishableKey: 'sb_publishable_Rdyho9ktQQDVFHiEZ3wwBQ_xFi1ST82',
  );

  runApp(const SocialGrowApp());
}


class SocialGrowApp extends StatelessWidget {
  const SocialGrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SocialGrow AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

class _Section {
  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _sections = <_Section>[
  _Section('Tableau de bord', Icons.dashboard_outlined),
  _Section('Création IA', Icons.auto_awesome_outlined),
  _Section('Calendrier', Icons.calendar_month_outlined),
  _Section('Statistiques', Icons.insights_outlined),
  _Section('Paramètres', Icons.settings_outlined),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final section = _sections[_index];
    return Scaffold(
      appBar: AppBar(title: Text(section.label)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Cette rubrique n\'est pas encore implémentée.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final s in _sections)
            NavigationDestination(icon: Icon(s.icon), label: s.label),
        ],
      ),
    );
  }
}
