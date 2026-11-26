import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/schedule.dart';

void main() {
  final now = DateTime(2026, 11, 26, 12);

  test('formate la date en français', () {
    expect(formatScheduleWhen(DateTime(2026, 11, 27, 9, 5)),
        'ven. 27 nov. 2026 à 09:05');
    expect(formatScheduleWhen(DateTime(2027, 3, 1, 18, 30)),
        'lun. 1 mars 2027 à 18:30');
  });

  test('refuse un horaire trop proche ou déjà passé', () {
    expect(validateScheduleTime(now.subtract(const Duration(hours: 1)), now),
        isNotNull);
    expect(validateScheduleTime(now.add(const Duration(minutes: 4)), now),
        isNotNull);
  });

  test('accepte un horaire à partir de la marge minimale', () {
    expect(validateScheduleTime(now.add(const Duration(minutes: 5)), now),
        isNull);
    expect(validateScheduleTime(now.add(const Duration(days: 30)), now),
        isNull);
  });

  test('refuse un horaire au-delà de l’horizon', () {
    expect(validateScheduleTime(now.add(const Duration(days: 400)), now),
        isNotNull);
  });
}
