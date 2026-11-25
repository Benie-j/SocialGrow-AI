import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_gradient_button.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/agenda.dart';
import '../../../data/agenda_repository.dart';
import '../../../data/publication_settings_repository.dart' show describeError;
import 'reschedule_sheet.dart';

String statusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Brouillon';
    case 'pending_approval':
      return 'À valider';
    case 'scheduled':
      return 'Programmé';
    case 'publishing':
      return 'En cours';
    case 'published':
      return 'Publié';
    case 'failed':
      return 'Échec';
    case 'cancelled':
      return 'Annulé';
    default:
      return status;
  }
}

Color statusColor(SgPalette p, String status) {
  switch (status) {
    case 'published':
      return p.success;
    case 'failed':
      return p.accentWarm;
    case 'scheduled':
      return p.accent;
    case 'pending_approval':
    case 'publishing':
      return p.accentCool;
    default:
      return p.textSecondary;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'image':
      return Icons.image_outlined;
    case 'video':
      return Icons.videocam_outlined;
    case 'link':
      return Icons.link;
    case 'carousel':
      return Icons.view_carousel_outlined;
    default:
      return Icons.notes;
  }
}

/// Agenda : les publications de la semaine, jour par jour, et les créneaux
/// encore libres selon la stratégie de publication de l'utilisateur.
class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    this.repository,
    this.onOpenStudio,
    this.now = DateTime.now,
  });

  /// Sans dépôt, l'agenda s'affiche vide (aucune donnée n'est inventée).
  final AgendaRepository? repository;
  final VoidCallback? onOpenStudio;

  /// Horloge injectable pour les tests.
  final DateTime Function() now;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _Entry {
  const _Entry.post(AgendaPost this.post) : slot = null;
  const _Entry.slot(AgendaSlot this.slot) : post = null;

  final AgendaPost? post;
  final AgendaSlot? slot;

  DateTime get time => post?.when ?? slot!.at;
}

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _weekStart;
  late DateTime _selected;
  AgendaContext? _context;
  List<AgendaPost> _posts = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(widget.now());
    _selected = today;
    _weekStart = mondayOf(today);
    if (widget.repository != null) {
      _loading = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final repository = widget.repository;
    if (repository == null) return;
    final request = ++_request;

    try {
      final context = _context ?? await repository.loadContext();
      final posts = await repository.loadRange(
        context.workspaceId,
        _weekStart,
        addDays(_weekStart, 7),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _context = context;
        _posts = posts;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _reload() {
    setState(() {
      _loading = true;
      _error = null;
    });
    return _fetch();
  }

  void _goTo(DateTime selected) {
    final sameWeek = mondayOf(selected) == _weekStart;
    setState(() => _selected = selected);
    if (!sameWeek) {
      _weekStart = mondayOf(selected);
      _reload();
    }
  }

  void _shiftWeek(int weeks) => _goTo(addDays(_selected, 7 * weeks));

  void _goToday() => _goTo(dateOnly(widget.now()));

  List<AgendaPost> _postsOn(DateTime day) => _posts
      .where((p) => p.when != null && sameDay(p.when!, day))
      .toList();

  List<_Entry> _entriesFor(DateTime day) {
    final context = _context;
    final entries = <_Entry>[
      for (final post in _postsOn(day)) _Entry.post(post),
    ];
    if (context != null && !_loading && _error == null) {
      for (final slot in freeSlotsFor(
        day,
        settings: context.settings,
        posts: _posts,
        now: widget.now(),
      )) {
        entries.add(_Entry.slot(slot));
      }
    }
    entries.sort((a, b) => a.time.compareTo(b.time));
    return entries;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reschedule(AgendaPost post) async {
    final repository = widget.repository;
    final agenda = _context;
    if (repository == null || agenda == null) return;

    final chosen = await showRescheduleSheet(
      context: context,
      post: post,
      agenda: agenda,
      repository: repository,
      now: widget.now,
    );
    if (chosen == null || !mounted) return;

    try {
      await repository.reschedule(
        workspaceId: agenda.workspaceId,
        postId: post.id,
        at: chosen,
      );
      if (!mounted) return;
      _toast('Publication reprogrammée.');
      setState(() {
        _selected = dateOnly(chosen);
        _weekStart = mondayOf(_selected);
      });
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _toast(describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final today = dateOnly(widget.now());
    final agenda = _context;
    final entries = _entriesFor(_selected);
    final postCount = _postsOn(_selected).length;

    final Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      content = GlassPanel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: p.accentWarm),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
            TextButton(onPressed: _reload, child: const Text('Réessayer')),
          ],
        ),
      );
    } else if (entries.isEmpty) {
      content = _EmptyDay(
        isPast: _selected.isBefore(today),
        canCreate: (agenda?.canEdit ?? false) && widget.onOpenStudio != null,
        onOpenStudio: widget.onOpenStudio,
      );
    } else {
      content = Column(
        children: [
          for (final entry in entries) ...[
            if (entry.post != null)
              _PostTile(
                post: entry.post!,
                pageName: agenda != null && agenda.pageNames.length > 1
                    ? agenda.pageNames[entry.post!.facebookPageId]
                    : null,
                onReschedule: (agenda?.canEdit ?? false) &&
                        entry.post!.canReschedule
                    ? () => _reschedule(entry.post!)
                    : null,
              )
            else
              _SlotTile(
                slot: entry.slot!,
                onTap: (agenda?.canEdit ?? false) ? widget.onOpenStudio : null,
              ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 100),
      children: [
        SgReveal(
          child: SgPageHeader(
            title: 'Agenda',
            subtitle: 'Tes publications, jour après jour.',
            trailing: _selected == today && mondayOf(today) == _weekStart
                ? null
                : TextButton(
                    onPressed: _goToday,
                    child: const Text('Aujourd’hui'),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        SgReveal(
          order: 1,
          child: _WeekCard(
            weekStart: _weekStart,
            selected: _selected,
            today: today,
            posts: _posts,
            onPrevious: () => _shiftWeek(-1),
            onNext: () => _shiftWeek(1),
            onSelect: (day) => setState(() => _selected = day),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          FrDate.dayLong(_selected),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 2),
        Text(
          postCount == 0
              ? 'Aucune publication'
              : postCount == 1
                  ? '1 publication'
                  : '$postCount publications',
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 14),
        content,
      ],
    );

    return RefreshIndicator(
      onRefresh: widget.repository == null ? () async {} : _fetch,
      child: list,
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.weekStart,
    required this.selected,
    required this.today,
    required this.posts,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final DateTime weekStart;
  final DateTime selected;
  final DateTime today;
  final List<AgendaPost> posts;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassPanel(
      highlight: true,
      radius: 24,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Semaine précédente',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  FrDate.weekRange(weekStart),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Semaine suivante',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayChip(
                    day: addDays(weekStart, i),
                    selected: sameDay(addDays(weekStart, i), selected),
                    isToday: sameDay(addDays(weekStart, i), today),
                    posts: posts
                        .where(
                          (p) =>
                              p.status != 'cancelled' &&
                              p.when != null &&
                              sameDay(p.when!, addDays(weekStart, i)),
                        )
                        .toList(),
                    onTap: () => onSelect(addDays(weekStart, i)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.posts,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final List<AgendaPost> posts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    const ink = SgPalette.inkDark;
    final label = selected ? ink : p.textSecondary;
    final number = selected ? ink : p.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${FrDate.dayLong(day)}, ${posts.length} publication(s)',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? SgPalette.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? (p.isDark ? SgPalette.lime : ink)
                    : isToday
                        ? p.accent
                        : Colors.transparent,
                width: selected ? 1.6 : 1.4,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FrDate.weekdayShort(day),
                  style: TextStyle(
                    color: label,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: number,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final post in posts.take(3))
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? ink
                                : statusColor(p, post.status),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn(this.at, {this.muted = false});

  final DateTime at;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);

    return SizedBox(
      width: 56,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          FrDate.time(at),
          style: TextStyle(
            color: muted ? p.textSecondary : p.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.pageName,
    required this.onReschedule,
  });

  final AgendaPost post;
  final String? pageName;
  final VoidCallback? onReschedule;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final color = statusColor(p, post.status);
    final showBody = post.title != null && post.body.trim().isNotEmpty;
    final name = pageName;
    final error = post.errorMessage;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimeColumn(post.when!),
        Expanded(
          child: GlassPanel(
            radius: 20,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SgPill(label: statusLabel(post.status), color: color),
                    const Spacer(),
                    Icon(
                      _typeIcon(post.contentType),
                      size: 18,
                      color: p.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  post.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (showBody) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.body.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                if (name != null && name.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.facebook, size: 15, color: p.accentCool),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (post.status == 'failed' && error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.accentWarm,
                      height: 1.35,
                    ),
                  ),
                ],
                if (onReschedule != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onReschedule,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Reprogrammer'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.onTap});

  final AgendaSlot slot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(20);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimeColumn(slot.at, muted: true),
        Expanded(
          child: Material(
            color: p.accent.withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: p.accent.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Créneau libre',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'Selon ta stratégie de publication',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onTap != null)
                      Icon(Icons.arrow_forward_rounded, color: p.accent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.isPast,
    required this.canCreate,
    required this.onOpenStudio,
  });

  final bool isPast;
  final bool canCreate;
  final VoidCallback? onOpenStudio;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.event_available_outlined, color: p.accent),
          ),
          const SizedBox(height: 14),
          Text(
            isPast ? 'Aucune publication ce jour' : 'Rien de prévu ce jour',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isPast
                ? 'Ce jour est passé.'
                : 'Crée une publication dans le Studio pour la planifier.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (!isPast && canCreate) ...[
            const SizedBox(height: 18),
            SgGradientButton(
              label: 'Créer dans le Studio',
              icon: Icons.auto_awesome,
              onPressed: onOpenStudio,
            ),
          ],
        ],
      ),
    );
  }
}
