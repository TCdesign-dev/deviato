import '../text/periodo_avviso.dart';

/// Da dove viene un avviso.
enum NoticeSource {
  /// alerts.aspx — porta il route_id gia' canonico nel 96,7% dei casi.
  gtfsRtAlert,

  /// /cms/variazioni — porta le date e la direzione in colonne separate.
  webVariazioni,
}

/// Un avviso di GTT, normalizzato, prima di qualunque interpretazione.
///
/// Non contiene geometrie ne' deduzioni: solo cio' che GTT ha detto, con
/// l'indicazione di dove l'ha detto. Serve a poter sempre mostrare
/// all'utente il testo originale accanto a qualunque cosa il sistema
/// concluda (§6.2): se sbagliamo, il dato grezzo resta a disposizione.
class RawNotice {
  const RawNotice({
    required this.id,
    required this.source,
    required this.text,
    required this.sourceUrl,
    this.headline,
    this.routeIds = const [],
    this.lineHints = const [],
    this.directionHint,
    this.reason,
    this.effect,
    this.validFrom,
    this.validUntil,
    this.mergedFrom = const [],
  });

  final String id;
  final NoticeSource source;

  /// Titolo, quando la fonte ne ha uno ("Linea 82 deviata in direzione...").
  final String? headline;

  /// Il testo completo, come l'ha scritto GTT.
  final String text;

  /// route_id gia' canonici, quando la fonte li fornisce.
  /// Dagli alert arrivano gratis: niente tabella alias da consultare.
  final List<String> routeIds;

  /// Nomi di linea grezzi da risolvere ("6 – 68+ - STAR 1").
  final List<String> lineHints;

  final String? directionHint;
  final String? reason;

  /// Effetto GTFS-RT: DETOUR, NO_SERVICE, MODIFIED_SERVICE...
  /// DETOUR e' un pre-filtro utile: 109 alert su 180 lo erano.
  final String? effect;

  final DateTime? validFrom;
  final DateTime? validUntil;

  final String sourceUrl;

  /// Gli avvisi originali, quando le due fonti raccontavano la stessa
  /// variazione e sono stati uniti (vedi [NoticeMerge]). Vuoto altrimenti.
  ///
  /// Si conservano interi apposta: di un avviso unito si mostra il testo
  /// piu' completo, ma quello scartato non e' perduto — il testo di GTT
  /// deve restare disponibile comunque (§6.2).
  final List<RawNotice> mergedFrom;

  bool get isMerged => mergedFrom.length > 1;

  /// Le fonti che hanno pubblicato questa variazione.
  Set<NoticeSource> get sources =>
      isMerged ? mergedFrom.map((n) => n.source).toSet() : {source};

  /// Tutti i testi che parlano di questa variazione: il proprio e quelli
  /// degli avvisi uniti. Serve a cercare i dati certi — i codici delle
  /// fermate — in TUTTO quello che GTT ha scritto, non solo nel testo che
  /// si e' scelto di mostrare.
  Iterable<String> get allTexts => [
    fullText,
    ...mergedFrom.map((n) => n.fullText),
  ];

  /// Quando vale la variazione, letto dal testo. Si legge una volta.
  ///
  /// Il feed data gli avvisi con l'ora di PUBBLICAZIONE (MISURATO il
  /// 01/08/2026: 161 su 161 gia' cominciati): l'inizio vero, la fine, i
  /// giorni e le fasce orarie li scrive solo il testo. Il 04/10/2026, su 97
  /// avvisi pubblicati, il testo dava l'inizio in 96: la 65 «dalle 8:00 di
  /// lunedì 5 ottobre» risultava in corso da venerdi', e sette avvisi delle
  /// sere di meta' settembre sulla 3106 e la 4108 non erano mai finiti.
  PeriodoAvviso get periodo =>
      _periodi[this] ??= PeriodoAvviso.leggi(fullText, pubblicato: validFrom);

  static final _periodi = Expando<PeriodoAvviso>('periodo');

  /// Le date della tabella delle variazioni sono vere, scritte a mano in
  /// una colonna: quando ci sono valgono loro, non quelle lette dal testo.
  bool get _dateVere => sources.contains(NoticeSource.webVariazioni);

  /// Il periodo letto dal testo, se c'e' e se non ci sono date migliori.
  PeriodoAvviso? get _dalTesto =>
      !_dateVere && periodo.trovato ? periodo : null;

  /// A che punto e' la variazione [ora]: in corso, in programma, finita, o
  /// in vigore ma non in questo giorno od orario. Dal testo, se ne dice le
  /// date; se no dalla data del feed, che al massimo la fa sembrare gia'
  /// cominciata.
  StatoPeriodo statoAl(DateTime ora) {
    if (_dalTesto case final p?) return p.stato(ora);
    final from = validFrom;
    if (from == null) return StatoPeriodo.inCorso;
    final oggi = DateTime(ora.year, ora.month, ora.day);
    return DateTime(from.year, from.month, from.day).isAfter(oggi)
        ? StatoPeriodo.inProgramma
        : StatoPeriodo.inCorso;
  }

