import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/editorial_strategy.dart';

void main() {
  group('planWeek', () {
    test('respecte exactement les quotas de chaque pilier', () {
      final plan = planWeek(
        {'educate': 4, 'inspire': 2, 'sell': 0, 'engage': 2, 'behind': 0},
        8,
      );
      expect(plan.length, 8);
      expect(plan.where((id) => id == 'educate').length, 4);
      expect(plan.where((id) => id == 'inspire').length, 2);
      expect(plan.where((id) => id == 'engage').length, 2);
      expect(plan.contains('sell'), isFalse);
      expect(plan.contains('behind'), isFalse);
    });

    test('alterne les piliers au lieu de les regrouper', () {
      final plan = planWeek(
        {'educate': 1, 'inspire': 1, 'sell': 0, 'engage': 0, 'behind': 0},
        6,
      );
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i], isNot(plan[i - 1]));
      }
    });

    test('répartit les restes au plus fort reste et garde le total', () {
      final plan = planWeek(
        {'educate': 1, 'inspire': 1, 'sell': 1, 'engage': 0, 'behind': 0},
        5,
      );
      expect(plan.length, 5);
      final counts = {
        for (final id in plan) id: plan.where((p) => p == id).length,
      };
      expect(counts.values.reduce((a, b) => a + b), 5);
      expect(counts.values.every((c) => c == 1 || c == 2), isTrue);
    });

    test('renvoie un plan vide sans publications ou sans poids', () {
      expect(planWeek({'educate': 3}, 0), isEmpty);
      expect(
        planWeek(
          {'educate': 0, 'inspire': 0, 'sell': 0, 'engage': 0, 'behind': 0},
          5,
        ),
        isEmpty,
      );
    });

    test('est déterministe', () {
      final weights = {'educate': 3, 'inspire': 2, 'sell': 1, 'engage': 2};
      expect(planWeek(weights, 7), planWeek(weights, 7));
    });
  });

  group('EditorialStrategy', () {
    test('lit et réécrit une ligne Supabase sans perte', () {
      final strategy = EditorialStrategy.fromMap({
        'business_description': 'Boulangerie artisanale',
        'brand_tagline': 'Le pain qui a du caractère',
        'pillar_weights': {'educate': 5, 'inspire': 0, 'sell': 2},
        'voice_formality': 8,
        'voice_warmth': 2,
        'banned_phrases': ['révolutionnaire'],
      });
      final map = strategy.toMap();
      expect(map['business_description'], 'Boulangerie artisanale');
      expect(map['voice_formality'], 8);
      expect(map['banned_phrases'], ['révolutionnaire']);
      final weights = map['pillar_weights'] as Map;
      expect(weights['educate'], 5);
      expect(weights['inspire'], 0);
      expect(weights.keys.length, kPillars.length);
    });

    test('borne les valeurs hors limites venues du serveur', () {
      final strategy = EditorialStrategy.fromMap({
        'pillar_weights': {'educate': 99, 'inspire': -4},
        'voice_formality': 40,
        'voice_warmth': -3,
      });
      expect(strategy.pillarWeights['educate'], kMaxWeight);
      expect(strategy.pillarWeights['inspire'], 0);
      expect(strategy.voiceFormality, 10);
      expect(strategy.voiceWarmth, 0);
    });

    test('utilise les valeurs par défaut quand la ligne est vide', () {
      final strategy = EditorialStrategy.fromMap({});
      expect(strategy.totalWeight, greaterThan(0));
      expect(strategy.validate(), isEmpty);
    });

    test('refuse une stratégie sans aucun poids ou trop longue', () {
      final strategy = EditorialStrategy(
        pillarWeights: {for (final p in kPillars) p.id: 0},
        brandTagline: 'x' * (kMaxTagline + 1),
      );
      expect(strategy.validate().length, 2);
    });

    test('la boussole compte les étapes réellement complétées', () {
      final empty = EditorialStrategy();
      expect(empty.compass().where((s) => s.done).length, 1);

      final full = EditorialStrategy(
        businessDescription: 'Boutique de mode',
        brandTagline: 'S’habiller avec confiance',
      );
      final steps = full.compass(audience: 'Femmes 25-40 ans');
      expect(steps.every((s) => s.done), isTrue);
    });
  });

  test('describeVoice résume la voix choisie', () {
    expect(describeVoice(9, 8), 'formel et chaleureux');
    expect(describeVoice(1, 1), 'décontracté et sobre');
    expect(describeVoice(5, 5), 'équilibré et mesuré');
  });
}
