/// Délai minimum entre maintenant et l'heure choisie : le serveur vérifie les
/// publications échues chaque minute, on garde une marge confortable.
const int kMinScheduleLeadMinutes = 5;

/// Horizon maximum de planification.
const int kMaxScheduleDays = 365;

const _weekdays = [
  'lun.',
  'mar.',
  'mer.',
  'jeu.',
  'ven.',
  'sam.',
  'dim.',
];

const _months = [
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

/// « jeu. 26 nov. 2026 à 09:05 » (heure locale).
String formatScheduleWhen(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} '
      '${d.year} à $hh:$mm';
}

/// Message d'erreur si [at] n'est pas un horaire valide, sinon null.
String? validateScheduleTime(DateTime at, DateTime now) {
  if (at.isBefore(now.add(const Duration(minutes: kMinScheduleLeadMinutes)))) {
    return 'Choisis un horaire au moins $kMinScheduleLeadMinutes minutes '
        'dans le futur.';
  }
  if (at.isAfter(now.add(const Duration(days: kMaxScheduleDays)))) {
    return 'Tu peux planifier jusqu’à $kMaxScheduleDays jours à l’avance.';
  }
  return null;
}
