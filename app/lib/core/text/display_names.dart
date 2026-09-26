import '../models/transit.dart';

/// I nomi di GTT, scritti come si leggono.
///
/// Il GTFS scrive tutto in maiuscolo: «Fermata 422 - LARGO GIACHINO SUD»,
/// «NAVETTA, PIAZZA XVIII DICEMBRE». Il maiuscolo si legge più lentamente
/// — le parole perdono la loro sagoma — e in un elenco di sedici fermate
/// sembra che l'app stia urlando. Qui si riportano in minuscolo, con le
/// eccezioni che servono: numeri romani, preposizioni, apostrofi.
///
/// Sta in `core/` perché è Dart puro e si prova senza Flutter.
class DisplayNames {
  const DisplayNames._();

  /// «Fermata 422 - LARGO GIACHINO SUD» → «Largo Giachino Sud».
  ///
  /// Il codice si toglie perché si mostra a parte, più piccolo: è quello
  /// scritto sul palo, e serve a riconoscerla, non a leggerla.
  static String stop(TransitStop s) {
    final senza = s.name.replaceFirst(_prefissoFermata, '').trim();
    return titleCase(senza.isEmpty ? s.name : senza);
  }

  /// Da dove a dove va un percorso, per dirlo dopo «verso».
  ///
  /// Il capolinea sta nell'ultima parte del headsign («NAVETTA, VIA
  /// MASSARI»): la prima è spesso un'etichetta uguale per le due direzioni,
  /// e la legenda diceva «→ NAVETTA» due volte. Se il nome lungo della
  /// linea lo contiene già scritto bene («via Massari - piazza XVIII
  /// Dicembre») si usa quello.
  static String direction(String headsign, {String? longName}) {
    final parti = headsign
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final capolinea = parti.isEmpty ? headsign.trim() : parti.last;
    if (longName != null) {
      // «CAFASSO» nel headsign, «via Cafasso» nel nome lungo: il tipo di
      // strada spesso manca da una parte sola, e basta che finisca uguale.
      //
      // Il qualificatore davanti si toglie prima: nella 7, «circolare Tram
      // Storici, piazza Castello - Porta Nuova», la prima parte finiva con
      // «piazza Castello» e la legenda diceva «→ circolare Tram Storici,…».
      final cercato = _norm(capolinea);
      final percorso = routeParts(longName).route;
      for (final t in percorso.split(RegExp(r'\s+[-–]\s+'))) {
        if (cercato.isNotEmpty && _norm(t).endsWith(cercato)) return t.trim();
      }
    }
    final nome = titleCase(capolinea);
    final primo = nome.split(' ').first;
    // «verso piazza XVIII Dicembre», non «verso Piazza»: dopo una
    // preposizione il tipo di strada si scrive minuscolo.
    return _tipiDiStrada.contains(primo.toLowerCase())
        ? primo.toLowerCase() + nome.substring(primo.length)
        : nome;
  }

  /// Il nome lungo di una linea, diviso in percorso e qualificatore.
  ///
  /// GTT mette davanti ai capolinea quando la linea circola: «feriale,
  /// corso Vercelli (Park Stura) - corso Bolzano», «notturna, piazza
  /// Vittorio Veneto - via Massari», «lunedì-venerdì, …». Nella ricerca
  /// delle linee il percorso va su una riga e il qualificatore sotto,
  /// piu' piccolo: e' un dettaglio, non il nome.
  static ({String route, String? qualifier}) routeParts(String longName) {
    final virgola = longName.indexOf(', ');
    if (virgola > 0) {
      final testa = longName.substring(0, virgola);
      final resto = longName.substring(virgola + 2);
      // Il qualificatore e' corto e non contiene capolinea: se la parte
      // prima della virgola ha gia' il trattino, la virgola e' dentro un
      // nome («piazza Dalla Chiesa, Orbassano») e non si tocca.
      if (!testa.contains(' - ') && resto.contains(' - ')) {
        return (route: _trattino(resto), qualifier: testa);
      }
    }
    return (route: _trattino(longName), qualifier: null);
  }

