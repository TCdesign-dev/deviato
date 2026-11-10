import 'extractor.dart';

/// Legge senza modello gli avvisi scritti nello schema fisso di GTT:
///
///   «Direzione X: da via A angolo via B deviata per via C, via D,
///   percorso normale.»
///
/// Un modello linguistico non e' un algoritmo: puo' cambiare, sparire (il
/// 29/10/2026), o rispondere diverso. Dove il testo segue lo schema la
/// lettura e' una regola, sempre uguale e senza quota. E' prudente di
/// proposito: basta un pezzo che non torna — «ove effettua inversione di
/// marcia», una fermata provvisoria, un capolinea — e restituisce null, e
/// l'avviso lo legge il modello come prima. Meglio leggerne pochi giusti.
class LettoreARegole {
  const LettoreARegole._();

  /// Le deviazioni di [titolo] e [testo], o null se non seguono lo schema.
  static List<ParsedDeviation>? leggi(String titolo, String testo) {
    final t = _pulisci(testo);
    final tit = _pulisci(titolo);
    // Solo deviazioni: limitazioni e sospensioni hanno altre parole, e un
    // altro significato.
    final tutto = '$tit $t'.toLowerCase();
    if (!tutto.contains('deviat')) return null;
    if (_altro.hasMatch(tutto)) return null;

    // Un pezzo per direzione, se il testo le distingue.
    final capi = _direzione.allMatches(t).toList();
    final pezzi = <({String? verso, String testo})>[];
    if (capi.isEmpty) {
      final nelTitolo = _direzioneNelTitolo.firstMatch(tit)?[1]?.trim();
      pezzi.add((verso: nelTitolo, testo: t));
    } else {
      for (var i = 0; i < capi.length; i++) {
        final fine = i + 1 < capi.length ? capi[i + 1].start : t.length;
        pezzi.add((
          verso: capi[i][1]!.trim(),
          testo: t.substring(capi[i].end, fine),
        ));
      }
    }

    final out = <ParsedDeviation>[];
    for (final p in pezzi) {
      // «Direzione X: percorso regolare.»: quella direzione non devia.
      if (_soloRegolare.hasMatch(p.testo)) continue;
      final m = _schema.firstMatch(p.testo);
      if (m == null) return null;
      final stacco = m[1]!.trim(), angolo = m[2]?.trim();
      final vie = [for (final v in m[3]!.split(',')) v.trim()];
      if (!_via(stacco) || (angolo != null && !_via(angolo))) return null;
      if (vie.isEmpty || !vie.every(_via)) return null;
      // Dopo «percorso normale» puo' restare solo la causa.
      if (!_coda.hasMatch(p.testo.substring(m.end))) return null;
      out.add(
        ParsedDeviation.fromJson({
          'deviation_type': 'deviazione',
          'direction_desc': ?p.verso,
          'detach_point': {'street': stacco, 'cross_street': ?angolo},
          'via_sequence': [
            for (final v in vie) {'street': v},
          ],
        }),
      );
    }
    return out.isEmpty ? null : out;
  }

  static String _pulisci(String s) => s
      .replaceAll(RegExp('[’‘`´]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final _direzione = RegExp(
    r'\b(?:nella sola )?direzione (?:di )?([^:.]{2,60}):',
    caseSensitive: false,
  );

  static final _direzioneNelTitolo = RegExp(
    r'\bin direzione ([^.]{2,60}?)\.?$',
    caseSensitive: false,
  );

  static final _soloRegolare = RegExp(
    r'^\s*(?:segue |effettua )?(?:il )?percorso (?:normale|regolare)\.?\s*$',
    caseSensitive: false,
  );

  /// da A [angolo B] deviata|prosegue per|in|su C, D, … percorso normale
  static final _schema = RegExp(
    r"\bda ([^,;:.]{3,70}?)(?: angolo ([^,;:.]{3,70}?))?,? "
    r"(?:(?:è |e' |viene |sono |vengono )?deviat[aoei]|prosegue|proseguono|devia|deviano) "
    r"(?:per|in|su|lungo) "
    r"([^;:]{3,600}?),? "
    r"(?:quindi |poi |e )?(?:segue |riprende |seguono |riprendono )?(?:il )?"
    r"(?:normale percorso|percorso (?:normale|regolare))",
    caseSensitive: false,
  );

  /// Quello che puo' seguire lo schema: niente, la causa, o altre frasi
  /// che non parlano piu' di percorso.
  static final _coda = RegExp(
    r"^(?!.*\b(?:devia|prosegu|direzione|fermat|percorso|capolinea|"
    r"transit|limitat|dopo|prima)).{0,400}$",
    caseSensitive: false,
  );

  /// Parole che dicono che l'avviso fa anche altro: non e' lo schema.
  static final _altro = RegExp(
    r'\b(?:limitat|capolinea|inversione|fermata provvisoria|non transit|'
    r'non effettu|soppress|navetta|sostitu|sospes)',
  );

  /// Un nome di via, e nient'altro: comincia col tipo di strada e non ha
  /// verbi o indicazioni dentro.
  static bool _via(String s) =>
      s.length <= 70 && _tipo.hasMatch(s) && !_nonVia.hasMatch(s);

  static final _tipo = RegExp(
    r"^(?:via|viale|corso|c\.so|piazza|p\.za|piazzale|piazzetta|largo|"
    r"strada|stradale|lungo ?po|lungodora|lungo dora|lungostura|ponte|"
    r"rond[oò]'?|rotonda|sottopasso|cavalcavia|tangenziale|"
    r"s\.? ?[psr]\.?|strada (?:provinciale|statale|regionale))\b",
    caseSensitive: false,
  );

  static final _nonVia = RegExp(
    r'\b(?:ove|dove|quindi|poi|fino|sino|fermata|direzione|svolta|'
    r'prosegue|effettua|presso|percorso|carreggiata|altezza|rotatoria)\b',
    caseSensitive: false,
  );
}
