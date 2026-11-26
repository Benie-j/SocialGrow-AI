import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/growth_plant.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/workspace_overview.dart';

class _Step {
  const _Step({
    required this.title,
    required this.hint,
    this.done = false,
    this.tab,
  });

  final String title;
  final String hint;
  final bool done;

  /// Onglet de l'application à ouvrir quand on touche l'étape.
  final int? tab;
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    this.userEmail,
    this.userName,
    this.userAvatarUrl,
    this.onNavigate,
    this.onSignOut,
    this.workspace = const WorkspaceState.idle(),
    this.onRetryWorkspace,
    this.onRefresh,
  });

  final String? userEmail;
  final String? userName;
  final String? userAvatarUrl;
  final ValueChanged<int>? onNavigate;
  final Future<void> Function()? onSignOut;

  /// État réel de l'espace de travail (profil, rôle, Pages connectées).
  final WorkspaceState workspace;
  final VoidCallback? onRetryWorkspace;

  /// Tirer pour actualiser ; absent = pas d'actualisation.
  final Future<void> Function()? onRefresh;

  /// La connexion d'une Page et la stratégie éditoriale se déduisent des
  /// données : les autres étapes restent à faire tant qu'aucune donnée ne
  /// prouve le contraire.
  static List<_Step> _stepsFor(WorkspaceOverview? overview) {
    final pageDone = overview?.hasConnectedPage ?? false;
    final pages = overview?.activePageCount ?? 0;
    final strategyDone = overview?.hasEditorialStrategy ?? false;
    final aiDone = overview?.hasAiActivity ?? false;

    return [
      const _Step(
        title: 'Compte connecté',
        hint: 'Tu es connecté avec Facebook.',
        done: true,
      ),
      _Step(
        title: 'Connecter ta Page Facebook',
        hint: pageDone
            ? _connectedHint(overview?.pageName, pages)
            : 'Choisis la Page à faire grandir.',
        done: pageDone,
      ),
      _Step(
        title: 'Définir ta stratégie éditoriale',
        hint: strategyDone
            ? 'Activité, piliers et voix de marque enregistrés.'
            : 'Activité, piliers de contenu et voix de marque.',
        done: strategyDone,
        tab: 4,
      ),
      _Step(
        title: 'Activer l’assistant IA',
        hint: aiDone
            ? 'Groq a déjà généré du contenu pour ton espace.'
            : 'Génère un premier texte dans le Studio : '
                'Groq prépare tes publications.',
        done: aiDone,
        tab: aiDone ? null : 1,
      ),
    ];
  }

  static String _connectedHint(String? name, int pages) {
    if (name == null) {
      return pages > 1 ? '$pages Pages connectées.' : '1 Page connectée.';
    }
    return pages > 1 ? '$name et ${pages - 1} autre(s) Page(s).' : name;
  }

  static String greetingFor(int hour) {
    if (hour >= 5 && hour < 12) return 'Bonjour';
    if (hour >= 12 && hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  /// Prénom affichable : nom complet si connu, sinon début de l'e-mail.
  static String? firstNameFrom(String? fullName, String? email) {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    final local = email?.split('@').first.trim();
    if (local == null || local.isEmpty) return null;
    final token = local
        .split(RegExp(r'[._+0-9-]+'))
        .firstWhere((part) => part.isNotEmpty, orElse: () => local);
    return token[0].toUpperCase() + token.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final overview = workspace.overview;
    final steps = _stepsFor(overview);
    final name = firstNameFrom(overview?.displayName ?? userName, userEmail);
    final avatarUrl = overview?.avatarUrl ?? userAvatarUrl;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final seed = (name ?? userEmail ?? '').trim();
    final initial = seed.isEmpty
        ? '•'
        : String.fromCharCode(seed.runes.first).toUpperCase();
    final refresh = onRefresh;

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 100),
      children: [
        SgReveal(
          child: _Header(
            greeting: greetingFor(DateTime.now().hour),
            name: name,
            initial: initial,
            avatarUrl: avatarUrl,
            onSignOut: onSignOut,
          ),
        ),
        if (workspace.status != WorkspaceStatus.idle) ...[
          const SizedBox(height: 14),
          SgReveal(
            order: 1,
            child: _WorkspaceBar(state: workspace, onRetry: onRetryWorkspace),
          ),
        ],
        const SizedBox(height: 18),
        SgReveal(order: 1, child: _GardenCard(steps: steps)),
        const SizedBox(height: 18),
        SgReveal(
          order: 2,
          child: _Timeline(steps: steps, onNavigate: onNavigate),
        ),
        const SizedBox(height: 22),
        SgReveal(
          order: 3,
          child: _StudioCard(onOpen: () => onNavigate?.call(1)),
        ),
        const SizedBox(height: 30),
        SgReveal(
          order: 4,
          child: Text('Ton espace', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 14),
        SgReveal(
          order: 4,
          child: _SpaceGrid(
            onNavigate: onNavigate,
            pageConnected: overview?.hasConnectedPage ?? false,
            pageName: overview?.pageName,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Ton assistant IA s’active dès la première génération réussie.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );

    if (refresh == null) return list;
    return RefreshIndicator(onRefresh: refresh, child: list);
  }
}

/// Espace de travail réel : nom, rôle, ou état de chargement / d'erreur.
class _WorkspaceBar extends StatelessWidget {
  const _WorkspaceBar({required this.state, required this.onRetry});

  final WorkspaceState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final overview = state.overview;

    final Widget leading;
    final Widget body;
    Widget? trailing;

    if (state.status == WorkspaceStatus.loading) {
      leading = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent),
      );
      body = Text(
        'Chargement de ton espace…',
        style: theme.textTheme.bodyMedium?.copyWith(color: p.textSecondary),
      );
    } else if (state.status == WorkspaceStatus.failed) {
      leading = Icon(Icons.cloud_off_outlined, color: p.accentWarm);
      body = Text(
        state.message ?? 'Impossible de charger ton espace.',
        style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
      );
      final retry = onRetry;
      if (retry != null) {
        trailing = TextButton(onPressed: retry, child: const Text('Réessayer'));
      }
    } else {
      leading = Icon(Icons.workspaces_outline, color: p.accent);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Espace de travail',
            style: theme.textTheme.labelSmall?.copyWith(
              color: p.textSecondary,
            ),
          ),
          Text(
            overview?.workspaceName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
      if (overview != null) {
        trailing = SgPill(label: overview.roleLabel, color: p.accent);
      }
    }

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(child: body),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.name,
    required this.initial,
    required this.avatarUrl,
    required this.onSignOut,
  });

  final String greeting;
  final String? name;
  final String initial;
  final String? avatarUrl;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final url = avatarUrl;
    final signOut = onSignOut;

    final avatar = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: SgPalette.lime,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.ink, width: 1.6),
        boxShadow: [
          if (!p.isDark)
            BoxShadow(
              color: p.ink,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: SgPalette.inkDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
              ),
            ),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name ?? 'Bienvenue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 40),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (signOut == null)
          avatar
        else
          PopupMenuButton<String>(
            tooltip: 'Mon compte',
            padding: EdgeInsets.zero,
            onSelected: (_) {
              signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Se déconnecter'),
                  ],
                ),
              ),
            ],
            child: avatar,
          ),
      ],
    );
  }
}

