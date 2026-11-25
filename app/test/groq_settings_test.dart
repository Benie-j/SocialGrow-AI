import 'package:flutter_test/flutter_test.dart';
import 'package:socialgrow_ai/data/groq_settings.dart';

void main() {
  group('GroqSettings', () {
    test('lit et réécrit une ligne Supabase sans perte', () {
      final settings = GroqSettings.fromMap({
        'model': 'openai/gpt-oss-20b',
        'draft_model': 'llama-3.1-8b-instant',
        'creativity': 9,
        'max_output_tokens': 800,
        'monthly_generation_limit': 150,
      });
      final map = settings.toMap();
      expect(map['model'], 'openai/gpt-oss-20b');
      expect(map['creativity'], 9);
      expect(map['max_output_tokens'], 800);
      expect(map['monthly_generation_limit'], 150);
      expect(settings.temperature, closeTo(0.9, 0.0001));
    });

    test('borne les valeurs hors limites venues du serveur', () {
      final settings = GroqSettings.fromMap({
        'creativity': 99,
        'max_output_tokens': 5,
        'monthly_generation_limit': 999999,
      });
      expect(settings.creativity, kMaxCreativity);
      expect(settings.maxOutputTokens, kMinOutputTokens);
      expect(settings.monthlyGenerationLimit, kMaxMonthlyLimit);
    });

    test('utilise les valeurs par défaut quand la ligne est vide', () {
      final settings = GroqSettings.fromMap({});
      expect(settings.model, isNotEmpty);
      expect(settings.validate(), isEmpty);
    });

    test('refuse un identifiant de modèle invalide', () {
      expect(isValidModelId('llama-3.3-70b-versatile'), isTrue);
      expect(isValidModelId('openai/gpt-oss-20b'), isTrue);
      expect(isValidModelId('modèle avec espaces'), isFalse);
      expect(isValidModelId(''), isFalse);
      final settings = GroqSettings(model: 'a b', draftModel: '');
      expect(settings.validate().length, 2);
    });
  });

  test('describeCreativity couvre toute l’échelle', () {
    expect(describeCreativity(0), startsWith('Très fiable'));
    expect(describeCreativity(6), startsWith('Équilibré'));
    expect(describeCreativity(10), startsWith('Créatif'));
    expect(describeCreativity(15), startsWith('Très créatif'));
  });

  group('GroqUsage', () {
    test('agrège les journaux de génération', () {
      final usage = GroqUsage.fromRows([
        {'input_tokens': 100, 'output_tokens': 50, 'latency_ms': 400, 'success': true},
        {'input_tokens': 200, 'output_tokens': 150, 'latency_ms': 600, 'success': true},
        {'input_tokens': 10, 'output_tokens': 0, 'latency_ms': null, 'success': false},
      ]);
      expect(usage.generations, 3);
      expect(usage.failures, 1);
      expect(usage.totalTokens, 510);
      expect(usage.averageLatencyMs, 500);
      expect(usage.successPercent, 67);
    });

    test('reste cohérent sans aucune génération', () {
      final usage = GroqUsage.fromRows([]);
      expect(usage.generations, 0);
      expect(usage.averageLatencyMs, isNull);
      expect(usage.successPercent, isNull);
    });
  });
}