  /// «via Massari - piazza XVIII Dicembre» con la lineetta tipografica.
  static String _trattino(String s) => s.replaceAll(' - ', ' – ');

  /// Il motivo, in italiano, o null se non dice niente.
  ///
  /// Dal feed arriva il codice GTFS-RT («OTHER_CAUSE», «MAINTENANCE»),
  /// dalla tabella web testo libero («Lavori di rifacimento del ponte
  /// Rossini»). Il codice va tradotto; «altra causa» e «causa
  /// sconosciuta» non si mostrano, perché occupano una riga per dire che
  /// non si sa.
  static String? reason(String? raw) {
    final r = raw?.trim();
    if (r == null || r.isEmpty) return null;
    if (!_codice.hasMatch(r)) return r;
    return _motivi[r];
  }

  static String titleCase(String s) {
    final parole = s.trim().split(RegExp(r'\s+'));
    return [
      for (var i = 0; i < parole.length; i++) _parola(parole[i], i == 0),
    ].join(' ');
  }

  static String _parola(String w, bool prima) {
    if (w.length > 1 && _romano.hasMatch(w)) return w;
    if (_sigle.contains(w.toUpperCase())) return w.toUpperCase();
    if (w.toUpperCase() == 'CAP') return 'capolinea';
    // «DELL'ARTE» → «dell'Arte»: la parte prima dell'apostrofo è un
    // articolo, quella dopo il nome.
    final apostrofo = RegExp("['’]").firstMatch(w);
    if (apostrofo != null) {
      final articolo = w.substring(0, apostrofo.start);
      final nome = w.substring(apostrofo.end);
      final testa = prima ? _maiuscola(articolo) : articolo.toLowerCase();
      return "$testa'${_maiuscola(nome)}";
    }
    final minuscola = w.toLowerCase();
    if (!prima && _minuscole.contains(minuscola)) return minuscola;
    return w.split('-').map(_maiuscola).join('-');
  }

  static String _maiuscola(String w) {
    if (w.isEmpty) return w;
    final m = w.toLowerCase();
    return m[0].toUpperCase() + m.substring(1);
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ù]'), '');

  static final _prefissoFermata =
      RegExp(r'^fermata\s+\d+\s*[-–]\s*', caseSensitive: false);
  static final _romano = RegExp(r'^[IVXLC]+$');
  static final _codice = RegExp(r'^[A-Z_]+$');

  static const _minuscole = {
    'di', 'del', 'della', 'dello', 'dei', 'degli', 'delle', 'da', 'dal',
    'dalla', 'dai', 'a', 'al', 'alla', 'ai', 'e', 'ed', 'in', 'per', 'su',
    'sul', 'sulla', 'con', 'lo', 'la', 'le', 'il', 'gli',
  };

  /// Le sigle restano sigle: «Stabilimento GTT Tortona», non «Gtt».
  static const _sigle = {'GTT', 'FS', 'RFI', 'ASL', 'INPS', 'ATC', 'SFM'};

  static const _tipiDiStrada = {
    'via', 'viale', 'corso', 'piazza', 'piazzale', 'largo', 'strada',
    'lungo', 'lungodora', 'lungopo', 'vicolo', 'borgata', 'frazione',
  };

  static const _motivi = {
    'TECHNICAL_PROBLEM': 'problema tecnico',
    'STRIKE': 'sciopero',
    'DEMONSTRATION': 'manifestazione',
    'ACCIDENT': 'incidente',
    'HOLIDAY': 'festività',
    'WEATHER': 'maltempo',
    'MAINTENANCE': 'manutenzione',
    'CONSTRUCTION': 'lavori',
    'POLICE_ACTIVITY': 'intervento delle forze dell\'ordine',
    'MEDICAL_EMERGENCY': 'emergenza sanitaria',
  };
}
