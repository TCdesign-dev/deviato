import '../models/transit.dart';
import '../pipeline/extractor.dart';

/// Quale delle deviazioni lette in un avviso vale per una direzione.
///
/// Quando GTT descrive le due direzioni con due elenchi di vie — la 9 il
/// 28/09: «Direzione piazza Stampalia: … corso Vinzaglio, via Cernaia…» e
/// «Direzione corso Massimo D'Azeglio: … via Cibrario, piazza Statuto…» —
/// il modello restituisce due deviazioni, ognuna col suo `direction_desc`.
/// Il primo algoritmo usava sempre la prima per tutte e due: il tram verso
/// D'Azeglio veniva disegnato col percorso di quello verso Stampalia, al
/// contrario. MISURATO il 28/09: 21 deviazioni disegnate su 66 andavano
/// nel verso opposto alla loro direzione.
class SceltaDirezione {
  const SceltaDirezione._();

  /// La deviazione di [letture] per [shape].
  ///
  /// [esplicita] vale quando la deviazione nomina il capolinea di questa
  /// direzione: allora il suo ordine di vie e' quello giusto. Altrimenti e'
  /// una deviazione senza direzione (vale per tutte e due, e il verso va
  /// controllato sulla mappa) o, in mancanza d'altro, la prima.
  static ({ParsedDeviation deviazione, bool esplicita}) per(
    List<ParsedDeviation> letture,
    RouteShape shape,
  ) {
    final capolinea = parole(shape.headsign);
    final nominano = [
      for (final d in letture)
        if (parole(d.directionDesc ?? '').any(capolinea.contains)) d,
    ];
    if (nominano.length == 1) {
      return (deviazione: nominano.first, esplicita: true);
    }
    // Una deviazione che non nomina nessun capolinea vale per tutte e due.
    // Una che ne nomina uno diverso dal nostro e' dell'altra direzione: si
    // prende solo se non c'e' nient'altro.
    final senzaDirezione = [
      for (final d in letture)
        if (parole(d.directionDesc ?? '').isEmpty) d,
    ];
    return (
      deviazione: senzaDirezione.isNotEmpty
          ? senzaDirezione.first
          : letture.first,
      esplicita: false,
    );
  }

  /// Le deviazioni che non nominano il capolinea di [shape]: le candidate
  /// quando nessuna lo nomina, da scegliere guardando il verso sulla mappa.
  static List<ParsedDeviation> candidate(
    List<ParsedDeviation> letture,
    RouteShape shape,
  ) {
    final capolinea = parole(shape.headsign);
    return [
      for (final d in letture)
        if (!parole(d.directionDesc ?? '').any(capolinea.contains)) d,
    ];
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