  /// La variazione deve ancora cominciare?
  ///
  /// MISURATO (01/08/2026): 9 righe su 47 della tabella `/cms/variazioni`
  /// partono in futuro — una anche a 23 giorni di distanza. Trattarle come
  /// le altre significherebbe dire "la tua fermata non e' servita" per
  /// qualcosa che comincia fra tre settimane.
  bool startsAfter(DateTime now) => statoAl(now) == StatoPeriodo.inProgramma;

  /// Da quando vale, da dire a chi legge. Di un elenco di giorni, il
  /// prossimo.
  DateTime? inizioDaDire(DateTime ora) {
    final p = _dalTesto;
    if (p == null) return validFrom;
    if (p.giorni.isNotEmpty) {
      final oggi = DateTime(ora.year, ora.month, ora.day);
      return p.giorni.where((g) => !g.isBefore(oggi)).firstOrNull ??
          p.giorni.last;
    }
    return p.inizio;
  }

  /// Quanti giorni mancano all'inizio: 0 se comincia oggi, piu' tardi.
  /// null se e' gia' cominciata.
  int? daysUntilStart(DateTime now) {
    if (!startsAfter(now)) return null;
    final from = inizioDaDire(now);
    if (from == null) return null;
    return DateTime(
      from.year,
      from.month,
      from.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// In quali giorni o orari vale, se non sempre: «solo il sabato, dalle
  /// 6:00 alle 15:00». null se tutto il giorno, tutti i giorni.
  String? get fasciaDaDire => _dalTesto?.fascia;

  /// Testo su cui cercare: titolo piu' corpo.
  String get fullText =>
      headline == null || headline!.isEmpty ? text : '$headline $text';

  /// La fine da dire a chi legge: [validUntil], se e' una fine vera.
  ///
  /// «Sino a nuove comunicazioni» nel feed diventa una data un anno dopo:
  /// il 29/09/2026 la 68 risultava «non servita fino al 08/09», cioe' al
  /// 08/09/2027, e sembrava una data gia' passata. Si scarta se il testo
  /// dice che la fine non c'e', o se e' a piu' di 300 giorni dall'inizio.
  DateTime? get endToShow {
    // La fine scritta nel testo, se c'e': quella del feed e' spesso un
    // anno dopo la pubblicazione.
    if (_dalTesto case final p?) {
      if (p.fine case final f?) {
        // «A fine servizio di martedì 15» finisce alle 2 di notte, ma per
        // chi legge e' martedì 15.
        return f.hour < 3 ? DateTime(f.year, f.month, f.day - 1, 23, 59) : f;
      }
      if (p.giorni.isNotEmpty) return p.giorni.last;
    }
    final fine = validUntil;
    if (fine == null || allTexts.any(_senzaFine.hasMatch)) return null;
    final inizio = validFrom;
    if (inizio != null && fine.difference(inizio).inDays > 300) return null;
    return fine;
  }

  static final _senzaFine = RegExp(
    r'(sino|fino) a (nuove comunicazioni|nuovo avviso|data da destinarsi)',
    caseSensitive: false,
  );

  /// L'avviso parla di una variazione di percorso?
  /// Serve a scartare gli avvisi su ascensori, sciopero, orari estivi.
  bool get mentionsRouteChange => allTexts.any(_routeChange.hasMatch);

  /// Codici delle fermate sospese, estratti dal TESTO.
  ///
  /// MISURATO: negli alert il campo strutturato `informed_entity.stop_id`
  /// NON contiene le fermate impattate ma tutte quelle della linea (linea
  /// 82: 31 dichiarate = 31 fermate totali). I codici veri stanno nel
  /// testo, in avvisi dedicati tipo `Fermata 3447 "Sabotino" sospesa`.
  ///
  /// GTT usa forme diverse: `Fermata 3447`, `fermata n. 15080`,
  /// `Fermata n° 3445`, `fermata n.1182`.
  ///
  /// Si cerca in TUTTI i testi: di un avviso unito si mostra il piu'
  /// completo, ma un codice di fermata scritto solo nell'altro resta il
  /// dato piu' certo che il sistema abbia, e perderlo per una scelta di
  /// impaginazione sarebbe assurdo.
  List<String> get suspendedStopCodes {
    final out = <String>{};
    for (final text in allTexts) {
      for (final m in _stopCode.allMatches(text)) {
        final code = m.group(1);
        if (code != null) out.add(code);
      }
    }
    return out.toList();
  }

  static final _routeChange = RegExp(
    r'deviat|limitat|sospes|soppress|capolinea provvisorio|'
    r'inversione di marcia|non transita|percorso normale|prosegue per',
    caseSensitive: false,
  );

  static final _stopCode = RegExp(
    r'fermat[ae]\s*(?:n[.°]?\s*)?(\d{1,5})',
    caseSensitive: false,
  );

  @override
  String toString() => '[$id] ${headline ?? text.substring(0, 40)}';
}
