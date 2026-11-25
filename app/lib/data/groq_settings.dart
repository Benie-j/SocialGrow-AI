/// Identifiants de modèles proposés en exemple (la liste de Groq évolue :
/// l'utilisateur peut saisir n'importe quel identifiant valide).
const List<String> kGroqModelExamples = [
  'llama-3.3-70b-versatile',
  'llama-3.1-8b-instant',
  'openai/gpt-oss-20b',
  'openai/gpt-oss-120b',
];

const int kMaxCreativity = 15;
const int kMinOutputTokens = 100;
const int kMaxOutputTokens = 2000;
const int kMinMonthlyLimit = 1;
const int kMaxMonthlyLimit = 10000;

final RegExp _modelPattern = RegExp(r'^[A-Za-z0-9._/:-]{1,100}$');

bool isValidModelId(String value) => _modelPattern.hasMatch(value.trim());

int _int(Object? v, int fallback) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

int _clamp(int v, int low, int high) => v < low ? low : (v > high ? high : v);

String _model(Object? v, String fallback) =>
    v is String && v.trim().isNotEmpty ? v.trim() : fallback;

/// Réglages de génération Groq d'un espace (table `groq_settings`).
class GroqSettings {
  GroqSettings({
    this.model = 'llama-3.3-70b-versatile',
    this.draftModel = 'llama-3.1-8b-instant',
    this.creativity = 7,
    this.maxOutputTokens = 500,
    this.monthlyGenerationLimit = 300,
  });

  factory GroqSettings.fromMap(Map<String, dynamic> m) {
    final d = GroqSettings();
    return GroqSettings(
      model: _model(m['model'], d.model),
      draftModel: _model(m['draft_model'], d.draftModel),
      creativity: _clamp(
        _int(m['creativity'], d.creativity),
        0,
        kMaxCreativity,
      ),
      maxOutputTokens: _clamp(
        _int(m['max_output_tokens'], d.maxOutputTokens),
        kMinOutputTokens,
        kMaxOutputTokens,
      ),
      monthlyGenerationLimit: _clamp(
        _int(m['monthly_generation_limit'], d.monthlyGenerationLimit),
        kMinMonthlyLimit,
        kMaxMonthlyLimit,
      ),
    );
  }

  /// Modèle des textes finaux.
  String model;

  /// Modèle plus léger pour les brouillons et variantes.
  String draftModel;

  /// 0 (très fiable) à 15 (très créatif) ; température envoyée = valeur / 10.
  int creativity;

  int maxOutputTokens;
  int monthlyGenerationLimit;

  double get temperature => creativity / 10;

  Map<String, dynamic> toMap() => {
        'model': model.trim(),
        'draft_model': draftModel.trim(),
        'creativity': creativity,
        'max_output_tokens': maxOutputTokens,
        'monthly_generation_limit': monthlyGenerationLimit,
      };

  /// Problèmes qui empêchent l'enregistrement (liste vide si tout va bien).
  List<String> validate() {
    final problems = <String>[];
    if (!isValidModelId(model)) {
      problems.add('Le modèle principal est invalide (lettres, chiffres, '
          '. _ / : - uniquement).');
    }
    if (!isValidModelId(draftModel)) {
      problems.add('Le modèle de brouillon est invalide (lettres, chiffres, '
          '. _ / : - uniquement).');
    }
    return problems;
  }
}

/// Libellé de la créativité choisie.
String describeCreativity(int creativity) {
  if (creativity <= 3) {
    return 'Très fiable : textes sobres et prévisibles';
  }
  if (creativity <= 7) {
    return 'Équilibré : naturel sans prise de risque';
  }
  if (creativity <= 11) {
    return 'Créatif : tournures plus variées';
  }
  return 'Très créatif : surprenant, à relire de près';
}

/// Consommation réelle de l'espace, calculée depuis `ai_generation_logs`.
class GroqUsage {
  const GroqUsage({
    required this.generations,
    required this.failures,
    required this.inputTokens,
    required this.outputTokens,
    required this.averageLatencyMs,
  });

  factory GroqUsage.fromRows(List<Map<String, dynamic>> rows) {
    var failures = 0;
    var input = 0;
    var output = 0;
    var latencyTotal = 0;
    var latencyCount = 0;
    for (final row in rows) {
      if (row['success'] == false) {
        failures++;
      }
      input += _int(row['input_tokens'], 0);
      output += _int(row['output_tokens'], 0);
      final latency = row['latency_ms'];
      if (latency is num) {
        latencyTotal += latency.toInt();
        latencyCount++;
      }
    }
    return GroqUsage(
      generations: rows.length,
      failures: failures,
      inputTokens: input,
      outputTokens: output,
      averageLatencyMs: latencyCount == 0 ? null : latencyTotal ~/ latencyCount,
    );
  }

  final int generations;
  final int failures;
  final int inputTokens;
  final int outputTokens;
  final int? averageLatencyMs;

  int get totalTokens => inputTokens + outputTokens;

  /// Part de générations réussies, en pourcentage (null s'il n'y en a aucune).
  int? get successPercent => generations == 0
      ? null
      : ((generations - failures) * 100 / generations).round();
}
