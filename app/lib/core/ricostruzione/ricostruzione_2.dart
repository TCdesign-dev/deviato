import '../deviation_service.dart';
import '../geo/projection.dart';
import '../models/notice.dart';
import '../models/transit.dart';
import '../pipeline/extractor.dart';
import '../pipeline/geocoder.dart';
import '../pipeline/rejoin_inference.dart';
import '../pipeline/route_builder.dart';
import '../config.dart';
import '../pipeline/stop_impact.dart';
import 'ricostruzione.dart';
import 'rifinitura.dart';
import 'scelta_direzione.dart';

/// Il secondo algoritmo: nato il 28/09/2026 come copia identica del
/// primo, e' quello da correggere.
///
/// I difetti misurati sulle 66 deviazioni disegnate quel giorno: vie
/// lunghe ridotte a un punto che obbliga il percorso ad andare e tornare,
/// l'incrocio dello stacco («angolo corso Vinzaglio») ignorato, un elenco
/// di vie usato per tutte e due le direzioni, inizio e fine lontani dalla
/// linea. Il primo resta com'era in [Ricostruzione1].
///
/// Cosa cambia rispetto al primo, finora:
/// - ogni direzione usa il suo elenco di vie ([SceltaDirezione]); un
///   elenco senza direzione vale per tutte e due, e dove sulla mappa va al
///   contrario si gira;
/// - lo stacco e il rientro dichiarato si agganciano alla linea normale, e
///   il punto trovato per la via dello stacco non diventa una tappa: e' una
///   via lunga quanto la linea, e il suo punto cade dove capita;
/// - il rosso perde i pezzi che corrono sopra la linea normale;
/// - tre controlli in piu' ([Rifinitura.controlla]): inizio o fine lontani
///   dalla linea, verso contrario, andare e tornare sulla stessa via.
class Ricostruzione2 implements Ricostruzione {
  Ricostruzione2({
    required this._geocoder,
    required this._router,
    required this._impact,
  });

  final Geocoder _geocoder;
  final RouteBuilder _router;
  final StopImpactAnalyzer _impact;

