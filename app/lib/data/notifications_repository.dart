import 'package:supabase_flutter/supabase_flutter.dart';

import 'notifications.dart';

abstract class NotificationsRepository {
  Future<NotificationPrefs> loadPrefs(String workspaceId);

  Future<void> savePrefs(String workspaceId, NotificationPrefs prefs);

  Future<List<AppNotification>> loadRecent(String workspaceId, {int limit});

  Future<void> markRead(List<String> ids);

  Future<void> markAllRead(String workspaceId);
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw Exception('Session expirée. Reconnecte-toi.');
    }
    return id;
  }

  @override
  Future<NotificationPrefs> loadPrefs(String workspaceId) async {
    final row = await _client
        .from('notification_preferences')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('user_id', _userId)
        .maybeSingle();
    return row == null ? const NotificationPrefs() : NotificationPrefs.fromMap(row);
  }

  @override
  Future<void> savePrefs(String workspaceId, NotificationPrefs prefs) async {
    await _client.from('notification_preferences').upsert(
      {...prefs.toMap(), 'workspace_id': workspaceId, 'user_id': _userId},
      onConflict: 'workspace_id,user_id',
    );
  }

  @override
  Future<List<AppNotification>> loadRecent(
    String workspaceId, {
    int limit = 40,
  }) async {
    final rows = await _client
        .from('notifications')
        .select('id,kind,title,body,created_at,read_at')
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((e) => AppNotification.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', ids)
        .isFilter('read_at', null);
  }

  @override
  Future<void> markAllRead(String workspaceId) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('workspace_id', workspaceId)
        .isFilter('read_at', null);
  }
}
