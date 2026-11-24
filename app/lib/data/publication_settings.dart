/// Créneau horaire autorisé pour les publications (heures locales "HH:MM").
class TimeWindow {
  TimeWindow({required this.start, required this.end});

  factory TimeWindow.fromMap(Map<String, dynamic> map) {
    return TimeWindow(
      start: normalizeTime(map['start']?.toString() ?? '07:00'),
      end: normalizeTime(map['end']?.toString() ?? '21:00'),
    );
  }

  String start;
  String end;

  Map<String, dynamic> toMap() => {'start': start, 'end': end};
}

int minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  final hours = int.tryParse(parts.first) ?? 0;
  final minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return hours * 60 + minutes;
}

String formatMinutes(int total) {
  final hours = (total ~/ 60).toString().padLeft(2, '0');
  final minutes = (total % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}

/// Ramène "08:00:00" ou "8:5" au format "HH:MM".
String normalizeTime(String raw) => formatMinutes(minutesOf(raw));

String _str(Object? v, String fallback) =>
    v is String && v.isNotEmpty ? v : fallback;

int _int(Object? v, int fallback) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

double _double(Object? v, double fallback) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

List<String> _strList(Object? v, List<String> fallback) =>
    v is List ? v.map((e) => e.toString()).toList() : fallback;

/// Réglages de publication d’un espace de travail.
///
/// Source unique de vérité : ils sont lus et écrits uniquement dans la table
/// `public.publication_settings` de Supabase, depuis Paramètres > Paramètres
/// de publication. Générateur, calendrier et moteur de publication relisent
/// cette même ligne.
class PublicationSettings {
  PublicationSettings({
    // A. Fréquence
    this.postsPerDay = 1,
    this.dailyPostLimit = 3,
    this.minIntervalMinutes = 120,
    List<int>? preferredDays,
    // B. Horaires
    this.timezone = 'Africa/Abidjan',
    List<String>? preferredTimes,
    List<TimeWindow>? allowedTimeWindows,
    // C. Contenu
    this.language = 'fr',
    this.defaultTone = 'professional',
    this.defaultLength = 'medium',
    this.writingStyle = 'conversational',
    List<String>? allowedCategories,
    List<String>? preferredTopics,
    List<String>? avoidedTopics,
    this.hashtagsEnabled = true,
    this.maxHashtags = 3,
    this.ctaEnabled = true,
    // D. Formats
    this.formatTextEnabled = true,
    this.formatImageEnabled = true,
    this.formatVideoEnabled = false,
    // E. Automatisation
    this.autoPublish = false,
    this.autoGenerate = false,
    this.requireApproval = true,
    this.publishingPaused = false,
    this.maxRetries = 3,
    this.retryDelayMinutes = 15,
    // F. Stratégie
    this.primaryGoal = 'engagement',
    this.targetAudience,
    this.preferredContentType,
    this.topicRenewalDays = 14,
    this.adaptToPerformance = true,
    // G. Doublons
    this.duplicateDetectionEnabled = true,
    this.duplicateSimilarityThreshold = 0.8,
    this.topicReuseMinDays = 60,
    this.blockIdenticalRepublish = true,
  })  : preferredDays = preferredDays ?? [1, 2, 3, 4, 5],
        preferredTimes = preferredTimes ?? ['08:00', '12:00', '18:00'],
        allowedTimeWindows =
            allowedTimeWindows ?? [TimeWindow(start: '07:00', end: '21:00')],
        allowedCategories = allowedCategories ?? [],
        preferredTopics = preferredTopics ?? [],
        avoidedTopics = avoidedTopics ?? [];

  factory PublicationSettings.fromMap(Map<String, dynamic> m) {
    final d = PublicationSettings();
    final windows = m['allowed_time_windows'];
    final parsedWindows = windows is List
        ? windows
            .whereType<Map>()
            .map((e) => TimeWindow.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <TimeWindow>[];
    final days = m['preferred_days'];
    final times = m['preferred_times'];
    final audience = m['target_audience'];
    final contentType = m['preferred_content_type'];
    return PublicationSettings(
      postsPerDay: _int(m['posts_per_day'], d.postsPerDay),
      dailyPostLimit: _int(m['daily_post_limit'], d.dailyPostLimit),
      minIntervalMinutes:
          _int(m['min_interval_minutes'], d.minIntervalMinutes),
      preferredDays: days is List
          ? days.map((e) => _int(e, 0)).where((e) => e > 0).toList()
          : null,
      timezone: _str(m['timezone'], d.timezone),
      preferredTimes: times is List
          ? times.map((e) => normalizeTime(e.toString())).toList()
          : null,
      allowedTimeWindows: parsedWindows.isEmpty ? null : parsedWindows,
      language: _str(m['language'], d.language),
      defaultTone: _str(m['default_tone'], d.defaultTone),
      defaultLength: _str(m['default_length'], d.defaultLength),
      writingStyle: _str(m['writing_style'], d.writingStyle),
      allowedCategories: _strList(m['allowed_categories'], []),
      preferredTopics: _strList(m['preferred_topics'], []),
      avoidedTopics: _strList(m['avoided_topics'], []),
      hashtagsEnabled: _bool(m['hashtags_enabled'], d.hashtagsEnabled),
      maxHashtags: _int(m['max_hashtags'], d.maxHashtags),
      ctaEnabled: _bool(m['cta_enabled'], d.ctaEnabled),
      formatTextEnabled: _bool(m['format_text_enabled'], d.formatTextEnabled),
      formatImageEnabled:
          _bool(m['format_image_enabled'], d.formatImageEnabled),
      formatVideoEnabled:
          _bool(m['format_video_enabled'], d.formatVideoEnabled),
      autoPublish: _bool(m['auto_publish'], d.autoPublish),
      autoGenerate: _bool(m['auto_generate'], d.autoGenerate),
      requireApproval: _bool(m['require_approval'], d.requireApproval),
      publishingPaused: _bool(m['publishing_paused'], d.publishingPaused),
      maxRetries: _int(m['max_retries'], d.maxRetries),
      retryDelayMinutes: _int(m['retry_delay_minutes'], d.retryDelayMinutes),
      primaryGoal: _str(m['primary_goal'], d.primaryGoal),
      targetAudience: audience is String ? audience : null,
      preferredContentType: contentType is String ? contentType : null,
      topicRenewalDays: _int(m['topic_renewal_days'], d.topicRenewalDays),
      adaptToPerformance:
          _bool(m['adapt_to_performance'], d.adaptToPerformance),
      duplicateDetectionEnabled: _bool(
        m['duplicate_detection_enabled'],
        d.duplicateDetectionEnabled,
      ),
      duplicateSimilarityThreshold: _double(
        m['duplicate_similarity_threshold'],
        d.duplicateSimilarityThreshold,
      ),
      topicReuseMinDays: _int(m['topic_reuse_min_days'], d.topicReuseMinDays),
      blockIdenticalRepublish: _bool(
        m['block_identical_republish'],
        d.blockIdenticalRepublish,
      ),
    );
  }

  // A. Fréquence
  int postsPerDay;
  int dailyPostLimit;
  int minIntervalMinutes;

  /// Jours de publication : 1 = lundi … 7 = dimanche.
  List<int> preferredDays;

  // B. Horaires
  String timezone;
  List<String> preferredTimes;
  List<TimeWindow> allowedTimeWindows;

  // C. Contenu
  String language;
  String defaultTone;
  String defaultLength;
  String writingStyle;
  List<String> allowedCategories;
  List<String> preferredTopics;
  List<String> avoidedTopics;
  bool hashtagsEnabled;
  int maxHashtags;
  bool ctaEnabled;

  // D. Formats
  bool formatTextEnabled;
  bool formatImageEnabled;
  bool formatVideoEnabled;

  // E. Automatisation
  bool autoPublish;
  bool autoGenerate;
  bool requireApproval;
  bool publishingPaused;
  int maxRetries;
  int retryDelayMinutes;

  // F. Stratégie
  String primaryGoal;
  String? targetAudience;
  String? preferredContentType;
  int topicRenewalDays;
  bool adaptToPerformance;

  // G. Doublons
  bool duplicateDetectionEnabled;
  double duplicateSimilarityThreshold;
  int topicReuseMinDays;
  bool blockIdenticalRepublish;

  /// Colonnes de `publication_settings` (sans `workspace_id`).
  ///
  /// `frequency_per_week` est dérivée (publications par jour × jours) afin de
  /// ne jamais contredire les réglages quotidiens.
  Map<String, dynamic> toMap() {
    final days = preferredDays.toSet().toList()..sort();
    final times = preferredTimes.toSet().toList()..sort();
    final audience = targetAudience?.trim();
    final contentType = preferredContentType?.trim();
    return {
      'posts_per_day': postsPerDay,
      'daily_post_limit': dailyPostLimit,
      'min_interval_minutes': minIntervalMinutes,
      'preferred_days': days,
      'frequency_per_week': (postsPerDay * days.length).clamp(0, 50),
      'timezone': timezone,
      'preferred_times': times.map((t) => '$t:00').toList(),
      'allowed_time_windows': allowedTimeWindows.map((w) => w.toMap()).toList(),
      'language': language,
      'default_tone': defaultTone,
      'default_length': defaultLength,
      'writing_style': writingStyle,
      'allowed_categories': allowedCategories,
      'preferred_topics': preferredTopics,
      'avoided_topics': avoidedTopics,
      'hashtags_enabled': hashtagsEnabled,
      'max_hashtags': maxHashtags,
      'cta_enabled': ctaEnabled,
      'format_text_enabled': formatTextEnabled,
      'format_image_enabled': formatImageEnabled,
      'format_video_enabled': formatVideoEnabled,
      'auto_publish': autoPublish,
      'auto_generate': autoGenerate,
      'require_approval': requireApproval,
      'publishing_paused': publishingPaused,
      'max_retries': maxRetries,
      'retry_delay_minutes': retryDelayMinutes,
      'primary_goal': primaryGoal,
      'target_audience':
          (audience == null || audience.isEmpty) ? null : audience,
      'preferred_content_type':
          (contentType == null || contentType.isEmpty) ? null : contentType,
      'topic_renewal_days': topicRenewalDays,
      'adapt_to_performance': adaptToPerformance,
      'duplicate_detection_enabled': duplicateDetectionEnabled,
      'duplicate_similarity_threshold':
          double.parse(duplicateSimilarityThreshold.toStringAsFixed(2)),
      'topic_reuse_min_days': topicReuseMinDays,
      'block_identical_republish': blockIdenticalRepublish,
    };
  }

  /// Vérifie la cohérence des réglages. Liste vide = valides.
  List<String> validate() {
    final problems = <String>[];

    if (postsPerDay > dailyPostLimit) {
      problems.add(
        'Le nombre de publications par jour ($postsPerDay) dépasse le '
        'maximum autorisé ($dailyPostLimit).',
      );
    }
    if (postsPerDay > 0 && preferredDays.isEmpty) {
      problems.add('Choisis au moins un jour de publication.');
    }

    final times = preferredTimes.toSet().toList()..sort();
    if (postsPerDay > 0 && times.length < postsPerDay) {
      problems.add('Ajoute au moins $postsPerDay horaires de publication.');
    }

    if (allowedTimeWindows.isEmpty) {
      problems.add('Ajoute au moins un créneau autorisé.');
    }
    for (final w in allowedTimeWindows) {
      if (minutesOf(w.start) >= minutesOf(w.end)) {
        problems.add(
          'Le créneau ${w.start} – ${w.end} est invalide : la fin doit '
          'suivre le début.',
        );
      }
    }
    for (final t in times) {
      final m = minutesOf(t);
      final inside = allowedTimeWindows
          .any((w) => m >= minutesOf(w.start) && m <= minutesOf(w.end));
      if (!inside) {
        problems.add('L’horaire $t est en dehors des créneaux autorisés.');
      }
    }
    for (var i = 1; i < times.length; i++) {
      final gap = minutesOf(times[i]) - minutesOf(times[i - 1]);
      if (gap < minIntervalMinutes) {
        problems.add(
          'Les horaires ${times[i - 1]} et ${times[i]} sont plus proches que '
          'l’intervalle minimum ($minIntervalMinutes min).',
        );
      }
    }

    if (!formatTextEnabled && !formatImageEnabled && !formatVideoEnabled) {
      problems.add('Active au moins un format de publication.');
    }

    final avoided = avoidedTopics.map((t) => t.toLowerCase()).toSet();
    final overlap = preferredTopics
        .where((t) => avoided.contains(t.toLowerCase()))
        .toList();
    if (overlap.isNotEmpty) {
      problems.add(
        'Une thématique ne peut pas être à la fois privilégiée et évitée : '
        '${overlap.join(', ')}.',
      );
    }

    return problems;
  }
}
