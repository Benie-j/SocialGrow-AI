/// Préférences d'alertes d'un membre (table `notification_preferences`).
/// Tout est activé par défaut, comme côté base.
class NotificationPrefs {
  const NotificationPrefs({
    this.publishSuccess = true,
    this.publishFailure = true,
    this.aiDraftReady = true,
    this.facebookIssue = true,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic> map) {
    return NotificationPrefs(
      publishSuccess: map['publish_success'] != false,
      publishFailure: map['publish_failure'] != false,
      aiDraftReady: map['ai_draft_ready'] != false,
      facebookIssue: map['facebook_issue'] != false,
    );
  }

  final bool publishSuccess;
  final bool publishFailure;
  final bool aiDraftReady;
  final bool facebookIssue;

  Map<String, dynamic> toMap() => {
        'publish_success': publishSuccess,
        'publish_failure': publishFailure,
        'ai_draft_ready': aiDraftReady,
        'facebook_issue': facebookIssue,
      };

  NotificationPrefs copyWith({
    bool? publishSuccess,
    bool? publishFailure,
    bool? aiDraftReady,
    bool? facebookIssue,
  }) {
    return NotificationPrefs(
      publishSuccess: publishSuccess ?? this.publishSuccess,
      publishFailure: publishFailure ?? this.publishFailure,
      aiDraftReady: aiDraftReady ?? this.aiDraftReady,
      facebookIssue: facebookIssue ?? this.facebookIssue,
    );
  }
}

/// Une alerte de l'historique (table `notifications`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final created = DateTime.tryParse('${map['created_at']}');
    final read = map['read_at'];
    return AppNotification(
      id: '${map['id']}',
      kind: '${map['kind']}',
      title: '${map['title']}',
      body: map['body'] as String?,
      createdAt: (created ?? DateTime.now()).toLocal(),
      readAt: read == null ? null : DateTime.tryParse('$read')?.toLocal(),
    );
  }

  final String id;

  /// publish_success, publish_failure, ai_draft_ready ou facebook_issue.
  final String kind;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        readAt: at,
      );
}

/// « Il y a 5 min », « Hier », « 12/11/2026 »…
String relativeTimeFr(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.isNegative || diff.inMinutes < 1) {
    return 'À l’instant';
  }
  if (diff.inMinutes < 60) {
    return 'Il y a ${diff.inMinutes} min';
  }
  if (diff.inHours < 24) {
    return 'Il y a ${diff.inHours} h';
  }
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days == 1) {
    return 'Hier';
  }
  if (days < 7) {
    return 'Il y a $days j';
  }
  final dd = at.day.toString().padLeft(2, '0');
  final mm = at.month.toString().padLeft(2, '0');
  return '$dd/$mm/${at.year}';
}
