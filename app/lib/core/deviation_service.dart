import 'geo/projection.dart';
import 'llm/llm_client.dart';
import 'llm/llm_con_budget.dart';
import 'models/notice.dart';
import 'models/transit.dart';
import 'pipeline/extractor.dart';
import 'pipeline/geocoder.dart';
import 'pipeline/line_resolver.dart';
import 'pipeline/notice_merge.dart';
import 'pipeline/rejoin_inference.dart';
import 'pipeline/route_builder.dart';
import 'pipeline/stop_impact.dart';
import 'ricostruzione/ricostruzione.dart';
import 'ricostruzione/ricostruzione_1.dart';
import 'ricostruzione/ricostruzione_2.dart';
import 'sources/alerts_source.dart';
import 'sources/variazioni_source.dart';

/// Quanto fidarsi di quello che il sistema dice.
enum Confidence {
  /// Geometria ricostruita e superate tutte le prove.
  confermata,

  /// C'e' una geometria ma qualche verifica non torna: si mostra con
  /// riserva, accanto al testo originale.
  probabile,

  /// GTT dichiara una variazione ma non siamo riusciti a ricostruirla.
  /// Si mostra SOLO il testo di GTT: mai una mappa inventata.
  soloTesto,
}

/// Cosa succede a una linea per via di un singolo avviso.
class DeviationReport {
  const DeviationReport({
    required this.notice,
    required this.confidence,
    required this.shape,
    this.parsed,
    this.deviatedGeometry,
    this.impact,
    this.whyIncomplete,
    this.rejoin,
    this.retryable = false,
    this.algoritmo = 1,
  });

  final RawNotice notice;

  /// Il percorso su cui e' stato calcolato: linea PIU' DIREZIONE.
  ///
  /// La specifica (§10.9) e' esplicita: mai modellare una deviazione a
  /// livello di linea, perche' quasi tutte sono asimmetriche. GTT infatti
  /// scrive "nella sola direzione Derna", e la 94 ha due avvisi distinti
  /// per le due direzioni. Calcolare le fermate saltate sempre contro
  /// l'andata darebbe fermate sbagliate per meta' degli avvisi.
  final RouteShape shape;

  final Confidence confidence;
  final ParsedDeviation? parsed;
  final List<GeoPoint>? deviatedGeometry;
  final StopImpactResult? impact;

  /// Perche' non siamo arrivati fino in fondo. Va mostrato: dire "non ho
  /// saputo ricostruirlo" e' onesto, disegnare un percorso a caso no.
  final String? whyIncomplete;

  /// Dove rientra il mezzo, e se lo ha detto GTT o l'abbiamo dedotto.
  final RejoinPoint? rejoin;

  /// L'esito e' incompleto per un motivo che passa: quota esaurita, rete
  /// assente, un servizio giu'. Al prossimo controllo l'avviso si rilegge.
  ///
  /// Gli altri esiti, anche incompleti («l'avviso non indica abbastanza
  /// vie»), non cambierebbero rileggendo lo stesso testo: si tengono, e
  /// non si spende un'altra delle cinquanta richieste giornaliere.
  final bool retryable;

  /// Quale algoritmo l'ha calcolato ([AlgoritmoPercorsi.numero]). Cambiando
  /// algoritmo nel job, gli esiti dell'altro non si tengono.
  final int algoritmo;

  bool get hasMap => deviatedGeometry != null && deviatedGeometry!.length > 1;
  List<StopImpact> get skippedStops => impact?.skipped ?? const [];

  DeviationReport withImpact(StopImpactResult? impact) =>
      _copia(impact: impact, algoritmo: algoritmo);

  DeviationReport conAlgoritmo(int algoritmo) =>
      _copia(impact: impact, algoritmo: algoritmo);

  DeviationReport _copia({
    required StopImpactResult? impact,
    required int algoritmo,
  }) =>
      DeviationReport(
        notice: notice,
        confidence: confidence,
        shape: shape,
        parsed: parsed,
        deviatedGeometry: deviatedGeometry,
        impact: impact,
        whyIncomplete: whyIncomplete,
        rejoin: rejoin,
        retryable: retryable,
        algoritmo: algoritmo,
      );

