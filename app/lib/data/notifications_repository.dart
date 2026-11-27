import 'package:supabase_flutter/supabase_flutter.dart';

import 'notifications.dart';
import 'publication_settings_repository.dart';

abstract class NotificationsRepository {
  /// Charge les préférences et les 50 notifications les plus récentes de
  /// l'espace de travail.
  ///
  /// Lance [NoWorkspaceException] si aucun espace n'est associé au compte.
  Future<NotificationsOverview> load();

  Future<void> savePreferences(
    String workspaceId,
    NotificationPreferences preferences,
  );

  Future<void> markRead(String notificationId);

  Future<void> markAllRead(String workspaceId);
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const NoWorkspaceException();
    return id;
  }

  @override
  Future<NotificationsOverview> load() async {
    final userId = _userId;
    final access =
        await SupabasePublicationSettingsRepository(_client).loadAccess();

    final results = await Future.wait<Object?>([
      _client
          .from('notification_preferences')
          .select('publish_success, publish_failure, ai_draft_ready, '
              'facebook_issue')
          .eq('workspace_id', access.workspaceId)
          .eq('user_id', userId)
          .maybeSingle(),
      _client
          .from('notifications')
          .select('id, kind, title, body, post_id, created_at, read_at')
          .eq('workspace_id', access.workspaceId)
          .order('created_at', ascending: false)
          .limit(50),
    ]);

    final preferences = results[0] as Map<String, dynamic>?;
    final rows = results[1] as List<dynamic>;

    return NotificationsOverview(
      workspaceId: access.workspaceId,
      preferences: NotificationPreferences.fromRow(preferences),
      items: [
        for (final row in rows)
          AppNotification.fromRow(row as Map<String, dynamic>),
      ],
    );
  }

  @override
  Future<void> savePreferences(
    String workspaceId,
    NotificationPreferences preferences,
  ) async {
    await _client.from('notification_preferences').upsert(
      {
        'workspace_id': workspaceId,
        'user_id': _userId,
        ...preferences.toRow(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'workspace_id,user_id',
    );
  }

  @override
  Future<void> markRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .eq('user_id', _userId);
  }

  @override
  Future<void> markAllRead(String workspaceId) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('workspace_id', workspaceId)
        .eq('user_id', _userId)
        .isFilter('read_at', null);
  }
}
