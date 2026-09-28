/// Le parole con cui un avviso nomina una direzione, per capire a quale
/// delle due si riferisce una deviazione letta.
///
/// Quando GTT descrive le due direzioni con due elenchi di vie — la 9 il
/// 28/09: «Direzione piazza Stampalia: … corso Vinzaglio, via Cernaia…» e
/// «Direzione corso Massimo D'Azeglio: … via Cibrario, piazza Statuto…» —
/// il modello restituisce due deviazioni, ognuna col suo `direction_desc`.
/// Il primo algoritmo usava sempre la prima per tutte e due: il tram verso
/// D'Azeglio veniva disegnato col percorso di quello verso Stampalia, al
/// contrario. MISURATO il 28/09: 21 deviazioni disegnate su 66 andavano
/// nel verso opposto alla loro direzione. La scelta la fa
/// [Ricostruzione2], con queste parole e, se non bastano, con la mappa.
class SceltaDirezione {
  const SceltaDirezione._();

  /// Il luogo nominato da una direzione, da cercare sulla mappa:
  /// «Nella sola direzione via Biscaretti» -> «via Biscaretti», «Direzione
  /// via Goito (Moncalieri)» -> «via Goito, Moncalieri». null se non
  /// nomina niente.
  static String? luogo(String? direzione) {
    if (direzione == null) return null;
    var s = direzione
        .replaceAll('\u2019', "'")
        .replaceFirst(
          RegExp(
            r'^\s*(nella sola |solo in |sola |solo |in )?direzion[ei]\s+(di\s+|del\s+|della\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAllMapped(RegExp(r'\s*\(([^)]*)\)'), (m) => ', ${m[1]}')
        .trim();
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return parole(s).isEmpty ? null : s;
  }

  /// Le parole che distinguono un capolinea, per confrontarlo col testo.
  ///
  /// Parole intere e mai i qualificatori generici: «via», «corso»,
  /// «direzione», «entrambe» compaiono ovunque e farebbero corrispondere
  /// tutto con tutto (la trappola di «lavori stradali» contro «STRADA del
  /// Drosso»).
  static Set<String> parole(String s) => s
      .toLowerCase()
      .replaceAll('’', "'")
      .split(RegExp(r"[^a-zà-ù0-9']+"))
      .map((w) => w.contains("'") ? w.substring(w.indexOf("'") + 1) : w)
      .where((w) => w.length >= 4 && !_generiche.contains(w))
      .toSet();

  static const _generiche = {
    'via',
    'viale',
    'corso',
    'piazza',
    'piazzale',
    'largo',
    'strada',
    'ponte',
    'lungo',
    'sud',
    'nord',
    'est',
    'ovest',
    'della',
    'delle',
    'dello',
    'degli',
    'linea',
    'linee',
    'direzione',
    'direzioni',
    'entrambe',
    'capolinea',
    'sola',
    'solo',
    'verso',
    'deviata',
    'deviate',
    'percorso',
  };
}