  /// Le alternative di ogni avviso, tolte le fermate chiuse dagli ALTRI.
  ///
  /// Gli avvisi si analizzano uno per uno, e ognuno sa solo delle fermate
  /// che chiude lui. Qui si guarda la linea intera. Gli avvisi in corso si
  /// confrontano con quelli in corso; quelli in programma con tutti,
  /// perche' non si sa se quelli di adesso saranno finiti.
  ///
  /// Sta qui e non dentro [DeviationService.statusOf] perche' serve anche
  /// agli esiti salvati: quelli di prima di questa correzione avevano le
  /// alternative sbagliate scritte dentro.
  static List<DeviationReport> reconcileAlternatives(
    List<DeviationReport> reports, {
    required StopImpactAnalyzer analyzer,
    required DateTime now,
  }) {
    Set<String> chiuse(Iterable<DeviationReport> rs) =>
        {for (final r in rs) ...r.skippedStops.map((s) => s.stop.id)};
    final adesso = chiuse(reports.where((r) => !r.notice.startsAfter(now)));
    final tutte = chiuse(reports);
    if (tutte.isEmpty) return reports;

    return [
      for (final r in reports)
        if (r.impact == null || !r.impact!.hasImpact)
          r
        else
          r.withImpact(analyzer.excludingClosed(
            r.impact!,
            officialRoute: r.shape,
            deviatedRoute: r.deviatedGeometry,
            closedStopIds: r.notice.startsAfter(now) ? tutte : adesso,
          )),
    ];
  }
}

/// Stato completo di una linea.
class LineStatus {
  const LineStatus({
    required this.line,
    required this.shape,
    required this.reports,
    required this.checkedAt,
    this.shapeReturn,
    this.allShapes = const [],
  });

  final TransitLine line;

  /// La variante principale dell'andata.
  final RouteShape shape;

  /// La variante principale del ritorno, se la linea ne ha una.
  /// Una linea circolare puo' non averla.
  final RouteShape? shapeReturn;

  /// TUTTE le varianti della linea. Servono all'osservazione dei mezzi:
  /// un mezzo sulla corsa limitata non sta deviando, e confrontarlo solo
  /// con la principale lo farebbe sembrare fuori rotta.
  final List<RouteShape> allShapes;
  final List<DeviationReport> reports;
  final DateTime checkedAt;

  bool get hasDeviations => reports.isNotEmpty;

  /// I percorsi da disegnare: andata e ritorno.
  List<RouteShape> get mainShapes => [shape, ?shapeReturn];

  /// Quello che sta succedendo ADESSO.
  ///
  /// La domanda dell'utente e' al presente — "la mia fermata e' servita?"
  /// — e rispondere contando una deviazione che comincia fra tre
  /// settimane sarebbe una risposta a un'altra domanda.
  List<DeviationReport> get activeReports =>
      reports.where((r) => !r.notice.startsAfter(checkedAt)).toList();

  /// Quello che comincera'. Non si nasconde: sapere in anticipo che dal
  /// 24 agosto la tua fermata salta e' utile. Si tiene solo separato.
  List<DeviationReport> get scheduledReports =>
      reports.where((r) => r.notice.startsAfter(checkedAt)).toList();

  /// Tutte le fermate non servite, da tutti gli avvisi attivi.
  /// Una linea puo' avere piu' deviazioni contemporanee (§10.14).
  List<StopImpact> get allSkippedStops =>
      activeReports.expand((r) => r.skippedStops).toList();
}

/// La facciata del sistema: da una linea al suo stato.
///
/// Tutto il calcolo avviene **per singola linea, su richiesta**. Non si
/// monitora la rete intera: il vincolo geografico del geocoding e' il
/// percorso di QUELLA linea, ed e' proprio questo a rendere il passaggio
/// testo-geometria affidabile.
class DeviationService {
  DeviationService({
    required this.index,
    required LlmClient llm,
    Geocoder? geocoder,
    RouteBuilder? router,
    AlertsSource? alerts,
    VariazioniSource? variazioni,
    this.algoritmo = AlgoritmoPercorsi.primo,
  })  : _extractor = NoticeExtractor(llm: llm),
        _alerts = alerts ?? AlertsSource(),
        _variazioni = variazioni ?? VariazioniSource(),
        _resolver = LineResolver(index),
        _impact = StopImpactAnalyzer(index: index) {
    final g = geocoder ?? Geocoder();
    final r = router ?? RouteBuilder();
    _ricostruzione = switch (algoritmo) {
      AlgoritmoPercorsi.primo =>
        Ricostruzione1(geocoder: g, router: r, impact: _impact),
      AlgoritmoPercorsi.secondo =>
        Ricostruzione2(geocoder: g, router: r, impact: _impact),
    };
  }

