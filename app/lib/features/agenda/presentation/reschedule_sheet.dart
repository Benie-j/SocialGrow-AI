import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/sg_gradient_button.dart';
import '../../../data/agenda.dart';
import '../../../data/agenda_repository.dart';

/// Feuille de reprogrammation : choisir un jour puis un horaire autorisé.
/// Renvoie la nouvelle date/heure, ou null si l'utilisateur annule.
Future<DateTime?> showRescheduleSheet({
  required BuildContext context,
  required AgendaPost post,
  required AgendaContext agenda,
  required AgendaRepository repository,
  required DateTime Function() now,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RescheduleSheet(
      post: post,
      agenda: agenda,
      repository: repository,
      now: now,
    ),
  );
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({
    required this.post,
    required this.agenda,
    required this.repository,
    required this.now,
  });

  final AgendaPost post;
  final AgendaContext agenda;
  final AgendaRepository repository;
  final DateTime Function() now;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  static const _horizonDays = 14;

  late final DateTime _today = dateOnly(widget.now());
  late DateTime _day;
  DateTime? _time;
  List<AgendaPost> _dayPosts = const [];
  bool _loadingDay = true;
  bool _dayFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final current = widget.post.scheduledAt;
    final currentDay = current == null ? _today : dateOnly(current);
    _day = currentDay.isBefore(_today) ||
            currentDay.isAfter(addDays(_today, _horizonDays - 1))
        ? _today
        : currentDay;
    _loadDay();
  }

  Future<void> _loadDay() async {
    final request = ++_request;
    setState(() {
      _loadingDay = true;
      _dayFailed = false;
    });
    try {
      final posts = await widget.repository.loadRange(
        widget.agenda.workspaceId,
        _day,
        addDays(_day, 1),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _dayPosts = posts;
        _loadingDay = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _dayPosts = const [];
        _loadingDay = false;
        _dayFailed = true;
      });
    }
  }

  void _selectDay(DateTime day) {
    if (sameDay(day, _day)) return;
    setState(() {
      _day = day;
      _time = null;
    });
    _loadDay();
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final settings = widget.agenda.settings;
    final now = widget.now();
    final times = candidateTimes(_day, settings: settings);
    final preferred = settings.preferredTimes.toSet();
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final selected = _time;

    return Container(
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: p.glassBorder),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: p.glassBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reprogrammer', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.post.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text('Jour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _horizonDays,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final day = addDays(_today, i);
                  return _PickChip(
                    selected: sameDay(day, _day),
                    onTap: () => _selectDay(day),
                    width: 56,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          FrDate.weekdayShort(day),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${day.day}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Text('Horaire', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (_loadingDay)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (times.isEmpty)
              Text(
                'Aucun horaire autorisé ce jour. Vérifie tes fenêtres '
                'horaires dans les paramètres de publication.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in times)
                    _timeChip(
                      t,
                      enabled: t.isAfter(now) &&
                          !conflictsWithPosts(
                            t,
                            _dayPosts,
                            settings.minIntervalMinutes,
                            excludeId: widget.post.id,
                          ),
                      preferred: preferred.contains(FrDate.time(t)),
                      selected: selected != null && selected == t,
                    ),
                ],
              ),
            if (!_loadingDay && _dayFailed) ...[
              const SizedBox(height: 10),
              Text(
                'Impossible de vérifier les autres publications de ce jour.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.accentWarm,
                ),
              ),
            ] else if (!_loadingDay && times.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Les horaires grisés sont passés ou trop proches d’une autre '
                'publication (${settings.minIntervalMinutes} min minimum). '
                'Le contour marque les horaires de ta stratégie.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SgGradientButton(
              label: selected == null
                  ? 'Choisis un horaire'
                  : 'Reprogrammer · ${FrDate.dayCompact(selected)} à '
                      '${FrDate.time(selected)}',
              icon: Icons.swap_horiz,
              onPressed:
                  selected == null ? null : () => Navigator.pop(context, selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeChip(
    DateTime t, {
    required bool enabled,
    required bool preferred,
    required bool selected,
  }) {
    return _PickChip(
      selected: selected,
      enabled: enabled,
      preferred: preferred,
      onTap: enabled ? () => setState(() => _time = t) : null,
      child: Text(
        FrDate.time(t),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.selected,
    required this.onTap,
    required this.child,
    this.enabled = true,
    this.preferred = false,
    this.width,
  });

  final bool selected;
  final bool enabled;
  final bool preferred;
  final VoidCallback? onTap;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    const ink = SgPalette.inkDark;
    final radius = BorderRadius.circular(14);

    final Color foreground;
    if (selected) {
      foreground = ink;
    } else if (!enabled) {
      foreground = p.textSecondary.withValues(alpha: 0.45);
    } else {
      foreground = p.textPrimary;
    }

    return Material(
      color: selected ? SgPalette.lime : p.glass,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected
              ? (p.isDark ? SgPalette.lime : ink)
              : preferred && enabled
                  ? p.accent
                  : p.glassBorder,
          width: selected || (preferred && enabled) ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          alignment: width == null ? null : Alignment.center,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}
