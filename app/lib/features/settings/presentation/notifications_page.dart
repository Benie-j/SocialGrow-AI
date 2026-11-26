import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../data/notifications.dart';
import '../../../data/notifications_repository.dart';
import '../../../data/publication_settings_repository.dart';
import 'settings_widgets.dart';

/// Écran « Notifications » : choix des alertes et historique.
/// Les alertes sont créées par le serveur (publication envoyée ou échouée,
/// brouillon IA prêt, problème Facebook) et s'affichent ici, dans l'app.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    this.settingsRepository,
    this.repository,
  });

  /// Espace et rôle ; par défaut, Supabase.
  final PublicationSettingsRepository? settingsRepository;

  /// Préférences et historique ; par défaut, Supabase.
  final NotificationsRepository? repository;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final PublicationSettingsRepository _settingsRepo;
  late final NotificationsRepository _repo;

  WorkspaceAccess? _access;
  NotificationPrefs _prefs = const NotificationPrefs();
  List<AppNotification> _items = const [];
  Object? _loadError;
  bool _loading = true;
  bool _savingPrefs = false;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _settingsRepo = widget.settingsRepository ??
        SupabasePublicationSettingsRepository(client);
    _repo = widget.repository ?? SupabaseNotificationsRepository(client);
    _load();
  }

  Future<void> _load() async {
    try {
      final access = await _settingsRepo.loadAccess();
      final prefs = await _repo.loadPrefs(access.workspaceId);
      final items = await _repo.loadRecent(access.workspaceId, limit: 40);
      if (!mounted) {
        return;
      }
      setState(() {
        _access = access;
        _prefs = prefs;
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  Future<void> _changePrefs(NotificationPrefs next) async {
    final access = _access;
    if (access == null || _savingPrefs) {
      return;
    }
    final previous = _prefs;
    setState(() {
      _prefs = next;
      _savingPrefs = true;
    });
    try {
      await _repo.savePrefs(access.workspaceId, next);
      if (!mounted) {
        return;
      }
      setState(() => _savingPrefs = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _prefs = previous;
        _savingPrefs = false;
      });
      _toast(describeError(error));
    }
  }

  Future<void> _open(AppNotification item) async {
    if (item.isRead) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _items = [
        for (final e in _items) e.id == item.id ? e.markedRead(now) : e,
      ];
    });
    try {
      await _repo.markRead([item.id]);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _toast(describeError(error));
      await _load();
    }
  }

  Future<void> _readAll() async {
    final access = _access;
    if (access == null) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _items = [for (final e in _items) e.isRead ? e : e.markedRead(now)];
    });
    try {
      await _repo.markAllRead(access.workspaceId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _toast(describeError(error));
      await _load();
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'publish_success':
        return Icons.check_circle_outline;
      case 'publish_failure':
        return Icons.error_outline;
      case 'ai_draft_ready':
        return Icons.auto_awesome;
      default:
        return Icons.link_off;
    }
  }

  Color _tint(String kind, SgPalette p) {
    switch (kind) {
      case 'publish_success':
        return p.success;
      case 'publish_failure':
      case 'facebook_issue':
        return p.accentWarm;
      default:
        return p.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_access == null) {
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
      content = _buildBody(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: content,
    );
  }

  Widget _buildBody(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final unread = _items.where((e) => !e.isRead).length;
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alertes à recevoir', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                SwitchRow(
                  label: 'Publication envoyée',
                  subtitle: 'Ton texte est en ligne sur la Page.',
                  value: _prefs.publishSuccess,
                  onChanged: (v) =>
                      _changePrefs(_prefs.copyWith(publishSuccess: v)),
                ),
                SwitchRow(
                  label: 'Publication échouée',
                  subtitle: 'Meta a refusé ou la connexion a été coupée.',
                  value: _prefs.publishFailure,
                  onChanged: (v) =>
                      _changePrefs(_prefs.copyWith(publishFailure: v)),
                ),
                SwitchRow(
                  label: 'Brouillon IA prêt',
                  subtitle: 'L’assistant a rédigé un brouillon à relire.',
                  value: _prefs.aiDraftReady,
                  onChanged: (v) =>
                      _changePrefs(_prefs.copyWith(aiDraftReady: v)),
                ),
                SwitchRow(
                  label: 'Problème Facebook',
                  subtitle: 'Statistiques indisponibles ou autorisation à '
                      'renouveler.',
                  value: _prefs.facebookIssue,
                  onChanged: (v) =>
                      _changePrefs(_prefs.copyWith(facebookIssue: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Les alertes apparaissent ici, dans l’app. Les '
                    'notifications sur l’écran de verrouillage du téléphone '
                    'ne sont pas encore actives.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text('Historique', style: theme.textTheme.titleMedium),
              ),
              if (unread > 0)
                TextButton(
                  onPressed: _readAll,
                  child: const Text('Tout marquer comme lu'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aucune alerte pour l’instant. Elles apparaîtront dès '
                'qu’une publication partira ou qu’un brouillon sera prêt.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.textSecondary,
                ),
              ),
            )
          else
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassPanel(
                  onTap: () => _open(item),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_icon(item.kind), color: _tint(item.kind, p)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: item.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                            if ((item.body ?? '').isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.body!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              relativeTimeFr(item.createdAt, now),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!item.isRead)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 6),
                          child: Icon(Icons.circle, size: 10, color: p.accent),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
