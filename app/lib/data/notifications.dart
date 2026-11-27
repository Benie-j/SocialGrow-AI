/// Types de notifications produits côté serveur.
class NotificationKinds {
  const NotificationKinds._();

  static const publishSuccess = 'publish_success';
  static const publishFailure = 'publish_failure';
  static const aiDraftReady = 'ai_draft_ready';
  static const facebookIssue = 'facebook_issue';
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.postId,
    this.readAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    final readAt = row['read_at'] as String?;
    return AppNotification(
      id: row['id'] as String,
      kind: row['kind'] as String,
      title: row['title'] as String,
      body: row['body'] as String?,
      postId: row['post_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      readAt: readAt == null ? null : DateTime.parse(readAt),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String? body;
  final String? postId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification markedRead(DateTime at) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        postId: postId,
        createdAt: createdAt,
        readAt: readAt ?? at,
      );
}

/// Alertes choisies par l'utilisateur ; tout est activé tant qu'aucune
/// préférence n'est enregistrée (valeurs par défaut de la base).
class NotificationPreferences {
  const NotificationPreferences({
    this.publishSuccess = true,
    this.publishFailure = true,
    this.aiDraftReady = true,
    this.facebookIssue = true,
  });

  factory NotificationPreferences.fromRow(Map<String, dynamic>? row) {
    if (row == null) return const NotificationPreferences();
    return NotificationPreferences(
      publishSuccess: row['publish_success'] as bool? ?? true,
      publishFailure: row['publish_failure'] as bool? ?? true,
      aiDraftReady: row['ai_draft_ready'] as bool? ?? true,
      facebookIssue: row['facebook_issue'] as bool? ?? true,
    );
  }

  final bool publishSuccess;
  final bool publishFailure;
  final bool aiDraftReady;
  final bool facebookIssue;

  NotificationPreferences copyWith({
    bool? publishSuccess,
    bool? publishFailure,
    bool? aiDraftReady,
    bool? facebookIssue,
  }) {
    return NotificationPreferences(
      publishSuccess: publishSuccess ?? this.publishSuccess,
      publishFailure: publishFailure ?? this.publishFailure,
      aiDraftReady: aiDraftReady ?? this.aiDraftReady,
      facebookIssue: facebookIssue ?? this.facebookIssue,
    );
  }

  Map<String, dynamic> toRow() => {
        'publish_success': publishSuccess,
        'publish_failure': publishFailure,
        'ai_draft_ready': aiDraftReady,
        'facebook_issue': facebookIssue,
      };
}

class NotificationsOverview {
  const NotificationsOverview({
    required this.workspaceId,
    required this.preferences,
    required this.items,
  });

  final String workspaceId;
  final NotificationPreferences preferences;

  /// Les plus récentes d'abord.
  final List<AppNotification> items;

  int get unreadCount => items.where((n) => n.isUnread).length;

  NotificationsOverview copyWith({
    NotificationPreferences? preferences,
    List<AppNotification>? items,
  }) {
    return NotificationsOverview(
      workspaceId: workspaceId,
      preferences: preferences ?? this.preferences,
      items: items ?? this.items,
    );
  }
}

/// « À l'instant », « Il y a 5 min », « Hier »… puis la date.
String relativeTime(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inSeconds < 60) return 'À l’instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'Hier';
  if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';

  final local = then.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
