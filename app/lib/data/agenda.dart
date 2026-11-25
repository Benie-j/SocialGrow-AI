import 'publication_settings.dart';

const _weekdayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _weekdayLong = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const _monthShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];
const _monthLong = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Libellés français des dates (sans dépendre des localisations du système).
class FrDate {
  const FrDate._();

  static String weekdayShort(DateTime d) => _weekdayShort[d.weekday - 1];

  static String monthShort(DateTime d) => _monthShort[d.month - 1];

  /// « mercredi 25 novembre ».
  static String dayLong(DateTime d) =>
      '${_weekdayLong[d.weekday - 1]} ${d.day} ${_monthLong[d.month - 1]}';

  /// « jeu. 26 nov. » pour les boutons.
  static String dayCompact(DateTime d) =>
      '${weekdayShort(d).toLowerCase()}. ${d.day} ${monthShort(d)}';

  /// « 24 – 30 nov. 2026 », ou « 28 nov. – 4 déc. 2026 » à cheval sur deux mois.
  static String weekRange(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day} – ${sunday.day} ${monthShort(sunday)} ${sunday.year}';
    }
    return '${monday.day} ${monthShort(monday)} – '
        '${sunday.day} ${monthShort(sunday)} ${sunday.year}';
  }

  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Lundi (à minuit) de la semaine qui contient [d].
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ajoute [n] jours calendaires (sans dérive lors des changements d'heure).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Une publication telle qu'affichée dans l'agenda.
class AgendaPost {
  const AgendaPost({
    required this.id,
    required this.status,
    required this.contentType,
    required this.body,
    this.title,
    this.scheduledAt,
    this.publishedAt,
    this.errorMessage,
    this.facebookPageId,
  });

  factory AgendaPost.fromMap(Map<String, dynamic> m) {
    DateTime? date(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;

    return AgendaPost(
      id: m['id'].toString(),
      status: (m['status'] ?? 'draft').toString(),
      contentType: (m['content_type'] ?? 'text').toString(),
      body: (m['body'] ?? '').toString(),
      title: text(m['title']),
      scheduledAt: date(m['scheduled_at']),
      publishedAt: date(m['published_at']),
      errorMessage: text(m['error_message']),
      facebookPageId: text(m['facebook_page_id']),
    );
  }

  final String id;
  final String status;
  final String contentType;
  final String body;
  final String? title;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;
  final String? errorMessage;
  final String? facebookPageId;

  /// Moment affiché : la date réelle de publication si elle existe.
  DateTime? get when =>
      status == 'published' ? publishedAt ?? scheduledAt : scheduledAt ?? publishedAt;

  /// Une publication peut être déplacée tant qu'elle n'est pas partie.
  bool get canReschedule =>
      (status == 'scheduled' || status == 'pending_approval') &&
      scheduledAt != null;

  /// Compte dans l'agenda et bloque les créneaux voisins.
  bool get occupiesSlot =>
      status == 'scheduled' ||
      status == 'pending_approval' ||
      status == 'publishing' ||
      status == 'published';

  String get headline {
    final t = title;
    if (t != null) return t;
    final line = body.trim().split('\n').first.trim();
    return line.isEmpty ? 'Publication sans texte' : line;
  }
}

/// Créneau recommandé par les réglages de l'utilisateur, encore libre.
class AgendaSlot {
  const AgendaSlot(this.at);

  final DateTime at;
}

int? _minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

DateTime _at(DateTime day, int minutes) =>
    DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

/// Vrai si [at] est trop proche d'une autre publication du même espace.
bool conflictsWithPosts(
  DateTime at,
  Iterable<AgendaPost> posts,
  int minIntervalMinutes, {
  String? excludeId,
}) {
  final interval = minIntervalMinutes < 1 ? 1 : minIntervalMinutes;
  for (final post in posts) {
    if (post.id == excludeId || !post.occupiesSlot) continue;
    final other = post.when;
    if (other == null) continue;
    if (other.difference(at).inMinutes.abs() < interval) return true;
  }
  return false;
}

/// Créneaux libres d'un jour : horaires préférés, jours préférés, dans le futur,
/// à distance suffisante des autres publications.
List<AgendaSlot> freeSlotsFor(
  DateTime day, {
  required PublicationSettings settings,
  required List<AgendaPost> posts,
  required DateTime now,
}) {
  if (!settings.preferredDays.contains(day.weekday)) return const [];

  final slots = <AgendaSlot>[];
  final seen = <int>{};
  for (final raw in settings.preferredTimes) {
    final minutes = _minutesOf(raw);
    if (minutes == null || !seen.add(minutes)) continue;
    final at = _at(day, minutes);
    if (!at.isAfter(now)) continue;
    if (conflictsWithPosts(at, posts, settings.minIntervalMinutes)) continue;
    slots.add(AgendaSlot(at));
  }
  slots.sort((a, b) => a.at.compareTo(b.at));
  return slots;
}

/// Horaires proposables pour un jour : pas de 30 minutes dans les fenêtres
/// autorisées, plus les horaires préférés qui y tombent.
List<DateTime> candidateTimes(
  DateTime day, {
  required PublicationSettings settings,
  int stepMinutes = 30,
}) {
  final minutes = <int>{};
  final windows = <List<int>>[];
  for (final w in settings.allowedTimeWindows) {
    final start = _minutesOf(w.start);
    final end = _minutesOf(w.end);
    if (start == null || end == null || end < start) continue;
    windows.add([start, end]);
    for (var m = start; m <= end; m += stepMinutes) {
      minutes.add(m);
    }
  }
  for (final raw in settings.preferredTimes) {
    final m = _minutesOf(raw);
    if (m == null) continue;
    final inside = windows.isEmpty || windows.any((w) => m >= w[0] && m <= w[1]);
    if (inside) minutes.add(m);
  }
  final sorted = minutes.toList()..sort();
  return [for (final m in sorted) _at(day, m)];
}

/// La modification a été refusée (droits insuffisants côté base).
class AgendaPermissionException implements Exception {
  const AgendaPermissionException();
}