/// Carte héros : la plante pousse avec le nombre d'étapes terminées.
class _GardenCard extends StatelessWidget {
  const _GardenCard({required this.steps});

  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final done = steps.where((s) => s.done).length;
    final remaining = steps.length - done;
    final progress = done / steps.length;

    return GlassPanel(
      highlight: true,
      radius: 28,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 236,
          child: Stack(
            children: [
              Positioned(
                right: -14,
                bottom: -6,
                child: GrowthPlant(
                  size: 210,
                  growth: 0.2 + 0.8 * progress,
                ),
              ),
              Positioned(
                left: 20,
                top: 20,
                right: 150,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SgPill(
                      label: 'Ton jardin',
                      icon: Icons.spa_outlined,
                      color: p.accent,
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$done',
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -3,
                              height: 0.95,
                            ),
                          ),
                          TextSpan(
                            text: '/${steps.length}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Parcours de lancement',
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      remaining > 0
                          ? 'Encore $remaining étape${remaining > 1 ? 's' : ''} '
                              'avant ta première publication automatique.'
                          : 'Tout est prêt pour publier.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les étapes, reliées comme les nœuds d'une tige.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps, required this.onNavigate});

  final List<_Step> steps;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final navigate = onNavigate;
    final firstTodo = steps.indexWhere((s) => !s.done);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              step: steps[i],
              number: i + 1,
              isNext: i == firstTodo,
              isLast: i == steps.length - 1,
              nextDone: i + 1 < steps.length && steps[i + 1].done,
              onTap: steps[i].tab == null || navigate == null
                  ? null
                  : () => navigate(steps[i].tab!),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.isNext,
    required this.isLast,
    required this.nextDone,
    this.onTap,
  });

