import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/facebook_connection.dart';
import '../../data/notifications_repository.dart';
import '../../data/publication_settings_repository.dart';
import '../../data/agenda_repository.dart';
import '../../data/stats_repository.dart';
import '../../data/workspace_overview.dart';
import '../../data/workspace_repository.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/agenda/presentation/agenda_page.dart';
import '../../features/stats/presentation/stats_page.dart';
import '../../features/studio/presentation/studio_page.dart';
import '../../features/push/presentation/push_prompt.dart';
import '../../features/settings/presentation/notifications_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../push/push_service.dart';
import '../theme/sg_palette.dart';
import '../widgets/sg_background.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onSignOut,
    this.userEmail,
    this.userName,
    this.userAvatarUrl,
    this.settingsRepository,
    this.workspaceRepository,
    this.facebookRepository,
    this.studioPage,
    this.agendaRepository,
    this.statsRepository,
    this.pushService,
    this.notificationsRepository,
  });

  final Future<void> Function() onSignOut;
  final String? userEmail;
  final String? userName;
  final String? userAvatarUrl;
  final Widget? studioPage;

  /// Données de l'agenda ; sans dépôt (tests), l'agenda s'affiche vide.
  final AgendaRepository? agendaRepository;

  /// Données de l'onglet Statistiques ; sans dépôt (tests), il reste vide.
  final StatsRepository? statsRepository;
  /// Injectable pour les tests ; par défaut, Supabase.
  final PublicationSettingsRepository? settingsRepository;

  /// Injectable pour les tests ; sans dépôt, aucun espace n'est chargé.
  final WorkspaceRepository? workspaceRepository;

  /// Injectable pour les tests ; sans dépôt, « Connexion Facebook » reste
  /// indisponible.
  final FacebookConnectionRepository? facebookRepository;

  /// Alertes instantanées (push) ; sans service (tests), rien n'est proposé.
  final PushService? pushService;

  /// Injectable pour les tests ; par défaut, Supabase.
  final NotificationsRepository? notificationsRepository;

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
  WorkspaceState _workspace = const WorkspaceState.idle();
  StreamSubscription<void>? _opensSubscription;

  @override
  void initState() {
    super.initState();

    final push = widget.pushService;
    if (push != null) {
      _opensSubscription = push.opens.listen((_) => _openNotifications());
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPush(push));
    }
    if (widget.workspaceRepository != null) {
      _workspace = const WorkspaceState.loading();
      _fetchWorkspace();
    }
  }

  Future<void> _fetchWorkspace() async {
    final repository = widget.workspaceRepository;
    if (repository == null) return;

    try {
      final overview = await repository.load();
      if (!mounted) return;
      setState(() => _workspace = WorkspaceState.ready(overview));
    } catch (error) {
      if (!mounted) return;
      setState(() => _workspace = WorkspaceState.failed(describeError(error)));
    }
  }

  /// Rechargement après une erreur : on repasse d'abord par l'état « chargement ».
  Future<void> _retryWorkspace() async {
    if (widget.workspaceRepository == null) return;
    setState(() => _workspace = const WorkspaceState.loading());
    await _fetchWorkspace();
  }

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

  @override
  void dispose() {
    _opensSubscription?.cancel();
    super.dispose();
  }

  /// Au démarrage : enregistre le téléphone s'il est déjà autorisé, ouvre les
  /// notifications si l'appli a été lancée par un tap, sinon propose
  /// d'activer les alertes instantanées.
  Future<void> _startPush(PushService push) async {
    await push.syncIfEnabled();
    if (!mounted) return;

    if (push.takePendingOpen()) {
      _openNotifications();
      return;
    }
    if (await push.shouldPrompt()) {
      if (!mounted) return;
      await showPushPrompt(context, push);
    }
  }

  void _openNotifications() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(
          repository: widget.notificationsRepository,
          pushService: widget.pushService,
        ),
      ),
    );
  }

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
        workspace: _workspace,
        onRetryWorkspace: _retryWorkspace,
        onRefresh: _fetchWorkspace,
        onNavigate: _select,
        onSignOut: widget.onSignOut,
      ),
      widget.studioPage ?? const StudioPage(),
      AgendaPage(
        repository: widget.agendaRepository,
        onOpenStudio: () => _select(1),
      ),
      StatsPage(repository: widget.statsRepository),
      SettingsPage(
        repository: widget.settingsRepository,
        onSignOut: widget.onSignOut,
        facebookRepository: widget.facebookRepository,
        workspace: _workspace.overview,
        onWorkspaceChanged: _fetchWorkspace,
        notificationsRepository: widget.notificationsRepository,
        pushService: widget.pushService,
      ),
    ];

    return SgBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
        bottomNavigationBar: _Dock(
          destinations: _destinations,
          selectedIndex: _index,
          onSelected: _select,
        ),
      ),
    );
  }
}

/// Barre de navigation : un dock d'encre dont la pastille citron glisse
/// d'une rubrique à l'autre.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _height = 68;
  static const double _inset = 6;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: p.navFill,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: p.isDark ? p.glassBorder : SgPalette.inkDark,
            ),
            boxShadow: [
              BoxShadow(
                color: p.isDark
                    ? const Color(0x99000000)
                    : const Color(0x40111611),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  (constraints.maxWidth - _inset * 2) / destinations.length;

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutBack,
                    left: _inset + itemWidth * selectedIndex,
                    top: 8,
                    width: itemWidth,
                    height: _height - 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: SgPalette.lime,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _inset),
                      child: Row(
                        children: [
                          for (var i = 0; i < destinations.length; i++)
                            Expanded(
                              child: _DockItem(
                                destination: destinations[i],
                                selected: i == selectedIndex,
                                onTap: () => onSelected(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 23,
                color: selected
                    ? SgPalette.inkDark
                    : const Color(0xFFAAB5A6),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          destination.label,
                          style: const TextStyle(
                            color: SgPalette.inkDark,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.1,
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
