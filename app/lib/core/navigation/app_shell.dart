import 'package:material_ui/material_ui.dart';

import '../../data/publication_settings_repository.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/preview/presentation/feature_preview_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../theme/sg_palette.dart';
import '../widgets/aurora_background.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onSignOut,
    this.userEmail,
    this.userName,
    this.userAvatarUrl,
    this.settingsRepository,
  });

  final Future<void> Function() onSignOut;
  final String? userEmail;
  final String? userName;
  final String? userAvatarUrl;

  /// Injectable pour les tests ; par défaut, Supabase.
  final PublicationSettingsRepository? settingsRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    _Destination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Accueil',
    ),
    _Destination(
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: 'Studio',
    ),
    _Destination(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Agenda',
    ),
    _Destination(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: 'Stats',
    ),
    _Destination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Réglages',
    ),
  ];

  void _select(int value) {
    if (value == _index) return;
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        userEmail: widget.userEmail,
        userName: widget.userName,
        userAvatarUrl: widget.userAvatarUrl,
        onNavigate: _select,
        onSignOut: widget.onSignOut,
      ),
      const FeaturePreviewPage(
        title: 'Studio IA',
        description: 'Ton atelier de création pour ta Page Facebook.',
        icon: Icons.auto_awesome,
        highlights: [
          FeatureHighlight(
            icon: Icons.lightbulb_outline,
            title: 'Idées de publications',
            text: 'Des angles adaptés à ton audience et à ta stratégie.',
          ),
          FeatureHighlight(
            icon: Icons.edit_note,
            title: 'Textes prêts à publier',
            text: 'Une rédaction guidée qui respecte ton ton de marque.',
          ),
          FeatureHighlight(
            icon: Icons.view_carousel_outlined,
            title: 'Variantes',
            text: 'Plusieurs versions d’un même post pour choisir la meilleure.',
          ),
        ],
      ),
      const FeaturePreviewPage(
        title: 'Agenda',
        description: 'Organise et retrouve tes prochaines publications.',
        icon: Icons.calendar_month,
        highlights: [
          FeatureHighlight(
            icon: Icons.edit_calendar_outlined,
            title: 'Vue de la semaine',
            text: 'Toutes tes publications planifiées d’un coup d’œil.',
          ),
          FeatureHighlight(
            icon: Icons.schedule,
            title: 'Créneaux alignés',
            text: 'Des horaires cohérents avec tes réglages de publication.',
          ),
          FeatureHighlight(
            icon: Icons.swap_horiz,
            title: 'Reprogrammation simple',
            text: 'Déplace une publication sans tout refaire.',
          ),
        ],
      ),
      const FeaturePreviewPage(
        title: 'Statistiques',
        description: 'Les performances de ta Page, au même endroit.',
        icon: Icons.insights,
        highlights: [
          FeatureHighlight(
            icon: Icons.query_stats,
            title: 'Performances réelles',
            text: 'Portée et engagement de ta Page, issus de Meta.',
          ),
          FeatureHighlight(
            icon: Icons.leaderboard_outlined,
            title: 'Meilleurs contenus',
            text: 'Ce qui fonctionne vraiment auprès de ta communauté.',
          ),
          FeatureHighlight(
            icon: Icons.trending_up,
            title: 'Évolution',
            text: 'Suis ta croissance semaine après semaine.',
          ),
        ],
      ),
      SettingsPage(
        repository: widget.settingsRepository,
        onSignOut: widget.onSignOut,
      ),
    ];

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
        bottomNavigationBar: _FloatingNav(
          destinations: _destinations,
          selectedIndex: _index,
          onSelected: _select,
        ),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: p.navFill,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: p.glassBorder),
            boxShadow: [
              BoxShadow(
                color: p.isDark
                    ? const Color(0x66000000)
                    : const Color(0x1F1B1F4B),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < destinations.length; i++)
                _NavItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    return Tooltip(
      message: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 10,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            gradient: selected ? SgPalette.brand : null,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 24,
                color: selected ? Colors.white : p.textSecondary,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          destination.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