  final GtfsIndex index;

  /// Quale algoritmo calcola i percorsi deviati: vedi [AlgoritmoPercorsi].
  final AlgoritmoPercorsi algoritmo;
  final NoticeExtractor _extractor;
  final AlertsSource _alerts;
  final VariazioniSource _variazioni;
  final LineResolver _resolver;
  final StopImpactAnalyzer _impact;
  late final Ricostruzione _ricostruzione;

  /// Le letture gia' fatte in questa istanza, per avviso e testo.
  ///
  /// Nel job centrale lo stesso avviso riguarda spesso piu' linee — una
  /// manifestazione in centro ne devia dieci — e ognuna lo analizza contro
  /// il proprio percorso. Il testo pero' e' lo stesso: si legge una volta.
  /// Gli errori non si tengono, cosi' la linea dopo puo' ritentare.
  final Map<String, ExtractionResult> _letture = {};

  /// Quante letture sono state davvero chieste al modello.
  int letture = 0;

  /// Gli avvisi di tutte le fonti, presi una volta e riusati per tutte le
  /// linee della watchlist: sono due richieste, non due per linea.
  ///
  /// Qui le due liste si concatenano e basta: i doppioni fra le fonti li
  /// toglie [noticesFor], perche' per riconoscerli serve sapere di quale
  /// linea si sta parlando. Due variazioni diverse in due quartieri
  /// diversi possono nominare le stesse vie.
  Future<List<RawNotice>> fetchAllNotices() async {
    final out = <RawNotice>[];
    try {
      out.addAll(await _alerts.fetch());
    } on Object {
      // Una fonte che cade non deve far cadere l'altra.
    }
    try {
      out.addAll(await _variazioni.fetch());
    } on Object {
      // idem
    }
    return out;
  }

  /// Gli avvisi che riguardano [line], fra quelli gia' scaricati, con i
  /// doppioni fra le due fonti gia' uniti.
  ///
  /// L'unione avviene qui e non a monte perche' e' qui che si sa di quale
  /// linea si parla, ed e' la linea a distinguere due variazioni che
  /// nominano le stesse vie. Vale anche il contrario: una riga della
  /// tabella copre spesso piu' linee, e si unisce all'alert di ognuna.
  List<RawNotice> noticesFor(TransitLine line, List<RawNotice> all) {
    final out = <RawNotice>[];
    for (final n in all) {
      if (!n.mentionsRouteChange) continue;

      // Dagli alert il route_id arriva gia' canonico: niente da risolvere.
      if (n.routeIds.contains(line.routeId)) {
        out.add(n);
        continue;
      }
      // Dalla tabella web il nome e' scritto da un umano.
      for (final hint in n.lineHints) {
        if (_resolver
            .resolve(hint)
            .resolved
            .any((l) => l.routeId == line.routeId)) {
          out.add(n);
          break;
        }
      }
    }
    return NoticeMerge.dedupe(out);
  }

