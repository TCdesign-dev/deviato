/// Quando i dati pubblicati sono troppo vecchi per fidarsi, e da quando.
///
/// Il job pubblica ogni mezz'ora dalle 6 alle 22, poi alle 23, a
/// mezzanotte, all'una e alle tre. Di giorno due ore senza dati vogliono
/// dire quattro giri persi; di notte fra le 3:13 e le 6:13 passano tre ore
/// di regola. Dal 20 al 28/10/2026 gli avvisi di GTT non hanno risposto,
/// il job non ha pubblicato e l'app mostrava le deviazioni di sei giorni
/// prima con una sola riga in piccolo, «Aggiornate il 20/10 alle 23:20».
class DatiVecchi {
  const DatiVecchi._();

  /// Oltre quanto, a quest'[ora], i dati non sono piu' quelli di adesso.
  static Duration soglia(DateTime ora) => ora.hour >= 7 && ora.hour < 23
      ? const Duration(hours: 2)
      : const Duration(hours: 4);

  static bool sono(DateTime generato, DateTime ora) =>
      ora.difference(generato) > soglia(ora);

  /// «dalle 14:20», «da ieri alle 01:20», «da lunedì alle 23:20», «dal
  /// 20/10 alle 23:20»: il giorno della settimana solo entro sei giorni,
  /// oltre non si capirebbe di quale settimana.
  static String daQuando(DateTime t, DateTime ora) {
    String due(int n) => n.toString().padLeft(2, '0');
    final h = '${due(t.hour)}:${due(t.minute)}';
    final giorni = DateTime(
      ora.year,
      ora.month,
      ora.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    return switch (giorni) {
      0 => 'dalle $h',
      1 => 'da ieri alle $h',
      < 7 => 'da ${_giorni[t.weekday - 1]} alle $h',
      _ => 'dal ${due(t.day)}/${due(t.month)} alle $h',
    };
  }

  static const _giorni = [
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato',
    'domenica',
  ];
}
