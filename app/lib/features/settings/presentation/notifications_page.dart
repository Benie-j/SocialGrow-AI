import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/push_service.dart';
import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/notifications.dart';
import '../../../data/notifications_repository.dart';
import '../../../data/publication_settings_repository.dart';
import 'settings_widgets.dart';

/// Écran « Notifications » : alertes choisies par l'utilisateur et historique
/// réel des notifications de l'espace de travail.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.repository, this.pushService});

  /// Injectable pour les tests ; par défaut, Supabase.
  final NotificationsRepository? repository;

  /// Alertes instantanées ; sans service, la carte n'est pas affichée.
  final PushService? pushService;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationsRepository _repo;

  NotificationsOverview? _overview;
  Object? _loadError;
  bool _loading = true;
  bool _markingAll = false;
  PushStatus? _pushStatus;
  bool _pushBusy = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ??
        SupabaseNotificationsRepository(Supabase.instance.client);
    _load();
    _loadPushStatus();
  }

  Future<void> _loadPushStatus() async {
    final service = widget.pushService;
    if (service == null) return;
    try {
      final status = await service.status();
      if (!mounted) return;
      setState(() => _pushStatus = status);
    } catch (_) {
      // La carte reste masquée si l'état est inconnu.
    }
  }

  Future<void> _enablePush() async {
    final service = widget.pushService;
    if (service == null) return;
    setState(() => _pushBusy = true);
    try {
      final status = await service.enable();
      if (!mounted) return;
      setState(() {
        _pushStatus = status;
        _pushBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pushBusy = false);
      _toast('Impossible d’activer les alertes pour le moment.');
    }
  }

  Future<void> _load() async {
    try {
      final overview = await _repo.load();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Applique tout de suite, puis revient en arrière si l'enregistrement échoue.
  Future<void> _setPreferences(NotificationPreferences next) async {
    final overview = _overview;
    if (overview == null) return;
    final previous = overview.preferences;

    setState(() => _overview = overview.copyWith(preferences: next));
    try {
      await _repo.savePreferences(overview.workspaceId, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _overview = _overview?.copyWith(preferences: previous));
      _toast(describeError(error));
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    final overview = _overview;
    if (overview == null || !notification.isUnread) return;
    final now = DateTime.now();

    setState(() {
      _overview = overview.copyWith(
        items: [
          for (final item in overview.items)
            item.id == notification.id ? item.markedRead(now) : item,
        ],
      );
    });
    try {
      await _repo.markRead(notification.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _overview = overview);
      _toast(describeError(error));
    }
  }

  Future<void> _markAllRead() async {
    final overview = _overview;
    if (overview == null || overview.unreadCount == 0) return;
    final now = DateTime.now();

    setState(() => _markingAll = true);
    try {
      await _repo.markAllRead(overview.workspaceId);
      if (!mounted) return;
      setState(() {
        _markingAll = false;
        _overview = overview.copyWith(
          items: [for (final item in overview.items) item.markedRead(now)],
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      _toast(describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (overview == null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                describeError(_loadError ?? 'inconnue'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: _buildContent(context, overview),
      );
    }

    final unread = overview?.unreadCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: const Text('Tout marquer comme lu'),
            ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context, NotificationsOverview overview) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final prefs = overview.preferences;
    final now = DateTime.now();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 28),
      children: [
        if (_pushStatus != null && _pushStatus != PushStatus.unavailable) ...[
          _PushCard(
            status: _pushStatus!,
            busy: _pushBusy,
            onEnable: _enablePush,
          ),
          const SizedBox(height: 14),
        ],
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alertes', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Choisis ce qui mérite de t’être signalé dans cet espace.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              // Les ListTile des interrupteurs ont besoin d'un Material sous
              // le fond de la carte, sinon leurs effets seraient masqués.
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                SwitchRow(
                  label: 'Publication réussie',
                  subtitle: 'Quand un post est publié sur ta Page.',
                  value: prefs.publishSuccess,
                  onChanged: (v) =>
                      _setPreferences(prefs.copyWith(publishSuccess: v)),
                ),
                SwitchRow(
                  label: 'Échec de publication',
                  subtitle: 'Quand une publication n’a pas pu partir.',
                  value: prefs.publishFailure,
                  onChanged: (v) =>
                      _setPreferences(prefs.copyWith(publishFailure: v)),
                ),
                SwitchRow(
                  label: 'Brouillon IA prêt',
                  subtitle: 'Quand JUN AI prépare un brouillon pour toi.',
                  value: prefs.aiDraftReady,
                  onChanged: (v) =>
                      _setPreferences(prefs.copyWith(aiDraftReady: v)),
                ),
                SwitchRow(
                  label: 'Problème Facebook',
                  subtitle: 'Connexion expirée ou Page inaccessible.',
                  value: prefs.facebookIssue,
                  onChanged: (v) =>
                      _setPreferences(prefs.copyWith(facebookIssue: v)),
                ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text('Récentes', style: theme.textTheme.titleLarge),
            ),
            if (overview.unreadCount > 0)
              SgPill(
                label: overview.unreadCount > 1
                    ? '${overview.unreadCount} non lues'
                    : '1 non lue',
                color: p.accent,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (overview.items.isEmpty)
          _EmptyState(color: p.textSecondary)
        else
          for (final item in overview.items) ...[
            _NotificationTile(
              notification: item,
              when: relativeTime(item.createdAt, now),
              onTap: () => _markRead(item),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 36, color: color),
          const SizedBox(height: 10),
          Text(
            'Aucune notification pour le moment.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tes alertes de publication apparaîtront ici.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.when,
    required this.onTap,
  });

  final AppNotification notification;
  final String when;
  final VoidCallback onTap;

  static IconData _icon(String kind) {
    switch (kind) {
      case NotificationKinds.publishSuccess:
        return Icons.check_circle_outline;
      case NotificationKinds.publishFailure:
        return Icons.error_outline;
      case NotificationKinds.aiDraftReady:
        return Icons.auto_awesome;
      case NotificationKinds.facebookIssue:
        return Icons.link_off;
      default:
        return Icons.notifications_none;
    }
  }

  static Color _color(String kind, SgPalette p) {
    switch (kind) {
      case NotificationKinds.publishSuccess:
        return p.success;
      case NotificationKinds.publishFailure:
      case NotificationKinds.facebookIssue:
        return p.accentWarm;
      case NotificationKinds.aiDraftReady:
        return p.accent;
      default:
        return p.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final color = _color(notification.kind, p);
    final body = notification.body;
    final unread = notification.isUnread;

    return GlassPanel(
      onTap: unread ? onTap : null,
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_icon(notification.kind), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: unread ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  when,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (unread)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 8),
              child: Container(
                key: const ValueKey('unread-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alertes instantanées sur ce téléphone : état, activation et conseils.
class _PushCard extends StatelessWidget {
  const _PushCard({
    required this.status,
    required this.busy,
    required this.onEnable,
  });

  final PushStatus status;
  final bool busy;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final enabled = status == PushStatus.enabled;

    final String message;
    switch (status) {
      case PushStatus.enabled:
        message = 'Tu recevras chaque alerte sur ce téléphone, même écran '
            'verrouillé ou application fermée.';
      case PushStatus.denied:
        message = 'Les notifications sont désactivées pour JUN AI. Active-les '
            'dans Réglages Android › Applications › JUN AI › Notifications.';
      case PushStatus.notDetermined:
      case PushStatus.unavailable:
        message = 'Reçois chaque alerte sur ton téléphone, même écran '
            'verrouillé ou application fermée.';
    }

    return GlassPanel(
      highlight: !enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: enabled ? p.success : p.accentWarm,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Alertes instantanées',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (enabled) SgPill(label: 'Activées', color: p.success),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
              height: 1.4,
            ),
          ),
          if (!enabled) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : onEnable,
              child: Text(
                status == PushStatus.denied
                    ? 'Réessayer'
                    : 'Activer les alertes instantanées',
              ),
            ),
          ],
          if (enabled) ...[
            const SizedBox(height: 6),
            Material(
              type: MaterialType.transparency,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Rien ne s’affiche ?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Text(
                    'Certains téléphones (Xiaomi, Tecno, Infinix, Oppo, '
                    'Huawei…) ferment les applications en arrière-plan. '
                    'Dans Réglages › Applications › JUN AI, autorise le '
                    'démarrage automatique et mets la batterie sur « Sans '
                    'restriction ».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            ),
          ],
        ],
      ),
    );
  }
}