  /// Lo stato completo di una linea.
  ///
  /// [direction] 0 o 1. Se [allNotices] e' gia' disponibile lo si passa,
  /// per non riscaricare gli avvisi a ogni linea.
  ///
  /// [previous] e' l'esito precedente della stessa linea: gli avvisi che
  /// non sono cambiati da allora non si rileggono (vedi [_giaLetto]).
  Future<LineStatus> statusOf(
    TransitLine line, {
    List<RawNotice>? allNotices,
    LineStatus? previous,
    void Function(String phase)? onProgress,
  }) async {
    final andata = index.mainShape(line.routeId, 0);
    final ritorno = index.mainShape(line.routeId, 1);
    final shape = andata ?? ritorno;
    if (shape == null) {
      throw StateError('nessuna geometria per ${line.shortName}');
    }

    if (allNotices == null) onProgress?.call('Download degli avvisi');
    final notices = noticesFor(line, allNotices ?? await fetchAllNotices());
    final reports = <DeviationReport>[];

    if (notices.isEmpty) onProgress?.call('Nessun avviso');

    for (var i = 0; i < notices.length; i++) {
      final notice = notices[i];
      // "Avviso 2 di 4" invece di un generico "sto lavorando": e' l'unica
      // cosa che fa capire quanto manca. Un controllo puo' durare mezzo
      // minuto, e mezzo minuto davanti a una rotella muta sembra un
      // blocco.
      final quale = notices.length == 1
          ? 'Avviso'
          : 'Avviso ${i + 1} di ${notices.length}';
      onProgress?.call(quale);
      // Un avviso puo' riguardare una direzione sola, o entrambe. Va
      // analizzato contro il percorso GIUSTO, altrimenti le fermate
      // saltate sono quelle dell'altro senso di marcia.
      final direzioni = shapesConcernedBy(notice, andata, ritorno);

      final gia = _giaLetto(notice, direzioni, previous, algoritmo.numero);
      if (gia != null) {
        onProgress?.call('$quale · già letto');
        reports.addAll(gia);
        continue;
      }

      // Il testo si legge UNA volta, qualunque sia il numero di direzioni.
      // Prima si leggeva per ogni direzione: un avviso che valeva per
      // andata e ritorno costava due richieste, e la 10N coi suoi sedici
      // avvisi ne consumava trentadue delle cinquanta giornaliere.
      onProgress?.call('$quale · lettura');
      final chiave = '${notice.id}\u0000${notice.fullText}';
      var extraction = _letture[chiave];
      if (extraction == null) {
        letture++;
        extraction = await _extractor.extract(notice);
        if (extraction.status != ExtractionStatus.error) {
          _letture[chiave] = extraction;
        }
      }
      for (final s in direzioni) {
        final r = await _ricostruzione.analizza(notice, s, extraction,
            onProgress: (p) => onProgress?.call('$quale · $p'));
        reports.add(r.conAlgoritmo(algoritmo.numero));
      }
    }

    final now = DateTime.now();
    return LineStatus(
      line: line,
      shape: shape,
      shapeReturn: identical(shape, andata) ? ritorno : null,
      allShapes: index.shapesOf(line.routeId),
      reports: DeviationReport.reconcileAlternatives(reports,
          analyzer: _impact, now: now),
      checkedAt: now,
    );
  }

  /// Gli esiti di [notice] dal controllo precedente, se si possono tenere.
  ///
  /// Si tengono quando l'avviso e' lo stesso — stesso testo, stesse date,
  /// stesse direzioni — e nessuna delle sue analisi era fallita per un
  /// motivo che passa ([DeviationReport.retryable]). Rileggere un testo
  /// identico darebbe lo stesso risultato e costerebbe una richiesta.
  ///
  /// Visto il 26/09: un «Aggiorna tutte» a quota esaurita rimpiazzava le
  /// deviazioni calcolate nel pomeriggio (15, 55, 68) con «non letto».
  /// Con questo le rilegge solo se sono cambiate, e quelle non cambiate
  /// restano.
  ///
  /// Si rifanno anche quando li ha calcolati l'altro algoritmo: tornare al
  /// primo deve ridisegnare tutto, non solo gli avvisi nuovi.
  static List<DeviationReport>? _giaLetto(
    RawNotice notice,
    List<RouteShape> direzioni,
    LineStatus? previous,
    int algoritmo,
  ) {
    if (previous == null) return null;
    final prima =
        previous.reports.where((r) => r.notice.id == notice.id).toList();
    if (prima.isEmpty || prima.any((r) => r.retryable)) return null;
    if (prima.any((r) => r.algoritmo != algoritmo)) return null;
    final n = prima.first.notice;
    final uguale = n.text == notice.text &&
        n.headline == notice.headline &&
        n.validFrom == notice.validFrom &&
        n.validUntil == notice.validUntil;
    if (!uguale) return null;
    final idPrima = {for (final r in prima) r.shape.shapeId};
    final idOra = {for (final s in direzioni) s.shapeId};
    if (idPrima.length != idOra.length || !idPrima.containsAll(idOra)) {
      return null;
    }
    return prima;
  }

