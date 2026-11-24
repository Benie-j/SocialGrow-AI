import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/publication_settings.dart';

void main() {
  group('PublicationSettings', () {
    test('les valeurs par défaut sont cohérentes', () {
      final settings = PublicationSettings();

      expect(settings.validate(), isEmpty);
      expect(settings.autoPublish, isFalse);
      expect(settings.requireApproval, isTrue);
      expect(settings.formatVideoEnabled, isFalse);
    });

    test('toMap puis fromMap conserve les valeurs', () {
      final original = PublicationSettings(
        postsPerDay: 2,
        dailyPostLimit: 4,
        preferredTopics: ['Astuces'],
        targetAudience: 'Entrepreneurs',
        duplicateSimilarityThreshold: 0.9,
      );

      final copy = PublicationSettings.fromMap(original.toMap());

      expect(copy.toMap(), original.toMap());
    });

    test('fromMap lit les heures Postgres au format HH:MM:SS', () {
      final settings = PublicationSettings.fromMap({
        'preferred_times': ['08:00:00', '18:30:00'],
        'allowed_time_windows': [
          {'start': '06:00', 'end': '22:00'},
        ],
        'duplicate_similarity_threshold': 0.75,
      });

      expect(settings.preferredTimes, ['08:00', '18:30']);
      expect(settings.allowedTimeWindows.single.end, '22:00');
      expect(settings.duplicateSimilarityThreshold, 0.75);
    });

    test('frequency_per_week est dérivée des réglages quotidiens', () {
      final settings = PublicationSettings(
        postsPerDay: 2,
        preferredDays: [1, 3, 5],
      );

      expect(settings.toMap()['frequency_per_week'], 6);
    });

    test('refuse plus de publications par jour que le maximum autorisé', () {
      final settings = PublicationSettings(postsPerDay: 5, dailyPostLimit: 3);

      expect(settings.validate(), isNotEmpty);
    });

    test('refuse un horaire hors des créneaux autorisés', () {
      final settings = PublicationSettings(preferredTimes: ['03:00']);

      expect(
        settings.validate().any((p) => p.contains('03:00')),
        isTrue,
      );
    });

    test('refuse des horaires plus proches que l’intervalle minimum', () {
      final settings = PublicationSettings(
        postsPerDay: 2,
        preferredTimes: ['08:00', '08:30'],
        minIntervalMinutes: 120,
      );

      expect(settings.validate(), isNotEmpty);
    });

    test('exige au moins un format actif', () {
      final settings = PublicationSettings(
        formatTextEnabled: false,
        formatImageEnabled: false,
        formatVideoEnabled: false,
      );

      expect(settings.validate(), isNotEmpty);
    });

    test('refuse une thématique à la fois privilégiée et évitée', () {
      final settings = PublicationSettings(
        preferredTopics: ['Sport'],
        avoidedTopics: ['sport'],
      );

      expect(settings.validate(), isNotEmpty);
    });
  });
}