  final _Step step;
  final int number;
  final bool isNext;
  final bool isLast;
  final bool nextDone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    final Widget marker;
    if (step.done) {
      marker = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: SgPalette.lime,
          shape: BoxShape.circle,
          border: Border.all(color: p.ink, width: 1.6),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 18,
          color: SgPalette.inkDark,
        ),
      );
    } else {
      marker = Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isNext ? p.accent : p.glassBorder,
            width: isNext ? 2.2 : 1.4,
          ),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: isNext ? p.accent : p.textSecondary,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      );
    }

    final Widget trailing;
    if (step.done) {
      trailing = SgPill(label: 'Fait', color: p.success);
    } else if (onTap != null) {
      trailing = Icon(Icons.arrow_forward_rounded, color: p.accent);
    } else {
      trailing = const SgPill(label: 'Bientôt');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  marker,
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2.5,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: step.done && nextDone
                              ? p.accent
                              : p.glassBorder,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(alignment: Alignment.topCenter, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioCard extends StatelessWidget {
  const _StudioCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final radius = BorderRadius.circular(28);
    const ink = SgPalette.inkDark;

    return Container(
      decoration: BoxDecoration(
        color: SgPalette.lime,
        borderRadius: radius,
        border: Border.all(color: p.isDark ? SgPalette.lime : ink, width: 1.6),
        boxShadow: [
          if (!p.isDark)
            const BoxShadow(
              color: ink,
              offset: Offset(5, 5),
              blurRadius: 0,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -26,
              top: -22,
              child: Transform.rotate(
                angle: 0.25,
                child: Icon(
                  Icons.auto_awesome,
                  size: 170,
                  color: ink.withValues(alpha: 0.09),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 14, color: SgPalette.lime),
                        SizedBox(width: 4),
                        Text(
                          'INTELLIGENCE ARTIFICIELLE',
                          style: TextStyle(
                            color: SgPalette.lime,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Studio IA',
                    style: TextStyle(
                      color: ink,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Des idées, des textes et des variantes alignés sur '
                    'ta stratégie.',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: ink,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onOpen,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Découvrir le Studio',
                              style: TextStyle(
                                color: SgPalette.lime,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: SgPalette.lime,
                            ),
                          ],
                        ),
                      ),
                    ),
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

/// Grille décalée : deux colonnes de hauteurs alternées.
class _SpaceGrid extends StatelessWidget {
  const _SpaceGrid({
    required this.onNavigate,
    required this.pageConnected,
    this.pageName,
  });

  final ValueChanged<int>? onNavigate;
  final bool pageConnected;
  final String? pageName;

  static const double _tall = 214;
  static const double _short = 170;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final navigate = onNavigate;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _SpaceTile(
                height: _tall,
                icon: Icons.facebook,
                tint: p.accentCool,
                title: 'Page Facebook',
                subtitle: pageConnected
                    ? (pageName ?? 'Ta Page est prête à publier.')
                    : 'Connecte ta Page pour publier.',
                status: pageConnected
                    ? SgPill(label: 'Connectée', color: p.success)
                    : SgPill(label: 'À connecter', color: p.accentWarm),
              ),
              const SizedBox(height: 12),
              _SpaceTile(
                height: _short,
                icon: Icons.calendar_month,
                tint: p.accentWarm,
                title: 'Agenda',
                subtitle: 'Planifie tes posts.',
                status: SgPill(label: 'Disponible', color: p.success),
                onTap: navigate == null ? null : () => navigate(2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _SpaceTile(
                height: _short,
                icon: Icons.edit_note,
                tint: p.accent,
                title: 'Publications',
                subtitle: 'Tes contenus ici.',
                status: SgPill(label: 'Disponible', color: p.success),
                onTap: navigate == null ? null : () => navigate(1),
              ),
              const SizedBox(height: 12),
              _SpaceTile(
                height: _tall,
                icon: Icons.insights,
                tint: p.accent,
                title: 'Statistiques',
                subtitle: 'Mesure ta croissance, semaine après semaine.',
                status: SgPill(label: 'Disponible', color: p.success),
                onTap: navigate == null ? null : () => navigate(3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.height,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
  });

  final double height;
  final IconData icon;

  /// Couleur de l'icône ; la couleur d'accent par défaut si absente.
  final Color? tint;
  final String title;
  final String subtitle;
  final Widget status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final color = tint ?? p.textSecondary;

    return SizedBox(
      height: height,
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        radius: 22,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
                height: 1.3,
              ),
            ),
            const Spacer(),
            status,
          ],
        ),
      ),
    );
  }
}