  /// Quali direzioni riguarda un avviso.
  ///
  /// GTT lo dice quasi sempre, nominando il capolinea: "nella sola
  /// direzione Derna", "in direzione piazza Statuto". Il confronto e' col
  /// nome del capolinea che sta nel GTFS. Se non si capisce, si analizzano
  /// **entrambe**: meglio due rapporti, uno dei quali superfluo, che uno
  /// solo riferito al senso di marcia sbagliato.
  static List<RouteShape> shapesConcernedBy(
    RawNotice notice,
    RouteShape? andata,
    RouteShape? ritorno,
  ) {
    final both = [?andata, ?ritorno];
    if (both.length < 2) return both;

    final words = _words('${notice.fullText} ${notice.directionHint ?? ''}');
    final matched = both.where((s) {
      // Confronto per PAROLE INTERE, non per sottostringhe: "lavori
      // stradali" conteneva "strada" e faceva scattare il capolinea
      // "STRADA DEL DROSSO", assegnando l'avviso alla direzione sbagliata.
      final head = _words(s.headsign);
      return head.isNotEmpty && head.any(words.contains);
    }).toList();

    return matched.length == 1 ? matched : both;
  }

  /// Parole significative di un testo, per il confronto coi capolinea.
  ///
  /// Si scartano i qualificatori generici: "via", "corso", "strada" e
  /// simili compaiono in ogni avviso e in meta' dei capolinea, quindi
  /// farebbero corrispondere tutto con tutto.
  static const _genericWords = {
    'via', 'viale', 'corso', 'piazza', 'piazzale', 'largo', 'strada',
    'ponte', 'lungo', 'sud', 'nord', 'est', 'ovest', 'della', 'delle',
    'dello', 'degli', 'linea', 'direzione', 'entrambe', 'capolinea',
  };

  static Set<String> _words(String s) => s
      .toLowerCase()
      .replaceAll('\u2019', "'")
      .split(RegExp(r"[^a-zà-ù0-9']+"))
      .where((w) => w.length >= 4 && !_genericWords.contains(w))
      .toSet();

  /// Perche' la lettura del testo non e' riuscita, detto a chi usa l'app.
  ///
  /// Non basta dire "errore": alcune cause sono azionabili — la quota
  /// giornaliera si azzera, una chiave sbagliata si corregge — e altre no.
  /// Chi legge deve capire se puo' fare qualcosa o solo aspettare.
  static String lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  static String explainExtractionFailure(ExtractionResult r) {
    final detail = r.detail ?? '';
    if (detail.contains(LlmConBudget.inCoda)) {
      return 'Avviso appena pubblicato: sarà letto a breve.';
    }
    if (detail.contains('free-models-per-day')) {
      // L'orario si dice in ORA LOCALE. Il fornitore ragiona in UTC, ma
      // chi legge il messaggio all'una di notte no: "si azzerano a
      // mezzanotte UTC" sembra sbagliato quando la mezzanotte e' passata
      // da un'ora.
      // Senza un orario dal fornitore, la mezzanotte UTC detta in ora
      // locale: le 2 d'estate, l'una d'inverno. Prima era scritto «alle 2
      // di notte» fisso, sbagliato per metà dell'anno.
      final when = _localTime(r.retryAfter ?? _nextUtcMidnight());
      return 'Richieste gratuite esaurite per oggi (50 al giorno). '
          'Riprova dopo le $when.';
    }
    if (detail.contains('429')) {
      return 'Servizio momentaneamente sovraccarico. Riprova fra poco.';
    }
    if (detail.contains('401') || detail.contains('403')) {
      return 'La chiave non è valida. Controllala nelle impostazioni.';
    }
    if (detail.contains('non raggiungibile') ||
        detail.contains('TimeoutException')) {
      return 'Servizio non raggiungibile. Controlla la connessione.';
    }
    if (r.status == ExtractionStatus.parseFailed) {
      return 'L\'avviso non descrive un percorso ricostruibile.';
    }
    return 'Non è stato possibile leggere l\'avviso.';
  }

  /// L'orario in cui riprovare, nel fuso di chi legge.
  static DateTime _nextUtcMidnight() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day + 1);
  }

  static String? _localTime(DateTime? utcOrLocal) {
    if (utcOrLocal == null) return null;
    final t = utcOrLocal.toLocal();
    return '${t.hour.toString().padLeft(2, "0")}:'
        '${t.minute.toString().padLeft(2, "0")}';
  }
}
