import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_pill.dart';

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
  });

  final String? userEmail;
  final String? userName;
  final String? userAvatarUrl;
  final ValueChanged<int>? onNavigate;
  final Future<void> Function()? onSignOut;

  static const _steps = [
    _Step(
      title: 'Compte connecté',
      hint: 'Tu es connecté avec Facebook.',
      done: true,
    ),
    _Step(
      title: 'Connecter ta Page Facebook',
      hint: 'Choisis la Page à faire grandir.',
    ),
    _Step(
      title: 'Définir ta stratégie éditoriale',
      hint: 'Fréquence, horaires, public et contenus.',
      tab: 4,
    ),
    _Step(
      title: 'Activer l’assistant IA',
      hint: 'Groq prépare tes publications.',
    ),
  ];

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
    final name = firstNameFrom(userName, userEmail);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final seed = (name ?? userEmail ?? '').trim();
    final initial = seed.isEmpty
        ? '•'
        : String.fromCharCode(seed.runes.first).toUpperCase();

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 28),
      children: [
        SgReveal(
          child: _Header(
            greeting: greetingFor(DateTime.now().hour),
            name: name,
            initial: initial,
            avatarUrl: userAvatarUrl,
            onSignOut: onSignOut,
          ),
        ),
        const SizedBox(height: 24),
        SgReveal(
          order: 1,
          child: _LaunchPath(steps: _steps, onNavigate: onNavigate),
        ),
        const SizedBox(height: 16),
        SgReveal(
          order: 2,
          child: _StudioCard(onOpen: () => onNavigate?.call(1)),
        ),
        const SizedBox(height: 28),
        SgReveal(
          order: 3,
          child: Text('Ton espace', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 14),
        SgReveal(order: 3, child: _SpaceGrid(onNavigate: onNavigate)),
        const SizedBox(height: 22),
        Text(
          'Les fonctions Facebook et Groq seront activées dans les '
          'prochaines étapes.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
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
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SgPalette.brand,
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: p.background,
        foregroundImage: url == null ? null : NetworkImage(url),
        onForegroundImageError: url == null ? null : (error, stackTrace) {},
        child: Text(
          initial,
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(name ?? 'Bienvenue', style: theme.textTheme.headlineMedium),
            ],
          ),
        ),
        if (signOut == null)
          avatar
        else
          PopupMenuButton<String>(
            tooltip: 'Mon compte',
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

class _LaunchPath extends StatelessWidget {
  const _LaunchPath({required this.steps, required this.onNavigate});

  final List<_Step> steps;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final done = steps.where((s) => s.done).length;
    final remaining = steps.length - done;
    final navigate = onNavigate;

    return GlassPanel(
      highlight: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                value: done / steps.length,
                size: 104,
                stroke: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$done/${steps.length}',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      'étapes',
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parcours de lancement',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      remaining > 0
                          ? 'Encore $remaining étape${remaining > 1 ? 's' : ''} '
                              'avant ta première publication automatique.'
                          : 'Tout est prêt pour publier.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              step: steps[i],
              number: i + 1,
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
  const _StepRow({required this.step, required this.number, this.onTap});

  final _Step step;
  final int number;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    final marker = step.done
        ? Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SgPalette.brand,
            ),
            child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
          )
        : Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.glassBorder, width: 1.5),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: p.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          );

    final Widget trailing;
    if (step.done) {
      trailing = SgPill(label: 'Fait', color: p.success);
    } else if (onTap != null) {
      trailing = Icon(Icons.chevron_right, color: p.textSecondary);
    } else {
      trailing = const SgPill(label: 'Bientôt');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            marker,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _StudioCard extends StatelessWidget {
  const _StudioCard({required this.onOpen});

  final VoidCallback onOpen;

  Widget _circle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final radius = BorderRadius.circular(28);

    return Container(
      decoration: BoxDecoration(
        gradient: SgPalette.brand,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.38),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned(right: -44, top: -44, child: _circle(170, 0.10)),
            Positioned(right: 36, bottom: -56, child: _circle(120, 0.08)),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Studio IA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Génère des idées, des textes et des variantes alignés '
                    'sur ta stratégie.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onOpen,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Découvrir le Studio',
                              style: TextStyle(
                                color: Color(0xFF4B2BD6),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: Color(0xFF4B2BD6),
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

class _SpaceGrid extends StatelessWidget {
  const _SpaceGrid({required this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final navigate = onNavigate;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SpaceTile(
                  icon: Icons.facebook,
                  title: 'Page Facebook',
                  subtitle: 'Connecte ta Page pour publier.',
                  status: SgPill(label: 'À connecter', color: p.accentWarm),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: _SpaceTile(
                  icon: Icons.edit_note,
                  title: 'Publications',
                  subtitle: 'Tes contenus au même endroit.',
                  status: SgPill(label: 'Bientôt'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SpaceTile(
                  icon: Icons.calendar_month,
                  title: 'Agenda',
                  subtitle: 'Planifie tes prochains posts.',
                  status: const SgPill(label: 'Bientôt'),
                  onTap: navigate == null ? null : () => navigate(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SpaceTile(
                  icon: Icons.insights,
                  title: 'Statistiques',
                  subtitle: 'Mesure ta croissance.',
                  status: const SgPill(label: 'Bientôt'),
                  onTap: navigate == null ? null : () => navigate(3),
                ),
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
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      radius: 22,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: p.accent, size: 22),
          ),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
              height: 1.35,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          status,
        ],
      ),
    );
  }
}
