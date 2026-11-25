/// Pilier de contenu : une famille de publications que la marque alterne.
class EditorialPillar {
  const EditorialPillar(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

const List<EditorialPillar> kPillars = [
  EditorialPillar('educate', 'Éduquer', 'Astuces, explications, guides'),
  EditorialPillar('inspire', 'Inspirer', 'Histoires, citations, réussites'),
  EditorialPillar('sell', 'Vendre', 'Offres, produits, résultats'),
  EditorialPillar('engage', 'Engager', 'Questions, sondages, jeux'),
  EditorialPillar('behind', 'Coulisses', 'Équipe, fabrication, quotidien'),
];

/// Dosages prêts à l'emploi (poids de 0 à 10 par pilier).
const Map<String, Map<String, int>> kPillarPresets = {
  'Équilibré': {'educate': 3, 'inspire': 2, 'sell': 2, 'engage': 2, 'behind': 1},
  'Audience': {'educate': 4, 'inspire': 3, 'sell': 0, 'engage': 3, 'behind': 1},
  'Ventes': {'educate': 2, 'inspire': 1, 'sell': 5, 'engage': 1, 'behind': 1},
  'Communauté': {'educate': 1, 'inspire': 2, 'sell': 0, 'engage': 5, 'behind': 3},
};

const int kMaxWeight = 10;
const int kMaxDescription = 600;
const int kMaxTagline = 160;
const int kMaxBannedPhrases = 20;

int _int(Object? v, int fallback) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

String _text(Object? v) => v is String ? v : '';

int _clamp(int v, int low, int high) => v < low ? low : (v > high ? high : v);

/// Stratégie éditoriale d'un espace de travail (table `editorial_strategy`).
///
/// L'objectif, le public cible et la fréquence restent dans les réglages de
/// publication : ici, on ne stocke que ce qui guide le contenu lui-même.
class EditorialStrategy {
  EditorialStrategy({
    this.businessDescription = '',
    this.brandTagline = '',
    Map<String, int>? pillarWeights,
    this.voiceFormality = 5,
    this.voiceWarmth = 5,
    List<String>? bannedPhrases,
  })  : pillarWeights = pillarWeights ?? {...kPillarPresets['Équilibré']!},
        bannedPhrases = bannedPhrases ?? [];

  factory EditorialStrategy.fromMap(Map<String, dynamic> m) {
    final defaults = EditorialStrategy();
    final raw = m['pillar_weights'];
    final weights = <String, int>{};
    for (final pillar in kPillars) {
      final value = raw is Map ? raw[pillar.id] : null;
      weights[pillar.id] = _clamp(
        _int(value, defaults.pillarWeights[pillar.id] ?? 0),
        0,
        kMaxWeight,
      );
    }
    final banned = m['banned_phrases'];
    return EditorialStrategy(
      businessDescription: _text(m['business_description']),
      brandTagline: _text(m['brand_tagline']),
      pillarWeights: weights,
      voiceFormality: _clamp(_int(m['voice_formality'], 5), 0, 10),
      voiceWarmth: _clamp(_int(m['voice_warmth'], 5), 0, 10),
      bannedPhrases: banned is List ? banned.map((e) => '$e').toList() : [],
    );
  }

  String businessDescription;
  String brandTagline;
  Map<String, int> pillarWeights;
  int voiceFormality;
  int voiceWarmth;
  List<String> bannedPhrases;

  Map<String, dynamic> toMap() => {
        'business_description': businessDescription.trim(),
        'brand_tagline': brandTagline.trim(),
        'pillar_weights': {
          for (final pillar in kPillars)
            pillar.id: pillarWeights[pillar.id] ?? 0,
        },
        'voice_formality': voiceFormality,
        'voice_warmth': voiceWarmth,
        'banned_phrases': bannedPhrases,
      };

  int get totalWeight =>
      pillarWeights.values.fold<int>(0, (sum, weight) => sum + weight);

  int get activePillars =>
      pillarWeights.values.where((weight) => weight > 0).length;

  /// Problèmes qui empêchent l'enregistrement (liste vide si tout va bien).
  List<String> validate() {
    final problems = <String>[];
    if (businessDescription.trim().length > kMaxDescription) {
      problems.add('La description de l’activité dépasse $kMaxDescription '
          'caractères.');
    }
    if (brandTagline.trim().length > kMaxTagline) {
      problems.add('La phrase de marque dépasse $kMaxTagline caractères.');
    }
    if (totalWeight <= 0) {
      problems.add('Donne du poids à au moins un pilier de contenu.');
    }
    if (bannedPhrases.length > kMaxBannedPhrases) {
      problems.add('Maximum $kMaxBannedPhrases formules à bannir.');
    }
    return problems;
  }

  /// Étapes de la « boussole » : vrai quand l'étape est complétée.
  /// [audience] vient des réglages de publication (public cible).
  List<CompassStep> compass({String? audience}) => [
        CompassStep(
          'Décrire ton activité',
          businessDescription.trim().isNotEmpty,
        ),
        CompassStep('Écrire ta phrase de marque', brandTagline.trim().isNotEmpty),
        CompassStep(
          'Définir ton public cible (Paramètres de publication)',
          audience != null && audience.trim().isNotEmpty,
        ),
        CompassStep('Activer au moins 3 piliers', activePillars >= 3),
      ];
}

class CompassStep {
  const CompassStep(this.label, this.done);

  final String label;
  final bool done;
}

/// Répartit [slots] publications entre les piliers selon leurs poids, en
/// alternant les piliers (jamais deux fois le même d'affilée si possible).
///
/// Quotas par la méthode du plus fort reste, puis ordre par tourniquet
/// pondéré lissé : le résultat est déterministe et contient exactement
/// le quota de chaque pilier.
List<String> planWeek(Map<String, int> weights, int slots) {
  final ids = [for (final p in kPillars) p.id];
  final w = {
    for (final id in ids) id: _clamp(weights[id] ?? 0, 0, kMaxWeight),
  };
  final total = w.values.fold<int>(0, (sum, v) => sum + v);
  if (slots <= 0 || total <= 0) {
    return [];
  }

  final counts = <String, int>{};
  final remainders = <String, int>{};
  var assigned = 0;
  for (final id in ids) {
    final product = w[id]! * slots;
    counts[id] = product ~/ total;
    remainders[id] = product % total;
    assigned += counts[id]!;
  }
  final byRemainder = [...ids]
    ..sort((a, b) {
      final diff = remainders[b]!.compareTo(remainders[a]!);
      return diff != 0 ? diff : ids.indexOf(a).compareTo(ids.indexOf(b));
    });
  for (var i = 0; i < slots - assigned; i++) {
    final id = byRemainder[i];
    counts[id] = counts[id]! + 1;
  }

  final current = {for (final id in ids) id: 0};
  final plan = <String>[];
  for (var step = 0; step < slots; step++) {
    String? best;
    for (final id in ids) {
      if (counts[id]! == 0) {
        continue;
      }
      current[id] = current[id]! + counts[id]!;
      if (best == null || current[id]! > current[best]!) {
        best = id;
      }
    }
    final picked = best!;
    current[picked] = current[picked]! - slots;
    plan.add(picked);
  }
  return plan;
}

/// Phrase qui résume la voix choisie, ex. « formel et chaleureux ».
String describeVoice(int formality, int warmth) {
  final tone = formality >= 7
      ? 'formel'
      : formality <= 3
          ? 'décontracté'
          : 'équilibré';
  final heat = warmth >= 7
      ? 'chaleureux'
      : warmth <= 3
          ? 'sobre'
          : 'mesuré';
  return '$tone et $heat';
}