  @override
  Future<DeviationReport> analizza(
    RawNotice notice,
    RouteShape shape,
    ExtractionResult extraction, {
    void Function(String phase)? onProgress,
  }) async {
    // 1. Testo -> struttura: gia' fatto, una volta per avviso.
    //
    // Un errore del modello (quota, rete, chiave) passa; un testo che non
    // descrive un percorso no.
    final estrazioneDaRitentare = extraction.status == ExtractionStatus.error;
    if (!extraction.isUsable) {
      // L'LLM non ha risposto — quota finita, rete, servizio giu'. Ma se
      // GTT ha scritto un numero di fermata, quel numero sta nel testo e
      // lo prende una regex: non serve nessun modello per leggerlo.
      // Sarebbe assurdo perdere il dato piu' certo che abbiamo proprio
      // quando tutto il resto non funziona.
      final impact = _impact.declaredOnly(
        officialRoute: shape,
        declaredCodes: notice.suspendedStopCodes.toSet(),
      );
      if (impact.hasImpact) {
        return DeviationReport(
          notice: notice,
          shape: shape,
          impact: impact,
          // Non "confermata": senza estrazione non sappiamo se l'avviso
          // dica anche altro, per esempio un cambio di percorso che non
          // abbiamo ricostruito.
          confidence: Confidence.probabile,
          whyIncomplete:
              'La fermata sospesa è indicata da GTT. Il resto '
              'dell\'avviso non è stato letto: '
              '${DeviationService.lowerFirst(DeviationService.explainExtractionFailure(extraction))}',
          retryable: estrazioneDaRitentare,
        );
      }
      return DeviationReport(
        notice: notice,
        shape: shape,
        confidence: Confidence.soloTesto,
        whyIncomplete: DeviationService.explainExtractionFailure(extraction),
        retryable: estrazioneDaRitentare,
      );
    }
    // 1-ter. Quale elenco di vie vale per questa direzione.
    final scelta = SceltaDirezione.per(extraction.deviations, shape);
    var parsed = scelta.deviazione;
    if (!scelta.esplicita) {
      // Nessuna nomina il nostro capolinea. Se le candidate sono piu' d'una
      // si prende quella che sulla mappa va nel nostro verso.
      final candidate = SceltaDirezione.candidate(extraction.deviations, shape);
      if (candidate.length > 1) {
        for (final c in candidate) {
          final g = await _cerca(c, shape, onProgress);
          if (g.punti.length >= 2 && !_alContrario(g.punti, shape)) {
            parsed = c;
            break;
          }
        }
      }
    }

    // Una sostituzione di mezzo non cambia il percorso: mostrarla come
    // deviazione sarebbe un allarme falso (§10.10).
    if (parsed.type == DeviationType.sostituzioneModale) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.confermata,
        whyIncomplete: 'Stesso percorso, cambia solo il tipo di mezzo.',
      );
    }

    // 1-bis. Fermate sospese senza cambio di percorso.
    //
    // MISURATO: 14 avvisi su 198 dicono soltanto "Fermata 3447 Sabotino
    // sospesa". Il codice sta nel testo, non in informed_entity, e si
    // estrae con una regex. Prima finivano nel ramo "non nomina abbastanza
    // vie" e l'informazione si perdeva, pur essendo la piu' certa che il
    // sistema abbia: nessuna geometria da ricostruire, solo un codice da
    // cercare nel GTFS.
    final declaredCodes = <String>{
      ...notice.suspendedStopCodes,
      ...parsed.suspendedStopCodes,
    };
    if (declaredCodes.isNotEmpty && parsed.viaSequence.isEmpty) {
      final impact = _impact.declaredOnly(
        officialRoute: shape,
        declaredCodes: declaredCodes,
      );
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        impact: impact,
        confidence: Confidence.confermata,
        whyIncomplete: impact.hasImpact
            ? null
            : declaredCodes.length == 1
            ? 'La fermata ${declaredCodes.first} indicata da GTT non è '
                  'su questo percorso.'
            : 'Le fermate ${declaredCodes.join(", ")} indicate da GTT '
                  'non sono su questo percorso.',
      );
    }

    // 2. Toponimi -> coordinate, vincolate al percorso di questa linea.
    final toponyms = parsed.allToponyms;
    if (toponyms.length < 2) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.soloTesto,
        whyIncomplete:
            'L\'avviso non indica abbastanza vie per disegnare '
            'il percorso.',
      );
    }

    final cercate = await _cerca(parsed, shape, onProgress);
    var points = cercate.punti;
    final unresolved = cercate.nonTrovate;
    // Photon non raggiungibile non e' «via non trovata»: si ritenta.
    final geocodingInErrore = cercate.inErrore;
    if (points.length < 2) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.soloTesto,
        whyIncomplete: 'Vie non trovate sulla mappa: ${unresolved.join(", ")}.',
        retryable: geocodingInErrore,
      );
    }

    // 2-bis. Dove rientra.
    //
    // MISURATO: 24 avvisi su 28 non nominano la via di rientro, dicono solo
    // "percorso normale". Senza dedurlo il percorso deviato si ferma
    // all'ultima via nominata, il tratto di linea interessato resta
    // troncato, e le fermate fra li' e il rientro vero non vengono valutate.
    // Un elenco senza direzione e' scritto nel verso di una delle due: per
    // l'altra si legge al contrario. La via dello stacco diventa quella
    // del rientro, che sta sulla linea: il rientro si deduce.
    var girato = false;
    var rientroDichiarato = parsed.rejoinStreet != null;
    if (!scelta.esplicita && _alContrario(points, shape)) {
      points = points.reversed.toList();
      girato = true;
      rientroDichiarato = false;
    }

    // Lo stacco sta sulla linea normale, per definizione: «da corso
    // Vittorio» vuol dire dal punto in cui il bus lascia corso Vittorio.
    // Il punto che Photon da' per una via lunga cade dove capita — la 9
    // partiva 547 m piu' in la' — e si aggancia alla linea.
    final stacco = Rifinitura.aggancia(points.first, shape);
    final staccoSullaLinea = stacco.distanza <= GttConfig.geocodeBufferMeters;
    final primo = staccoSullaLinea ? stacco.punto : points.first;

    final RejoinPoint rejoin;
    if (rientroDichiarato) {
      // GTT l'ha detto. Anche qui si aggancia alla linea, a valle dello
      // stacco: e' li' che il bus riprende il percorso normale.
      final r = Rifinitura.aggancia(
        points.last,
        shape,
        daMetri: staccoSullaLinea ? stacco.metri : 0,
      );
      rejoin = RejoinPoint(
        source: RejoinSource.dichiarato,
        point: r.distanza <= GttConfig.geocodeBufferMeters
            ? r.punto
            : points.last,
        alongMeters: r.metri,
        metersFromRoute: r.distanza,
      );
    } else {
      rejoin = RejoinInference.infer(
        officialRoute: shape,
        detachPoint: points.first,
        lastVia: points.last,
      );
    }

    // Le tappe: lo stacco sulla linea, le vie in mezzo, il rientro. Le vie
    // in mezzo restano punti di Photon: il passo che le sostituira' con gli
    // incroci fra una via e l'altra deve ancora venire.
    final inMezzo = points.sublist(
      1,
      rientroDichiarato ? points.length - 1 : points.length,
    );
    final waypoints = [
      primo,
      ...inMezzo,
      if (rejoin.isUsable)
        rejoin.point!
      else if (rientroDichiarato)
        points.last,
    ];

    // 3. Punti -> percorso vero, con le cinque prove.
    onProgress?.call('calcolo del percorso');
    final route = await _router.build(
      waypoints: waypoints,
      officialRoute: shape,
      // Le vie da attraversare restano quelle NOMINATE in mezzo: stacco e
      // rientro ora stanno sulla linea, e il punto di Photon per la loro
      // via puo' essere lontano da dove il bus la usa.
      requiredVias: inMezzo,
    );
    if (route.geometry == null) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        rejoin: rejoin,
        confidence: Confidence.soloTesto,
        whyIncomplete: 'Non è stato possibile calcolare il percorso deviato.',
        retryable: geocodingInErrore || route.status == RouteBuildStatus.error,
      );
    }

    // 3-bis. Il rosso solo dove il bus sta davvero altrove, e i controlli
    // che le cinque prove non fanno.
    final rifinita = Rifinitura.taglia(route.geometry!, shape);
    if (rifinita.isEmpty) {
      // Tutto il percorso calcolato sta sopra la linea normale: non c'e'
      // niente da disegnare, e disegnarlo farebbe credere a una deviazione
      // su vie dove il bus passa comunque.
      final dichiarate = <String>{
        ...notice.suspendedStopCodes,
        ...parsed.suspendedStopCodes,
      };
      final impact = dichiarate.isEmpty
          ? null
          : _impact.declaredOnly(
              officialRoute: shape,
              declaredCodes: dichiarate,
            );
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        rejoin: rejoin,
        impact: impact,
        confidence: impact != null && impact.hasImpact
            ? Confidence.probabile
            : Confidence.soloTesto,
        whyIncomplete: 'Non è stato possibile calcolare il percorso deviato.',
        retryable: geocodingInErrore,
      );
    }
    final problemi = Rifinitura.controlla(rifinita, shape);
    final tuttoBene =
        route.isUsable && unresolved.isEmpty && problemi.isEmpty && !girato;

    // 4. Quali fermate saltano.
    final impact = _impact.analyze(
      officialRoute: shape,
      deviatedRoute: rifinita,
      declaredSuspendedCodes: {
        ...notice.suspendedStopCodes,
        ...parsed.suspendedStopCodes,
      },
    );

    return DeviationReport(
      notice: notice,
      shape: shape,
      parsed: parsed,
      rejoin: rejoin,
      deviatedGeometry: rifinita,
      impact: impact,
      confidence: tuttoBene ? Confidence.confermata : Confidence.probabile,
      whyIncomplete: tuttoBene
          ? null
          // Frasi per chi legge, non l'elenco delle prove fallite: «lungo
          // 4,1 km per sostituire 1,2 km (3,4x, max 3x)» e' utile a chi
          // tara le soglie (lo stampano gli strumenti in tool/), non a chi
          // aspetta il bus.
          : [
              if (unresolved.isNotEmpty)
                'Vie non trovate sulla mappa: ${unresolved.join(", ")}.',
              if (!rejoin.isUsable) 'Il punto di rientro è incerto.',
              if (girato)
                'GTT descrive il percorso di una direzione sola: questo è '
                    'ricavato al contrario.',
              if (route.failures.isNotEmpty || problemi.isNotEmpty)
                'Il percorso calcolato non corrisponde del tutto all\'avviso.',
            ].join(' '),
      // Una via non trovata perche' Photon non rispondeva potrebbe
      // completare il percorso al prossimo giro.
      retryable: geocodingInErrore,
    );
  }

  /// Le vie di [parsed] sulla mappa, nell'ordine dell'avviso.
  Future<({List<GeoPoint> punti, List<String> nonTrovate, bool inErrore})>
  _cerca(
    ParsedDeviation parsed,
    RouteShape shape,
    void Function(String phase)? onProgress,
  ) async {
    final punti = <GeoPoint>[];
    final nonTrovate = <String>[];
    var inErrore = false;
    for (final t in parsed.allToponyms) {
      // Il geocoding e' il passaggio piu' lento: una chiamata per via,
      // con le pause di cortesia verso Photon. Vale la pena dire a che
      // punto e', e quale via si sta cercando.
      onProgress?.call('ricerca di «$t»');
      final r = await _geocoder.locate(
        t,
        near: shape,
        municipality: parsed.municipality,
      );
      if (r.isUsable) {
        punti.add(r.point!);
      } else {
        nonTrovate.add(t);
        if (r.status == GeocodeStatus.error) inErrore = true;
      }
    }
    return (punti: punti, nonTrovate: nonTrovate, inErrore: inErrore);
  }

  /// Le vie, messe sulla linea normale, vanno all'indietro: la prima sta
  /// piu' avanti dell'ultima. Con un margine, perche' un punto per via e'
  /// impreciso.
  static bool _alContrario(List<GeoPoint> punti, RouteShape shape) {
    if (punti.length < 2) return false;
    final primo = Rifinitura.aggancia(punti.first, shape).metri;
    final ultimo = Rifinitura.aggancia(punti.last, shape).metri;
    return ultimo < primo - _margineVerso;
  }

  static const _margineVerso = 200.0;
}
