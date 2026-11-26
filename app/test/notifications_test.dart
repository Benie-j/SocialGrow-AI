import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/notifications.dart';

void main() {
  // Jeudi 26 novembre 2026, 12 h.
  final now = DateTime(2026, 11, 26, 12);

  group('NotificationPrefs', () {
    test('tout est activé par défaut', () {
      const prefs = NotificationPrefs();
      expect(prefs.toMap().values.every((v) => v == true), isTrue);
    });

    test('fromMap lit les valeurs et traite l’absence comme activé', () {
      final prefs = NotificationPrefs.fromMap({
        'publish_success': false,
        'ai_draft_ready': null,
      });
      expect(prefs.publishSuccess, isFalse);
      expect(prefs.publishFailure, isTrue);
      expect(prefs.aiDraftReady, isTrue);
      expect(prefs.facebookIssue, isTrue);
    });

    test('copyWith ne change que le champ demandé', () {
      final next = const NotificationPrefs().copyWith(facebookIssue: false);
      expect(next.facebookIssue, isFalse);
      expect(next.publishSuccess, isTrue);
      expect(next.toMap()['facebook_issue'], isFalse);
    });
  });

  group('AppNotification', () {
    test('fromMap : non lue puis marquée lue', () {
      final item = AppNotification.fromMap({
        'id': 'n1',
        'kind': 'publish_failure',
        'title': 'Publication échouée',
        'body': null,
        'created_at': '2026-11-26T10:00:00Z',
        'read_at': null,
      });
      expect(item.isRead, isFalse);
      expect(item.body, isNull);
      final read = item.markedRead(now);
      expect(read.isRead, isTrue);
      expect(read.id, 'n1');
      expect(read.title, 'Publication échouée');
    });
  });

  group('relativeTimeFr', () {
    test('à l’instant, minutes, heures', () {
      expect(relativeTimeFr(now, now), 'À l’instant');
      expect(
        relativeTimeFr(now.subtract(const Duration(minutes: 5)), now),
        'Il y a 5 min',
      );
      expect(
        relativeTimeFr(now.subtract(const Duration(hours: 3)), now),
        'Il y a 3 h',
      );
    });

    test('hier, jours, date complète', () {
      expect(relativeTimeFr(DateTime(2026, 11, 25, 8), now), 'Hier');
      expect(relativeTimeFr(DateTime(2026, 11, 23, 8), now), 'Il y a 3 j');
      expect(relativeTimeFr(DateTime(2026, 11, 3, 8), now), '03/11/2026');
    });

    test('une date future est traitée comme maintenant', () {
      expect(
        relativeTimeFr(now.add(const Duration(minutes: 5)), now),
        'À l’instant',
      );
    });
  });
}
